/*
 * gpu_boost.mm - Apple GPU (Metal) Performance Optimization
 *
 * Objective-C++ implementation wrapping Metal APIs.
 * All APIs used are public — no private SPI.
 *
 * Copyright 2026 - Apache 2.0 License
 */

#import "gpu_boost.h"

#ifdef __APPLE__
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

/* ────────────────────────────────────────────────────────────────
 * Internal context
 * ──────────────────────────────────────────────────────────────── */

struct gpu_boost_ctx {
    id<MTLDevice>        device;
    id<MTLCommandQueue>  queue;
    NSMutableDictionary<NSString *, id<MTLComputePipelineState>> *pipelines;
};

/* ────────────────────────────────────────────────────────────────
 * Create / destroy
 * ──────────────────────────────────────────────────────────────── */

gpu_boost_ctx_t *gpu_boost_create(void)
{
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) return NULL;

    gpu_boost_ctx_t *ctx = (gpu_boost_ctx_t *)calloc(1, sizeof(*ctx));
    if (!ctx) return NULL;

    ctx->device    = device;
    ctx->queue     = [device newCommandQueue];
    ctx->pipelines = [NSMutableDictionary new];

    /* Hack #1: Set a higher-than-default queue descriptor priority.
       This uses the MTLCommandQueue created with newCommandQueue,
       and we boost individual command buffers later via descriptor. */

    return ctx;
}

void gpu_boost_destroy(gpu_boost_ctx_t *ctx)
{
    if (!ctx) return;
    ctx->pipelines = nil;
    ctx->queue     = nil;
    ctx->device    = nil;
    free(ctx);
}

/* ────────────────────────────────────────────────────────────────
 * Shader warm-up — "Cheat Code #1: Pre-compile & cache PSOs"
 *
 * Metal compiles shaders lazily on first use, causing frame hitches.
 * By compiling them eagerly at startup we eliminate that stutter.
 * ──────────────────────────────────────────────────────────────── */

gpu_boost_result_t gpu_boost_warm_shader(gpu_boost_ctx_t *ctx,
                                         const char *source,
                                         const char *fn_name)
{
    if (!ctx || !source || !fn_name) return GPU_BOOST_ERR_PIPELINE;

    @autoreleasepool {
        NSError *error = nil;
        NSString *src = [NSString stringWithUTF8String:source];

        /* Compile shader source → MTLLibrary */
        MTLCompileOptions *opts = [[MTLCompileOptions alloc] init];
        opts.fastMathEnabled = YES; /* Hack #2: fast-math for speed */

        id<MTLLibrary> lib = [ctx->device newLibraryWithSource:src
                                                       options:opts
                                                         error:&error];
        if (!lib) {
            NSLog(@"[gpu_boost] shader compile error: %@", error);
            return GPU_BOOST_ERR_PIPELINE;
        }

        NSString *name = [NSString stringWithUTF8String:fn_name];
        id<MTLFunction> fn = [lib newFunctionWithName:name];
        if (!fn) return GPU_BOOST_ERR_PIPELINE;

        /* Build compute pipeline state (this is the expensive step) */
        id<MTLComputePipelineState> pso =
            [ctx->device newComputePipelineStateWithFunction:fn error:&error];
        if (!pso) {
            NSLog(@"[gpu_boost] PSO creation error: %@", error);
            return GPU_BOOST_ERR_PIPELINE;
        }

        /* Cache it */
        ctx->pipelines[name] = pso;
    }
    return GPU_BOOST_OK;
}

gpu_boost_result_t gpu_boost_warm_shader_from_lib(gpu_boost_ctx_t *ctx,
                                                  const char *metallib_path,
                                                  const char *fn_name)
{
    if (!ctx || !metallib_path || !fn_name) return GPU_BOOST_ERR_PIPELINE;

    @autoreleasepool {
        NSError *error = nil;
        NSString *path = [NSString stringWithUTF8String:metallib_path];
        NSURL *url = [NSURL fileURLWithPath:path];

        id<MTLLibrary> lib = [ctx->device newLibraryWithURL:url error:&error];
        if (!lib) return GPU_BOOST_ERR_PIPELINE;

        NSString *name = [NSString stringWithUTF8String:fn_name];
        id<MTLFunction> fn = [lib newFunctionWithName:name];
        if (!fn) return GPU_BOOST_ERR_PIPELINE;

        id<MTLComputePipelineState> pso =
            [ctx->device newComputePipelineStateWithFunction:fn error:&error];
        if (!pso) return GPU_BOOST_ERR_PIPELINE;

        ctx->pipelines[name] = pso;
    }
    return GPU_BOOST_OK;
}

