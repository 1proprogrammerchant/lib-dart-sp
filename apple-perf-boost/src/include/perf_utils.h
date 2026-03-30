/*
 * perf_utils.h - Cross-cutting performance utilities
 *
 * Copyright 2026 - Apache 2.0 License
 */

#ifndef PERF_UTILS_H
#define PERF_UTILS_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

/* - High-resolution timing - */

/** Return monotonic nanosecond timestamp (Mach absolute time converted). */
uint64_t perf_timestamp_ns(void);

/** Return elapsed nanoseconds between two timestamps. */
static inline uint64_t perf_elapsed_ns(uint64_t start, uint64_t end) {
    return end - start;
}

/* - Spin-wait with back-off (avoid syscall overhead) - */

/**
 * Busy-wait for approximately `ns` nanoseconds using pause / yield hints.
 * Useful for ultra-short waits where usleep() is too coarse.
 */
void perf_spin_wait_ns(uint64_t ns);

/* - Compiler / CPU hints - */

#if defined(__arm64__) || defined(__aarch64__)
  #define PERF_YIELD()      __asm__ volatile("yield")
  #define PERF_DMB()        __asm__ volatile("dmb ish" ::: "memory")
  #define PERF_ISB()        __asm__ volatile("isb")
  #define PERF_PREFETCH(p)  __builtin_prefetch((p), 0, 3)
#elif defined(__x86_64__)
  #define PERF_YIELD()      __asm__ volatile("pause")
  #define PERF_DMB()        __asm__ volatile("mfence" ::: "memory")
  #define PERF_ISB()        ((void)0)
  #define PERF_PREFETCH(p)  __builtin_prefetch((p), 0, 3)
#else
  #define PERF_YIELD()      ((void)0)
  #define PERF_DMB()        __sync_synchronize()
  #define PERF_ISB()        ((void)0)
  #define PERF_PREFETCH(p)  ((void)(p))
#endif

#define PERF_LIKELY(x)   __builtin_expect(!!(x), 1)
#define PERF_UNLIKELY(x) __builtin_expect(!!(x), 0)

/* - Cache-line constant for Apple Silicon - */
#if defined(__arm64__) || defined(__aarch64__)
  #define PERF_CACHE_LINE  128   /* Apple Silicon uses 128-byte lines */
#else
  #define PERF_CACHE_LINE   64
#endif

#define PERF_ALIGN_CACHE __attribute__((aligned(PERF_CACHE_LINE)))

#ifdef __cplusplus
}
#endif

#endif /* PERF_UTILS_H */
