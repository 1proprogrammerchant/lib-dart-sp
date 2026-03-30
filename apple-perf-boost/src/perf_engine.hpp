/*
 * perf_engine.hpp - C++ Performance Orchestration Engine
 *
 * Coordinates CPU + GPU boosts, provides RAII helpers and a
 * benchmark harness.
 *
 * Copyright 2026 - Apache 2.0 License
 */

#ifndef PERF_ENGINE_HPP
#define PERF_ENGINE_HPP

#include <cstdint>
#include <string>
#include <vector>
#include <functional>
#include <chrono>
#include <memory>

/* C API headers */
extern "C" {
#include "cpu_boost.h"
#include "gpu_boost.h"
#include "perf_utils.h"
}

namespace apple_perf {

struct BenchmarkResult {
    std::string name;
    double      elapsed_ms;
    double      cpu_user_ms;
    double      cpu_sys_ms;
    int32_t     thread_count;
    int32_t     thermal_state;
};

class ScopedQoS {
public:
    explicit ScopedQoS(cpu_qos_level_t level) : previous_(CPU_QOS_DEFAULT) {
        cpu_boost_set_qos(level);
    }
    ~ScopedQoS() { cpu_boost_set_qos(previous_); }

    ScopedQoS(const ScopedQoS &)            = delete;
    ScopedQoS &operator=(const ScopedQoS &) = delete;
private:
    cpu_qos_level_t previous_;
};

/* - RAII wrapper: wired memory region - */
class WiredRegion {
public:
    WiredRegion(void *addr, size_t len) : addr_(addr), len_(len) {
        cpu_boost_wire_memory(addr_, len_);
    }
    ~WiredRegion() { cpu_boost_unwire_memory(addr_, len_); }

    WiredRegion(const WiredRegion &)            = delete;
    WiredRegion &operator=(const WiredRegion &) = delete;
private:
    void  *addr_;
    size_t len_;
};

/* - Cache-aligned buffer (unique_ptr with custom deleter) - */
using AlignedBuffer = std::unique_ptr<void, decltype(&cpu_boost_aligned_free)>;

inline AlignedBuffer make_aligned_buffer(size_t size) {
    return AlignedBuffer(cpu_boost_aligned_alloc(size), cpu_boost_aligned_free);
}

class GPUContext {
public:
    GPUContext() : ctx_(gpu_boost_create()) {}
    ~GPUContext() { if (ctx_) gpu_boost_destroy(ctx_); }

    gpu_boost_ctx_t       *get()       { return ctx_; }
    const gpu_boost_ctx_t *get() const { return ctx_; }
    explicit operator bool() const     { return ctx_ != nullptr; }

    GPUContext(const GPUContext &)            = delete;
    GPUContext &operator=(const GPUContext &) = delete;
private:
    gpu_boost_ctx_t *ctx_;
};

class PerfEngine {
public:
    PerfEngine();
    ~PerfEngine();

    /** Apply all CPU speed boosts (QoS + P-core pref + prefetch config). */
    void apply_cpu_boosts();

    /** Warm a set of Metal shaders so first dispatch is fast. */
    void warm_gpu_shaders(const std::vector<std::string> &sources,
                          const std::vector<std::string> &fn_names);

    /** Run `fn` under maximum performance settings and return a benchmark. */
    BenchmarkResult benchmark(const std::string &name,
                              std::function<void()> fn);

    /** Collect a snapshot combining CPU + GPU status. */
    struct SystemSnapshot {
        cpu_boost_snapshot_t   cpu;
        gpu_boost_device_info_t gpu;
    };
    SystemSnapshot snapshot() const;

private:
    GPUContext gpu_;
};

} /* namespace apple_perf */

#endif /* PERF_ENGINE_HPP */