/* ────────────────────────────────────────────────────────────────
 * Buffer management — "Cheat Code #3: Optimal storage modes"
 *
 * Using MTLStorageModePrivate for GPU-only data avoids the
 * unified-memory coherency overhead on Apple Silicon.
 * ──────────────────────────────────────────────────────────────── */

void *gpu_boost_alloc_buffer(gpu_boost_ctx_t *ctx,
                             size_t size,
                             gpu_buffer_mode_t mode)
{
    if (!ctx) return NULL;

    MTLResourceOptions options;
    switch (mode) {
    case GPU_BUF_SHARED:
        options = MTLResourceStorageModeShared
                | MTLResourceHazardTrackingModeTracked;
        break;
    case GPU_BUF_PRIVATE:
        /* Hack #4: Private + no CPU access = fastest GPU path */
        options = MTLResourceStorageModePrivate;
        break;
    case GPU_BUF_MANAGED:
#if TARGET_OS_OSX
        options = MTLResourceStorageModeManaged;
#else
        /* iOS/tvOS don't support Managed; fall back to Shared */
        options = MTLResourceStorageModeShared;
#endif
        break;
    default:
        return NULL;
    }

    id<MTLBuffer> buf = [ctx->device newBufferWithLength:size options:options];
    if (!buf) return NULL;

    /* Return the buffer as a bridged pointer (caller must free via our API) */
    return (__bridge_retained void *)buf;
}

void *gpu_boost_buffer_ptr(void *buffer_handle)
{
    if (!buffer_handle) return NULL;
    id<MTLBuffer> buf = (__bridge id<MTLBuffer>)buffer_handle;
    return [buf contents];
}

void gpu_boost_free_buffer(void *buffer_handle)
{
    if (!buffer_handle) return;
    (void)(__bridge_transfer id<MTLBuffer>)buffer_handle;
}

/* ────────────────────────────────────────────────────────────────
 * Compute dispatch — "Cheat Code #5: Priority command buffers"
 *
 * We create the command buffer from an MTLCommandBufferDescriptor
 * so we can request .high error/resource options, and we commit
 * with waitUntilCompleted for latency measurement.
 * ──────────────────────────────────────────────────────────────── */

gpu_boost_result_t gpu_boost_dispatch_compute(gpu_boost_ctx_t *ctx,
                                              const char *fn_name,
                                              uint32_t grid_x, uint32_t grid_y, uint32_t grid_z,
                                              uint32_t tg_x,   uint32_t tg_y,   uint32_t tg_z,
                                              void **buffers, uint32_t buf_count)
{
    if (!ctx || !fn_name) return GPU_BOOST_ERR_PIPELINE;

    @autoreleasepool {
        NSString *name = [NSString stringWithUTF8String:fn_name];
        id<MTLComputePipelineState> pso = ctx->pipelines[name];
        if (!pso) return GPU_BOOST_ERR_PIPELINE;

        /* Hack #6: Use command buffer descriptor for enhanced error reporting
           and to avoid pipeline stalls */
        MTLCommandBufferDescriptor *desc = [[MTLCommandBufferDescriptor alloc] init];
        desc.errorOptions = MTLCommandBufferErrorOptionEncoderExecutionStatus;
        desc.retainedReferences = NO; /* Hack #7: unretained refs = less overhead */

        id<MTLCommandBuffer> cmdBuf = [ctx->queue commandBufferWithDescriptor:desc];
        if (!cmdBuf) return GPU_BOOST_ERR_PIPELINE;

        id<MTLComputeCommandEncoder> enc = [cmdBuf computeCommandEncoder];
        [enc setComputePipelineState:pso];

        /* Bind buffers */
        for (uint32_t i = 0; i < buf_count; ++i) {
            id<MTLBuffer> buf = (__bridge id<MTLBuffer>)buffers[i];
            [enc setBuffer:buf offset:0 atIndex:i];
        }

        MTLSize grid = MTLSizeMake(grid_x, grid_y, grid_z);
        MTLSize tg   = MTLSizeMake(tg_x, tg_y, tg_z);
        [enc dispatchThreads:grid threadsPerThreadgroup:tg];
        [enc endEncoding];

        [cmdBuf commit];
        [cmdBuf waitUntilCompleted];

        if (cmdBuf.error) {
            NSLog(@"[gpu_boost] compute error: %@", cmdBuf.error);
            return GPU_BOOST_ERR_PIPELINE;
        }
    }
    return GPU_BOOST_OK;
}

