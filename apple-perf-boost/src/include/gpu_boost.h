/*
 * gpu_boost.h - Apple GPU (Metal) Performance Optimization (Non-Malicious)
 *
 * Legitimate GPU performance tricks via public Metal & CoreGraphics APIs:
 *   - Shader compilation caching / warming
 *   - Optimal buffer storage modes
 *   - Command buffer priority
 *   - GPU occupancy hints
 *   - Thermal-aware workload scheduling
 *
 * Copyright 2026 - Apache 2.0 License
 */

#ifndef GPU_BOOST_H
#define GPU_BOOST_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* - Result codes */
typedef enum {
    GPU_BOOST_OK            =  0,
    GPU_BOOST_ERR_NO_DEVICE = -1,
    GPU_BOOST_ERR_PIPELINE  = -2,
    GPU_BOOST_ERR_BUFFER    = -3,
    GPU_BOOST_ERR_PLATFORM  = -4,
} gpu_boost_result_t;

/* - Opaque handle to the GPU boost context (wraps MTLDevice) - */
typedef struct gpu_boost_ctx gpu_boost_ctx_t;

/**
 * Initialise the GPU boost context on the default Metal device.
 * Returns NULL if Metal is unavailable.
 */
gpu_boost_ctx_t *gpu_boost_create(void);

/** Tear down the GPU boost context and release Metal objects. */
void gpu_boost_destroy(gpu_boost_ctx_t *ctx);

/* - Shader cache warm-up */

/**
 * Pre-compile a Metal shader library from source and cache the PSO.
 * Call during app startup to eliminate first-frame stutter.
 *
 * @param ctx       GPU context
 * @param source    Metal Shading Language source (UTF-8)
 * @param fn_name   Kernel / vertex / fragment function name
 */
gpu_boost_result_t gpu_boost_warm_shader(gpu_boost_ctx_t *ctx,
                                         const char *source,
                                         const char *fn_name);

/**
 * Pre-compile a shader from a .metallib file path.
 */
gpu_boost_result_t gpu_boost_warm_shader_from_lib(gpu_boost_ctx_t *ctx,
                                                  const char *metallib_path,
                                                  const char *fn_name);

/* - Buffer management */

typedef enum {
    GPU_BUF_SHARED  = 0,   /* MTLStorageModeShared  - CPU+GPU  */
    GPU_BUF_PRIVATE = 1,   /* MTLStorageModePrivate - GPU-only (fastest) */
    GPU_BUF_MANAGED = 2,   /* MTLStorageModeManaged - explicit sync */
} gpu_buffer_mode_t;

void *gpu_boost_alloc_buffer(gpu_boost_ctx_t *ctx,
                             size_t size,
                             gpu_buffer_mode_t mode);

/** Get the CPU-visible pointer (only valid for SHARED / MANAGED). */
void *gpu_boost_buffer_ptr(void *buffer_handle);

void gpu_boost_free_buffer(void *buffer_handle);

/**
 * Submit a compute kernel with elevated GPU priority.
 * Uses MTLCommandBuffer priority hint for lower latency.
 *
 * @param ctx         GPU context
 * @param fn_name     Previously warmed function name
 * @param grid_x/y/z  Thread-group grid dimensions
 * @param tg_x/y/z    Threads-per-threadgroup
 * @param buffers      Array of buffer handles
 * @param buf_count    Number of buffers
 */
gpu_boost_result_t gpu_boost_dispatch_compute(gpu_boost_ctx_t *ctx,
                                              const char *fn_name,
                                              uint32_t grid_x, uint32_t grid_y, uint32_t grid_z,
                                              uint32_t tg_x,   uint32_t tg_y,   uint32_t tg_z,
                                              void **buffers, uint32_t buf_count);

/* - Device info / diagnostics  */

typedef struct {
    const char *device_name;
    uint64_t    recommended_max_working_set_size;
    uint64_t    current_allocated_size;
    uint32_t    max_threads_per_threadgroup;
    uint32_t    max_buffer_length;
    bool        supports_raytracing;
    bool        supports_mesh_shaders;
    int32_t     gpu_family;      /* MTLGPUFamily raw value */
} gpu_boost_device_info_t;

/**
 * Query GPU device capabilities to tune workloads at runtime.
 */
gpu_boost_result_t gpu_boost_device_info(gpu_boost_ctx_t *ctx,
                                         gpu_boost_device_info_t *out);

uint32_t gpu_boost_optimal_threadgroup(gpu_boost_ctx_t *ctx,
                                       const char *fn_name);

#ifdef __cplusplus
}
#endif

#endif /* GPU_BOOST_H */
