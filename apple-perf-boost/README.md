# Apple PerfBoost

> The cheat speed optimization toolkit for Apple CPU (Apple Silicon / Intel) and GPU (Metal) using legitimate public APIs.

Incorporates patterns from [apple/swift-system-metrics](https://github.com/apple/swift-system-metrics) for process-level metrics collection.

## Project Structure

```
apple-perf-boost/
├── include/                      # Public C headers
│   ├── cpu_boost.h               # CPU optimizations API
│   ├── gpu_boost.h               # GPU (Metal) optimizations API
│   └── perf_utils.h              # Timing & compiler hint utilities
├── src/                          # Implementations
│   ├── cpu_boost.c               # C - Mach thread policy, QoS, prefetch, mlock
│   ├── perf_utils.c              # C - High-res Mach timing
│   ├── gpu_boost.mm              # Objective-C++ - Metal shader caching, buffer mgmt
│   ├── perf_engine.hpp           # C++ - RAII orchestration engine header
│   └── perf_engine.cpp           # C++ - Benchmark harness, snapshot coordination
├── swift/                        # Swift layer
│   ├── PerfBoost.swift           # Swift wrappers for CPU & GPU boost
│   ├── MetricsIntegration.swift  # Metrics collector (swift-system-metrics style)
│   └── main.swift                # CLI demo entry point
├── shaders/
│   └── example_shader.metal      # Sample Metal compute shaders
├── tests/
│   └── test_driver.c             # C smoke test
├── vendor/swift-system-metrics/  # Reference files from apple/swift-system-metrics
│   ├── SystemMetricsMonitor.swift
│   ├── SystemMetricsMonitor+Darwin.swift
│   └── SystemMetricsMonitorConfiguration.swift
├── CMakeLists.txt                # Build system for C/C++/ObjC
├── Package.swift                 # Swift Package Manager manifest
└── README.md
```

## Speed Hacks / Cheat Codes (All Non-Malicious)

| #  | Technique | Layer | What it does |
|----|-----------|-------|------|
| 1  | P-core preference | CPU | Schedules thread on Performance cores via `QOS_CLASS_USER_INTERACTIVE` + thread affinity |
| 2  | QoS elevation | CPU | Sets highest non-realtime priority for the calling thread |
| 3  | Shader pre-compilation | GPU | Warms `MTLComputePipelineState` at startup — eliminates first-frame stutter |
| 4  | Fast-math Metal compile | GPU | `MTLCompileOptions.fastMathEnabled` trades IEEE precision for speed |
| 5  | Private GPU buffers | GPU | `MTLStorageModePrivate` avoids unified-memory coherency overhead |
| 6  | Priority command buffers | GPU | `MTLCommandBufferDescriptor` with enhanced options |
| 7  | Unretained CB references | GPU | `retainedReferences = NO` reduces command buffer overhead |
| 8  | Occupancy threadgroups | GPU | Queries `maxTotalThreadsPerThreadgroup` to saturate execution units |
| 9  | Cache-line alignment | CPU | 128-byte alignment for Apple Silicon (vs 64 for Intel) |
| 10 | Memory wiring (mlock) | CPU | Keeps hot-path memory resident — no page faults |
| 11 | Software prefetch | CPU | `__builtin_prefetch` pre-loads data into L1/L2 |
| 12 | Real-time scheduling | CPU | Mach `THREAD_TIME_CONSTRAINT_POLICY` for deterministic timing |
| 13 | Tiled matrix multiply | GPU | Threadgroup shared memory for data reuse |
| 14 | Tree reduction | GPU | Efficient parallel sum using shared memory |

## Building

### C/C++/Objective-C (CMake)

```bash
cd apple-perf-boost
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/perf_boost_test
```

### Swift (SPM)

```bash
cd apple-perf-boost
swift build -c release
swift run perf-boost
```

## swift-system-metrics Integration

This project references [apple/swift-system-metrics](https://github.com/apple/swift-system-metrics) in two ways:

1. **Vendored reference files** in `vendor/swift-system-metrics/` - annotated copies showing the Darwin metrics collection patterns we adopt
2. **SPM dependency** in `Package.swift` - pulls the real `SystemMetrics` library so you can use `SystemMetricsMonitor` alongside our `PerfBoostMetricsCollector`

The `MetricsIntegration.swift` file mirrors the swift-system-metrics label/gauge pattern but adds GPU and optimization-specific metrics.

## Requirements

- macOS 13+ (Ventura)
- Xcode 15+ or Swift 5.9+ toolchain
- Apple Silicon recommended (Intel Macs supported with reduced feature set)

## License

Apache 2.0. Vendored swift-system-metrics files retain their original Apple Inc. copyright.