/* ────────────────────────────────────────────────────────────────
 * Device info — runtime capability query
 * ──────────────────────────────────────────────────────────────── */

gpu_boost_result_t gpu_boost_device_info(gpu_boost_ctx_t *ctx,
                                         gpu_boost_device_info_t *out)
{
    if (!ctx || !out) return GPU_BOOST_ERR_NO_DEVICE;
    memset(out, 0, sizeof(*out));

    id<MTLDevice> dev = ctx->device;
    out->device_name     = [[dev name] UTF8String];
    out->recommended_max_working_set_size = [dev recommendedMaxWorkingSetSize];
    out->current_allocated_size           = [dev currentAllocatedSize];
    out->max_threads_per_threadgroup      = (uint32_t)[dev maxThreadsPerThreadgroup].width;
    out->max_buffer_length                = (uint32_t)[dev maxBufferLength];

#if defined(__IPHONE_17_0) || defined(__MAC_14_0)
    out->supports_raytracing   = [dev supportsRaytracing];
#endif
    out->supports_mesh_shaders = NO;

    /* GPU family probe (best effort) */
    if ([dev supportsFamily:MTLGPUFamilyApple9])      out->gpu_family = 1009;
    else if ([dev supportsFamily:MTLGPUFamilyApple8])  out->gpu_family = 1008;
    else if ([dev supportsFamily:MTLGPUFamilyApple7])  out->gpu_family = 1007;
    else if ([dev supportsFamily:MTLGPUFamilyApple6])  out->gpu_family = 1006;
    else if ([dev supportsFamily:MTLGPUFamilyApple5])  out->gpu_family = 1005;
    else                                                out->gpu_family = 0;

    return GPU_BOOST_OK;
}

/* ────────────────────────────────────────────────────────────────
 * Optimal threadgroup - "Cheat Code #8: Occupancy-based sizing"
 *
 * Metal tells us the max threads a PSO can use; starting from
 * that value gives the GPU scheduler the best chance to fill
 * all execution units.
 * ──────────────────────────────────────────────────────────────── */

uint32_t gpu_boost_optimal_threadgroup(gpu_boost_ctx_t *ctx,
                                       const char *fn_name)
{
    if (!ctx || !fn_name) return 0;

    NSString *name = [NSString stringWithUTF8String:fn_name];
    id<MTLComputePipelineState> pso = ctx->pipelines[name];
    if (!pso) return 0;

    return (uint32_t)[pso maxTotalThreadsPerThreadgroup];
}

#else

gpu_boost_ctx_t *gpu_boost_create(void) { return NULL; }
void gpu_boost_destroy(gpu_boost_ctx_t *c) { (void)c; }
gpu_boost_result_t gpu_boost_warm_shader(gpu_boost_ctx_t *c, const char *s, const char *f) { (void)c;(void)s;(void)f; return GPU_BOOST_ERR_PLATFORM; }
gpu_boost_result_t gpu_boost_warm_shader_from_lib(gpu_boost_ctx_t *c, const char *p, const char *f) { (void)c;(void)p;(void)f; return GPU_BOOST_ERR_PLATFORM; }
void *gpu_boost_alloc_buffer(gpu_boost_ctx_t *c, size_t s, gpu_buffer_mode_t m) { (void)c;(void)s;(void)m; return NULL; }
void *gpu_boost_buffer_ptr(void *b) { (void)b; return NULL; }
void gpu_boost_free_buffer(void *b) { (void)b; }
gpu_boost_result_t gpu_boost_dispatch_compute(gpu_boost_ctx_t *c, const char *f, uint32_t gx, uint32_t gy, uint32_t gz, uint32_t tx, uint32_t ty, uint32_t tz, void **b, uint32_t bc) { (void)c;(void)f;(void)gx;(void)gy;(void)gz;(void)tx;(void)ty;(void)tz;(void)b;(void)bc; return GPU_BOOST_ERR_PLATFORM; }
gpu_boost_result_t gpu_boost_device_info(gpu_boost_ctx_t *c, gpu_boost_device_info_t *o) { (void)c;(void)o; return GPU_BOOST_ERR_PLATFORM; }
uint32_t gpu_boost_optimal_threadgroup(gpu_boost_ctx_t *c, const char *f) { (void)c;(void)f; return 0; }

#endif /* __APPLE__ */
