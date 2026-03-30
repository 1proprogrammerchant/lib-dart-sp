/*
 * perf_utils.c - Utility implementations
 *
 * Copyright 2026 - Apache 2.0 License
 */

#include "perf_utils.h"

#ifdef __APPLE__
#include <mach/mach_time.h>

static mach_timebase_info_data_t _perf_timebase = {0, 0};

static void _perf_init_timebase(void)
{
    if (_perf_timebase.denom == 0)
        mach_timebase_info(&_perf_timebase);
}

uint64_t perf_timestamp_ns(void)
{
    _perf_init_timebase();
    uint64_t t = mach_absolute_time();
    return t * _perf_timebase.numer / _perf_timebase.denom;
}

void perf_spin_wait_ns(uint64_t ns)
{
    uint64_t start = perf_timestamp_ns();
    while ((perf_timestamp_ns() - start) < ns) {
        PERF_YIELD();
    }
}

#else
#include <time.h>

uint64_t perf_timestamp_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

void perf_spin_wait_ns(uint64_t ns)
{
    uint64_t start = perf_timestamp_ns();
    while ((perf_timestamp_ns() - start) < ns) {
        PERF_YIELD();
    }
}

#endif
