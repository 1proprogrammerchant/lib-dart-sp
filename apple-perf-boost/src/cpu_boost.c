/*
 * cpu_boost.c - Apple CPU Performance Optimization Implementation
 *
 * Uses only public Apple APIs (Mach, pthread, sysctl).
 *
 * Copyright 2026 - Apache 2.0 License
 */

#include "cpu_boost.h"
#include "perf_utils.h"

#ifdef __APPLE__

#include <mach/mach.h>
#include <mach/thread_policy.h>
#include <mach/thread_act.h>
#include <mach/host_info.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <sys/sysctl.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <stdlib.h>
#include <string.h>

/* ────────────────────────────────────────────────────────────────
 * QoS / Priority
 * ──────────────────────────────────────────────────────────────── */

cpu_boost_result_t cpu_boost_set_qos(cpu_qos_level_t level)
{
    qos_class_t qos;
    switch (level) {
    case CPU_QOS_BACKGROUND:       qos = QOS_CLASS_BACKGROUND;       break;
    case CPU_QOS_UTILITY:          qos = QOS_CLASS_UTILITY;          break;
    case CPU_QOS_DEFAULT:          qos = QOS_CLASS_DEFAULT;          break;
    case CPU_QOS_USER_INITIATED:   qos = QOS_CLASS_USER_INITIATED;   break;
    case CPU_QOS_USER_INTERACTIVE: qos = QOS_CLASS_USER_INTERACTIVE; break;
    default: return CPU_BOOST_ERR_INVALID;
    }

    int rv = pthread_set_qos_class_self_np(qos, 0);
    return rv == 0 ? CPU_BOOST_OK : CPU_BOOST_ERR_SYSCALL;
}

/* ────────────────────────────────────────────────────────────────
 * Real-time scheduling via Mach thread policy
 * ──────────────────────────────────────────────────────────────── */

/* Convert nanoseconds to Mach absolute time units. */
static uint64_t ns_to_mach_abs(uint64_t ns)
{
    static mach_timebase_info_data_t info = {0, 0};
    if (info.denom == 0) {
        mach_timebase_info(&info);
    }
    /* abs = ns * denom / numer */
    return ns * info.denom / info.numer;
}

cpu_boost_result_t cpu_boost_set_realtime(uint32_t period_ns,
                                          uint32_t computation_ns,
                                          uint32_t constraint_ns)
{
    thread_time_constraint_policy_data_t policy;
    policy.period      = (uint32_t)ns_to_mach_abs(period_ns);
    policy.computation = (uint32_t)ns_to_mach_abs(computation_ns);
    policy.constraint  = (uint32_t)ns_to_mach_abs(constraint_ns);
    policy.preemptible = 1;

    kern_return_t kr = thread_policy_set(
        mach_thread_self(),
        THREAD_TIME_CONSTRAINT_POLICY,
        (thread_policy_t)&policy,
        THREAD_TIME_CONSTRAINT_POLICY_COUNT);

    return kr == KERN_SUCCESS ? CPU_BOOST_OK : CPU_BOOST_ERR_SYSCALL;
}

/* ────────────────────────────────────────────────────────────────
 * Memory / Cache helpers
 * ──────────────────────────────────────────────────────────────── */

void cpu_boost_prefetch(const void *addr, size_t nbytes)
{
    const char *p = (const char *)addr;
    const char *end = p + nbytes;
    for (; p < end; p += PERF_CACHE_LINE) {
        __builtin_prefetch(p, 0, 3);
    }
}

void *cpu_boost_aligned_alloc(size_t size)
{
    void *ptr = NULL;
    if (posix_memalign(&ptr, PERF_CACHE_LINE, size) != 0)
        return NULL;
    return ptr;
}

void cpu_boost_aligned_free(void *ptr)
{
    free(ptr);
}

cpu_boost_result_t cpu_boost_wire_memory(void *addr, size_t len)
{
    if (mlock(addr, len) != 0)
        return CPU_BOOST_ERR_SYSCALL;
    return CPU_BOOST_OK;
}

cpu_boost_result_t cpu_boost_unwire_memory(void *addr, size_t len)
{
    if (munlock(addr, len) != 0)
        return CPU_BOOST_ERR_SYSCALL;
    return CPU_BOOST_OK;
}

/* ────────────────────────────────────────────────────────────────
 * Thermal / CPU snapshot
 * ──────────────────────────────────────────────────────────────── */

