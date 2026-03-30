/*
 * example_shader.metal - Sample Metal compute shaders
 *
 * Pre-compile these during startup with gpu_boost_warm_shader_from_lib()
 * to eliminate first-frame stutter.
 */

#include <metal_stdlib>
using namespace metal;

// - Cheat Code Demo: Vector Add
kernel void vector_add(device const float *a [[buffer(0)]],
                       device const float *b [[buffer(1)]],
                       device float       *c [[buffer(2)]],
                       uint id [[thread_position_in_grid]])
{
    c[id] = a[id] + b[id];
}

// - Cheat Code Demo: SAXPY (Single-precision A*X + Y) 
// Classic GPU benchmark kernel. Using fast::fma for speed.
kernel void saxpy(device const float *x [[buffer(0)]],
                  device const float *y [[buffer(1)]],
                  device float       *z [[buffer(2)]],
                  constant float     &a [[buffer(3)]],
                  uint id [[thread_position_in_grid]])
{
    z[id] = fast::fma(a, x[id], y[id]);
}

// - Cheat Code Demo: Matrix Multiply Tile
// Tiled matrix multiply using threadgroup memory (shared memory)
// for data reuse - key GPU optimization technique.
constant int TILE_SIZE = 16;

kernel void matmul_tiled(device const float *A [[buffer(0)]],
                         device const float *B [[buffer(1)]],
                         device float       *C [[buffer(2)]],
                         constant uint      &N [[buffer(3)]],
                         uint2 gid  [[thread_position_in_grid]],
                         uint2 lid  [[thread_position_in_threadgroup]])
{
    threadgroup float As[TILE_SIZE][TILE_SIZE];
    threadgroup float Bs[TILE_SIZE][TILE_SIZE];

    float sum = 0.0f;
    uint row = gid.y;
    uint col = gid.x;

    for (uint t = 0; t < (N + TILE_SIZE - 1) / TILE_SIZE; ++t) {
        uint tCol = t * TILE_SIZE + lid.x;
        uint tRow = t * TILE_SIZE + lid.y;

        As[lid.y][lid.x] = (row < N && tCol < N) ? A[row * N + tCol] : 0.0f;
        Bs[lid.y][lid.x] = (tRow < N && col < N) ? B[tRow * N + col] : 0.0f;

        threadgroup_barrier(mem_flags::mem_threadgroup);

        for (uint k = 0; k < TILE_SIZE; ++k) {
            sum = fast::fma(As[lid.y][k], Bs[k][lid.x], sum);
        }

        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    if (row < N && col < N) {
        C[row * N + col] = sum;
    }
}

// - Cheat Code Demo: Parallel Reduce
// Reduction with threadgroup shared memory - efficient sum.
kernel void parallel_reduce(device const float     *input  [[buffer(0)]],
                            device float            *output [[buffer(1)]],
                            constant uint           &count  [[buffer(2)]],
                            threadgroup float       *sdata  [[threadgroup(0)]],
                            uint tid  [[thread_index_in_threadgroup]],
                            uint gid  [[thread_position_in_grid]],
                            uint blockDim [[threads_per_threadgroup]])
{
    sdata[tid] = (gid < count) ? input[gid] : 0.0f;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Tree reduction
    for (uint s = blockDim / 2; s > 0; s >>= 1) {
        if (tid < s) {
            sdata[tid] += sdata[tid + s];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    if (tid == 0) {
        output[gid / blockDim] = sdata[0];
    }
}
