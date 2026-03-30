/*
 * MetricsIntegration.swift - Integration with apple/swift-system-metrics
 *
 * Bridges our PerfBoost data into the Swift Metrics ecosystem using
 * the same patterns as swift-system-metrics (SystemMetricsMonitor).
 *
 * Reference: https://github.com/apple/swift-system-metrics
 *
 * Copyright 2026 - Apache 2.0 License
 */

import Foundation
import CPerfBoost

// MARK: - PerfBoost Metrics Data

/// Mirrors the swift-system-metrics `SystemMetricsMonitor.Data` struct,
/// extended with GPU and optimization-specific metrics.
public struct PerfBoostMetricsData: Sendable {
    public var virtualMemoryBytes: Int
    public var residentMemoryBytes: Int
    public var startTimeSeconds: Int
    public var cpuSeconds: Double
    public var maxFileDescriptors: Int
    public var openFileDescriptors: Int
    public var threadCount: Int

    // - PerfBoost-specific metrics -
    public var cpuUserSeconds: Double
    public var cpuSystemSeconds: Double
    public var thermalState: Int          // 0=nominal, 1=fair, 2=serious, 3=critical
    public var simdWidth: Int             // NEON/SSE/AVX width in bytes
    public var gpuAllocatedBytes: UInt64  // Current Metal allocation
    public var gpuMaxWorkingSet: UInt64   // Recommended max VRAM budget
    public var gpuFamily: Int             // MTLGPUFamily raw value
    public var pCoreActive: Bool          // Whether P-core scheduling was requested
}

// MARK: - Labels (mirrors SystemMetricsMonitor.Configuration.Labels)
public struct PerfBoostMetricsLabels: Sendable {
    public var prefix: String = "perfboost_"

    public var virtualMemoryBytes: String  = "virtual_memory_bytes"
    public var residentMemoryBytes: String = "resident_memory_bytes"
    public var startTimeSeconds: String    = "start_time_seconds"
    public var cpuSecondsTotal: String     = "cpu_seconds_total"
    public var maxFileDescriptors: String  = "max_fds"
    public var openFileDescriptors: String = "open_fds"
    public var threadCount: String         = "thread_count"
    public var thermalState: String        = "thermal_state"
    public var simdWidth: String           = "simd_width_bytes"
    public var gpuAllocated: String        = "gpu_allocated_bytes"
    public var gpuMaxWorking: String       = "gpu_max_working_set_bytes"
    public var gpuFamily: String           = "gpu_family"
    public var pCoreActive: String         = "pcore_active"

    public func label(for key: String) -> String {
        prefix + key
    }

    public init() {}
}

// MARK: - Collector
public final class PerfBoostMetricsCollector: @unchecked Sendable {
    public let labels: PerfBoostMetricsLabels
    private let gpu: GPUBoost?

    public init(labels: PerfBoostMetricsLabels = .init()) {
        self.labels = labels
        self.gpu = GPUBoost()
    }

    public func collect() -> PerfBoostMetricsData {
        let cpuSnap = CPUBoost.snapshot()

        var data = PerfBoostMetricsData(
            virtualMemoryBytes:  0,
            residentMemoryBytes: 0,
            startTimeSeconds:    0,
            cpuSeconds:          (cpuSnap?.userTimeSec ?? 0) + (cpuSnap?.systemTimeSec ?? 0),
            maxFileDescriptors:  0,
            openFileDescriptors: 0,
            threadCount:         cpuSnap?.threadCount ?? 0,
            cpuUserSeconds:      cpuSnap?.userTimeSec ?? 0,
            cpuSystemSeconds:    cpuSnap?.systemTimeSec ?? 0,
            thermalState:        cpuSnap?.thermalState ?? 0,
            simdWidth:           CPUBoost.simdWidth,
            gpuAllocatedBytes:   0,
            gpuMaxWorkingSet:    0,
            gpuFamily:           0,
            pCoreActive:         false
        )

        #if os(macOS)
        fillDarwinProcessInfo(&data)
        #endif

        if let info = gpu?.deviceInfo {
            data.gpuAllocatedBytes = info.currentAllocatedSize
            data.gpuMaxWorkingSet  = info.maxWorkingSetSize
            data.gpuFamily         = info.gpuFamily
        }

        return data
    }

    public func printReport() {
        let d = collect()
        print("╔══════════════════════════════════════════════════╗")
        print("║         PerfBoost Metrics Report                ║")
        print("╠══════════════════════════════════════════════════╣")
        print("║ CPU                                             ║")
        print("║   User time:      \(String(format: "%10.3f", d.cpuUserSeconds)) sec          ║")
        print("║   System time:    \(String(format: "%10.3f", d.cpuSystemSeconds)) sec          ║")
        print("║   Threads:        \(String(format: "%10d", d.threadCount))               ║")
        print("║   Thermal state:  \(String(format: "%10d", d.thermalState))               ║")
        print("║   SIMD width:     \(String(format: "%10d", d.simdWidth)) bytes        ║")
        print("╠══════════════════════════════════════════════════╣")
        print("║ Memory                                          ║")
        print("║   Virtual:        \(formatBytes(d.virtualMemoryBytes))     ║")
        print("║   Resident:       \(formatBytes(d.residentMemoryBytes))     ║")
        print("╠══════════════════════════════════════════════════╣")
        print("║ GPU                                             ║")
        print("║   Allocated:      \(formatBytes(Int(d.gpuAllocatedBytes)))     ║")
        print("║   VRAM budget:    \(formatBytes(Int(d.gpuMaxWorkingSet)))     ║")
        print("║   Family:         Apple\(d.gpuFamily > 1000 ? d.gpuFamily - 1000 : d.gpuFamily)                    ║")
        print("╚══════════════════════════════════════════════════╝")
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%8.1f GB", Double(bytes) / 1_073_741_824.0)
        } else if bytes >= 1_048_576 {
            return String(format: "%8.1f MB", Double(bytes) / 1_048_576.0)
        } else if bytes >= 1024 {
            return String(format: "%8.1f KB", Double(bytes) / 1024.0)
        }
        return String(format: "%8d  B", bytes)
    }

    #if os(macOS)
    private nonisolated func fillDarwinProcessInfo(_ data: inout PerfBoostMetricsData) {
        // Use proc_pidinfo to get memory stats, matching the swift-system-metrics approach
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        nonisolated(unsafe) let selfPort = mach_task_self_
        let kr = withUnsafeMutablePointer(to: &taskInfo) { ptr in
            ptr.withMemoryRebound(to: Int32.self, capacity: Int(count)) { intPtr in
                task_info(selfPort, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }
        if kr == KERN_SUCCESS {
            data.virtualMemoryBytes  = Int(taskInfo.virtual_size)
            data.residentMemoryBytes = Int(taskInfo.resident_size)
        }

        var rlim = rlimit()
        if getrlimit(RLIMIT_NOFILE, &rlim) == 0 {
            data.maxFileDescriptors = Int(rlim.rlim_cur)
        }
    }
    #endif
}
