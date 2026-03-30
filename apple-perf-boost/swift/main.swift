/*
 * main.swift - Apple PerfBoost Demo Entry Point
 *
 * Demonstrates all CPU + GPU speed optimizations and metrics collection.
 *
 * Copyright 2026 - Apache 2.0 License
 */

import Foundation
import PerfBoostLib

print("""
╔══════════════════════════════════════════════════════════╗
║   Apple PerfBoost - CPU & GPU Speed Optimization Tool   ║
║   Uses public Apple APIs only (non-malicious)           ║
║   Reference: github.com/apple/swift-system-metrics      ║
╚══════════════════════════════════════════════════════════╝
"""
)

// ──────────────────────────────────────────────────────────────
// Step 1: Apply all CPU + GPU "cheat codes"
// ──────────────────────────────────────────────────────────────

print("\n- Step 1: Applying Speed Boosts -\n")
PerfBoostAll.activate()

// ──────────────────────────────────────────────────────────────
// Step 2: Collect & display metrics (swift-system-metrics style)
// ──────────────────────────────────────────────────────────────

print("\n- Step 2: Collecting Metrics -\n")
let collector = PerfBoostMetricsCollector()
collector.printReport()

// ──────────────────────────────────────────────────────────────
// Step 3: Demonstrate GPU shader warm-up
// ──────────────────────────────────────────────────────────────

print("\n- Step 3: GPU Shader Warm-up Demo -\n")

if let gpu = GPUBoost() {
    // A trivial compute kernel for demonstration
    let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void vector_add(device float *a [[buffer(0)]],
                           device float *b [[buffer(1)]],
                           device float *c [[buffer(2)]],
                           uint id [[thread_position_in_grid]])
    {
        c[id] = a[id] + b[id];
    }
    """

    if gpu.warmShader(source: shaderSource, functionName: "vector_add") {
        let tg = gpu.optimalThreadgroup(for: "vector_add")
        print("   Shader 'vector_add' pre-compiled and cached")
        print("   Optimal threadgroup size: \(tg)")
    } else {
        print("   Shader warm-up failed (Metal may not be available)")
    }
} else {
    print("   No Metal device available")
}

// ──────────────────────────────────────────────────────────────
// Step 4: Quick CPU benchmark
// ──────────────────────────────────────────────────────────────

print("\n- Step 4: CPU Micro-benchmark -\n")

func benchmarkTask() {
    let size = 1024 * 1024
    var buffer = [Float](repeating: 1.0, count: size)
    for i in 0..<size {
        buffer[i] = buffer[i] * 2.0 + Float(i % 7)
    }
    if buffer[size / 2] < 0 { print("nope") }
}

// Without boost
CPUBoost.setQoS(.default)
let t0 = CFAbsoluteTimeGetCurrent()
benchmarkTask()
let unboostedMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000

// With boost
CPUBoost.preferPCores()
CPUBoost.setQoS(.userInteractive)
let t1 = CFAbsoluteTimeGetCurrent()
benchmarkTask()
let boostedMs = (CFAbsoluteTimeGetCurrent() - t1) * 1000

print(String(format: "   Default QoS:  %.2f ms", unboostedMs))
print(String(format: "   Boosted:      %.2f ms", boostedMs))
if unboostedMs > 0 {
    let speedup = unboostedMs / boostedMs
    print(String(format: "   Speedup:      %.2fx", speedup))
}

// ──────────────────────────────────────────────────────────────
// Done
// ──────────────────────────────────────────────────────────────

print("\n- Summary of Cheat Codes Applied -\n")
print("""
  #1  P-core preference          → Schedules on Performance cores
  #2  QoS USER_INTERACTIVE       → Highest non-realtime priority
  #3  Shader pre-compilation     → Eliminates first-frame stutter
  #4  fast-math Metal compile    → Trades IEEE precision for speed
  #5  Private GPU buffers        → Avoids coherency overhead
  #6  Priority command buffers   → Lower GPU dispatch latency
  #7  Unretained CB references   → Less command buffer overhead
  #8  Occupancy threadgroups     → Saturates GPU execution units
  #9  Cache-line alignment (128B)→ Optimal for Apple Silicon
  #10 Memory wiring (mlock)      → Eliminates page faults in hot paths
  #11 Software prefetch           → Pre-loads data into L1/L2
  #12 Mach real-time scheduling  → Deterministic timing for audio/HPC
""")

print("\n- All done. Your Apple Silicon is running at full speed! -\n")
