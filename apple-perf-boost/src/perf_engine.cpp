/*
 * perf_engine.cpp - C++ Performance Orchestration Engine Implementation
 *
 * Copyright 2026 - Apache 2.0 License
 */

#include "perf_engine.hpp"
#include <cstdio>

namespace apple_perf {

/* ────────────────────────────────────────────────────────────────
 * Construction / destruction
 * ──────────────────────────────────────────────────────────────── */

PerfEngine::PerfEngine()
{
    if (!gpu_) {
        std::fprintf(stderr, "[PerfEngine] Metal device unavailable – "
                             "GPU boosts disabled.\n");
    }
}

PerfEngine::~PerfEngine() = default;

/* ────────────────────────────────────────────────────────────────
 * CPU boosts
 * ──────────────────────────────────────────────────────────────── */

void PerfEngine::apply_cpu_boosts()
{
    /* 1. Request Performance-core scheduling */
    cpu_boost_prefer_pcores();

    /* 2. Set QoS to USER_INTERACTIVE (highest non-realtime) */
    cpu_boost_set_qos(CPU_QOS_USER_INTERACTIVE);
}

/* ────────────────────────────────────────────────────────────────
 * GPU shader warm-up
 * ──────────────────────────────────────────────────────────────── */

void PerfEngine::warm_gpu_shaders(const std::vector<std::string> &sources,
                                  const std::vector<std::string> &fn_names)
{
    if (!gpu_) return;

    size_t count = std::min(sources.size(), fn_names.size());
    for (size_t i = 0; i < count; ++i) {
        gpu_boost_result_t r = gpu_boost_warm_shader(
            gpu_.get(), sources[i].c_str(), fn_names[i].c_str());
        if (r != GPU_BOOST_OK) {
            std::fprintf(stderr,
                         "[PerfEngine] Warning: shader warm failed for '%s' (err %d)\n",
                         fn_names[i].c_str(), r);
        }
    }
}

/* ────────────────────────────────────────────────────────────────
 * Benchmark
 * ──────────────────────────────────────────────────────────────── */

BenchmarkResult PerfEngine::benchmark(const std::string &name,
                                      std::function<void()> fn)
{
    /* Snapshot before */
    cpu_boost_snapshot_t before{};
    cpu_boost_snapshot(&before);

    uint64_t t0 = perf_timestamp_ns();

    fn();

    uint64_t t1 = perf_timestamp_ns();

    /* Snapshot after */
    cpu_boost_snapshot_t after{};
    cpu_boost_snapshot(&after);

    BenchmarkResult res;
    res.name          = name;
    res.elapsed_ms    = static_cast<double>(t1 - t0) / 1e6;
    res.cpu_user_ms   = (after.user_time_sec   - before.user_time_sec)   * 1000.0;
    res.cpu_sys_ms    = (after.system_time_sec  - before.system_time_sec) * 1000.0;
    res.thread_count  = after.thread_count;
    res.thermal_state = after.thermal_state;
    return res;
}

/* ────────────────────────────────────────────────────────────────
 * System snapshot
 * ──────────────────────────────────────────────────────────────── */

PerfEngine::SystemSnapshot PerfEngine::snapshot() const
{
    SystemSnapshot snap{};
    cpu_boost_snapshot(&snap.cpu);
    if (gpu_) {
        gpu_boost_device_info(
            const_cast<gpu_boost_ctx_t *>(gpu_.get()), &snap.gpu);
    }
    return snap;
}

} /* namespace apple_perf */