cpu_boost_result_t cpu_boost_snapshot(cpu_boost_snapshot_t *out)
{
    if (!out) return CPU_BOOST_ERR_INVALID;
    memset(out, 0, sizeof(*out));

    /* ── task_info for CPU times & thread count ── */
    struct task_basic_info_64 tbi;
    mach_msg_type_number_t count = TASK_BASIC_INFO_64_COUNT;
    kern_return_t kr = task_info(mach_task_self(),
                                 TASK_BASIC_INFO_64,
                                 (task_info_t)&tbi,
                                 &count);
    if (kr != KERN_SUCCESS)
        return CPU_BOOST_ERR_SYSCALL;

    /* User + system time from the thread list */
    struct task_thread_times_info tti;
    mach_msg_type_number_t tc = TASK_THREAD_TIMES_INFO_COUNT;
    kr = task_info(mach_task_self(), TASK_THREAD_TIMES_INFO,
                   (task_info_t)&tti, &tc);
    if (kr != KERN_SUCCESS)
        return CPU_BOOST_ERR_SYSCALL;

    out->user_time_sec   = (double)tti.user_time.seconds
                         + (double)tti.user_time.microseconds / 1e6;
    out->system_time_sec = (double)tti.system_time.seconds
                         + (double)tti.system_time.microseconds / 1e6;

    /* Thread count via thread_act_array */
    thread_act_array_t threads;
    mach_msg_type_number_t thread_count;
    kr = task_threads(mach_task_self(), &threads, &thread_count);
    if (kr == KERN_SUCCESS) {
        out->thread_count = (int32_t)thread_count;
        /* Deallocate the array the kernel gave us */
        vm_deallocate(mach_task_self(),
                      (vm_address_t)threads,
                      thread_count * sizeof(thread_act_t));
    }

    /* Thermal state (macOS 12+, best-effort) */
    out->thermal_state = 0; /* nominal by default */
#if __has_include(<Foundation/NSProcessInfo.h>)
    /* NSProcessInfo.thermalState is Obj-C; skip here, use the ObjC layer */
#endif

    return CPU_BOOST_OK;
}

/* ────────────────────────────────────────────────────────────────
 * SIMD width
 * ──────────────────────────────────────────────────────────────── */

int cpu_boost_simd_width(void)
{
#if defined(__arm64__) || defined(__aarch64__)
    /* Apple Silicon NEON: 128-bit registers (16 bytes).
       AMX is wider but not directly SIMD-accessible from user code. */
    return 16;
#elif defined(__x86_64__)
    #if defined(__AVX512F__)
        return 64;
    #elif defined(__AVX2__) || defined(__AVX__)
        return 32;
    #else
        return 16; /* SSE */
    #endif
#else
    return 0;
#endif
}

/* ────────────────────────────────────────────────────────────────
 * P-core preference (Apple Silicon "latency hack")
 *
 * Setting QOS_CLASS_USER_INTERACTIVE strongly hints the scheduler
 * to place the thread on a Performance core.  We also request
 * THREAD_AFFINITY_POLICY with tag=1 (best effort, no guarantee).
 * ──────────────────────────────────────────────────────────────── */

cpu_boost_result_t cpu_boost_prefer_pcores(void)
{
#if defined(__arm64__) || defined(__aarch64__)
    /* 1) Set highest QoS */
    int rv = pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
    if (rv != 0)
        return CPU_BOOST_ERR_SYSCALL;

    /* 2) Affinity tag = 1  (advisory: group related threads) */
    thread_affinity_policy_data_t policy = { .affinity_tag = 1 };
    kern_return_t kr = thread_policy_set(
        mach_thread_self(),
        THREAD_AFFINITY_POLICY,
        (thread_policy_t)&policy,
        THREAD_AFFINITY_POLICY_COUNT);

    return kr == KERN_SUCCESS ? CPU_BOOST_OK : CPU_BOOST_ERR_SYSCALL;
#else
    return CPU_BOOST_ERR_PLATFORM; /* Intel Macs – no E/P core split */
#endif
}

#else /* !__APPLE__ */

/* ── Stubs for non-Apple platforms ─────────────────────────────── */

cpu_boost_result_t cpu_boost_set_qos(cpu_qos_level_t level)
    { (void)level; return CPU_BOOST_ERR_PLATFORM; }
cpu_boost_result_t cpu_boost_set_realtime(uint32_t p, uint32_t c, uint32_t co)
    { (void)p; (void)c; (void)co; return CPU_BOOST_ERR_PLATFORM; }
void cpu_boost_prefetch(const void *a, size_t n) { (void)a; (void)n; }
void *cpu_boost_aligned_alloc(size_t s) { (void)s; return NULL; }
void cpu_boost_aligned_free(void *p) { (void)p; }
cpu_boost_result_t cpu_boost_wire_memory(void *a, size_t l)
    { (void)a; (void)l; return CPU_BOOST_ERR_PLATFORM; }
cpu_boost_result_t cpu_boost_unwire_memory(void *a, size_t l)
    { (void)a; (void)l; return CPU_BOOST_ERR_PLATFORM; }
cpu_boost_result_t cpu_boost_snapshot(cpu_boost_snapshot_t *o)
    { (void)o; return CPU_BOOST_ERR_PLATFORM; }
int cpu_boost_simd_width(void) { return 0; }
cpu_boost_result_t cpu_boost_prefer_pcores(void)
    { return CPU_BOOST_ERR_PLATFORM; }

#endif /* __APPLE__ */
