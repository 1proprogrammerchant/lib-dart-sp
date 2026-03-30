/*
 * test_driver.c - Quick smoke test for the C layer
 *
 * Build: cmake --build build && ./build/perf_boost_test
 */

#include <stdio.h>
#include "cpu_boost.h"
#include "gpu_boost.h"
#include "perf_utils.h"

static const char *result_str(int r) {
    switch (r) {
    case  0: return "OK";
    case -1: return "ERR_PERM";
    case -2: return "ERR_SYSCALL";
    case -3: return "ERR_INVALID";
    case -4: return "ERR_PLATFORM";
    default: return "UNKNOWN";
    }
}

int main(void)
{
    printf("=== Apple PerfBoost C Test Driver ===\n\n");

    /* - Timing */
    uint64_t t0 = perf_timestamp_ns();
    perf_spin_wait_ns(1000000); /* ~1 ms */
    uint64_t t1 = perf_timestamp_ns();
    printf("[timing] spin_wait(1ms) actual: %.3f ms\n",
           (double)(t1 - t0) / 1e6);

    /* - SIMD  */
    printf("[simd]   width = %d bytes\n", cpu_boost_simd_width());


    int r = cpu_boost_set_qos(CPU_QOS_USER_INTERACTIVE);
    printf("[qos]    set USER_INTERACTIVE: %s\n", result_str(r));


    r = cpu_boost_prefer_pcores();
    printf("[pcore]  prefer P-cores: %s\n", result_str(r));


    cpu_boost_snapshot_t snap;
    r = cpu_boost_snapshot(&snap);
    printf("[snap]   result: %s\n", result_str(r));
    if (r == 0) {
        printf("         user_time   = %.3f s\n", snap.user_time_sec);
        printf("         system_time = %.3f s\n", snap.system_time_sec);
        printf("         threads     = %d\n", snap.thread_count);
        printf("         thermal     = %d\n", snap.thermal_state);
    }
    
    void *buf = cpu_boost_aligned_alloc(4096);
    printf("[alloc]  aligned_alloc(4096): %s (addr=%p)\n",
           buf ? "OK" : "FAIL", buf);
    if (buf) {
        /* Prefetch test */
        cpu_boost_prefetch(buf, 4096);
        printf("[prefet  prefetch 4096 bytes: OK\n");

        /* Wire test */
        r = cpu_boost_wire_memory(buf, 4096);
        printf("[wire]   mlock: %s\n", result_str(r));
        if (r == 0) {
            cpu_boost_unwire_memory(buf, 4096);
        }
        cpu_boost_aligned_free(buf);
    }
    
    printf("\n--- GPU ---\n");
    gpu_boost_ctx_t *gpu = gpu_boost_create();
    if (gpu) {
        gpu_boost_device_info_t info;
        if (gpu_boost_device_info(gpu, &info) == GPU_BOOST_OK) {
            printf("[gpu]    device: %s\n", info.device_name);
            printf("         max_working_set: %llu MB\n",
                   info.recommended_max_working_set_size / (1024*1024));
            printf("         max_threads/tg:  %u\n",
                   info.max_threads_per_threadgroup);
            printf("         gpu_family:      %d\n", info.gpu_family);
        }
        gpu_boost_destroy(gpu);
    } else {
        printf("[gpu]    No Metal device available\n");
    }

    printf("\n=== All tests complete ===\n");
    return 0;
}
