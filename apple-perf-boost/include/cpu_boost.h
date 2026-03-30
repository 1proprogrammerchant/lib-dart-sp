/*
 * cpu_boost.h - Apple CPU Performance Optimization (Non-Malicious)
 *
 * Legitimate performance tuning via public Apple APIs:
 *   - Thread QoS elevation
 *   - Memory prefetch hints
 *   - Cache-line alignment helpers
 *   - SIMD dispatch hints
 *   - Mach thread policy tuning
 *
 * Copyright 2026 - Apache 2.0 License
 */

#ifndef CPU_BOOST_H
#define CPU_BOOST_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>

/* - Result codes */
typedef enum {
    CPU_BOOST_OK            =  0,
    CPU_BOOST_ERR_PERM      = -1,
    CPU_BOOST_ERR_SYSCALL   = -2,
    CPU_BOOST_ERR_INVALID   = -3,
    CPU_BOOST_ERR_PLATFORM  = -4,
} cpu_boost_result_t;

/* - QoS / Priority */
typedef enum {
    CPU_QOS_BACKGROUND      = 0,
    CPU_QOS_UTILITY         = 1,
    CPU_QOS_DEFAULT         = 2,
    CPU_QOS_USER_INITIATED  = 3,
    CPU_QOS_USER_INTERACTIVE = 4, /* P-core affinity on Apple Silicon */
} cpu_qos_level_t;

/**
 * Elevate the calling thread's QoS class.
 * On Apple Silicon this nudges the scheduler toward Performance cores.
 */
cpu_boost_result_t cpu_boost_set_qos(cpu_qos_level_t level);

/**
 * Request real-time scheduling for the calling thread (audio / tight loops).
 * period_ns / computation_ns / constraint_ns expressed in nanoseconds.
 */
cpu_boost_result_t cpu_boost_set_realtime(uint32_t period_ns,
                                          uint32_t computation_ns,
                                          uint32_t constraint_ns);

/* - Memory / Cache */

/**
 * Software-prefetch `nbytes` starting at `addr` into L1/L2.
 * Uses __builtin_prefetch with temporal locality hint.
 */
void cpu_boost_prefetch(const void *addr, size_t nbytes);

void *cpu_boost_aligned_alloc(size_t size);

/** Free a pointer returned by cpu_boost_aligned_alloc(). */
void cpu_boost_aligned_free(void *ptr);

cpu_boost_result_t cpu_boost_wire_memory(void *addr, size_t len);

/** Unwire a previously wired region. */
cpu_boost_result_t cpu_boost_unwire_memory(void *addr, size_t len);


typedef struct {
    double user_time_sec;
    double system_time_sec;
    uint64_t voluntary_ctx_switches;
    uint64_t involuntary_ctx_switches;
    int32_t  thread_count;
    int32_t  thermal_state;   /* 0 = nominal … 3 = critical */
} cpu_boost_snapshot_t;

/**
 * Collect a point-in-time CPU snapshot (Mach task_info + host_info).
 */
cpu_boost_result_t cpu_boost_snapshot(cpu_boost_snapshot_t *out);

/* - SIMD width hint - */

/**
 * Returns the widest NEON / AMX SIMD register width available (in bytes).
 * Useful for choosing batch sizes that saturate the vector unit.
 */
int cpu_boost_simd_width(void);

/* - Disable efficiency cores (latency hack) - */

/**
 * Ask the OS to avoid scheduling this thread on E-cores (best-effort).
 * Only meaningful on Apple Silicon; no-op on Intel Macs.
 */
cpu_boost_result_t cpu_boost_prefer_pcores(void);

#ifdef __cplusplus
}
#endif

#endif /* CPU_BOOST_H */
