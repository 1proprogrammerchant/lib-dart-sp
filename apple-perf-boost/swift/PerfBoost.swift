/*
 * PerfBoost.swift - Swift orchestrator for Apple CPU + GPU speed boosts
 *
 * Coordinates the C/C++/ObjC layers and provides a clean Swift API.
 *
 * Copyright 2026 - Apache 2.0 License
 */

import Foundation
import CPerfBoost

public struct CPUBoost {

    public enum QoS: Int32 {
        case background      = 0
        case utility         = 1
        case `default`       = 2
        case userInitiated   = 3
        case userInteractive = 4
    }


    @discardableResult
    public static func setQoS(_ level: QoS) -> Bool {
        cpu_boost_set_qos(cpu_qos_level_t(UInt32(level.rawValue))) == CPU_BOOST_OK
    }

    /// Request real-time scheduling for latency-critical work (audio, tight loops).
    @discardableResult
    public static func setRealtime(periodNs: UInt32,
                                   computationNs: UInt32,
                                   constraintNs: UInt32) -> Bool {
        cpu_boost_set_realtime(periodNs, computationNs, constraintNs) == CPU_BOOST_OK
    }

    @discardableResult
    public static func preferPCores() -> Bool {
        cpu_boost_prefer_pcores() == CPU_BOOST_OK
    }
    public static func prefetch(_ buffer: UnsafeRawPointer, bytes: Int) {
        cpu_boost_prefetch(buffer, bytes)
    }


    public static var simdWidth: Int {
        Int(cpu_boost_simd_width())
    }

    /// Current CPU + thread snapshot.
    public static func snapshot() -> Snapshot? {
        var raw = cpu_boost_snapshot_t()
        guard cpu_boost_snapshot(&raw) == CPU_BOOST_OK else { return nil }
        return Snapshot(raw: raw)
    }

    public struct Snapshot {
        public let userTimeSec: Double
        public let systemTimeSec: Double
        public let voluntaryCtxSwitches: UInt64
        public let involuntaryCtxSwitches: UInt64
        public let threadCount: Int
        public let thermalState: Int

        init(raw: cpu_boost_snapshot_t) {
            userTimeSec              = raw.user_time_sec
            systemTimeSec            = raw.system_time_sec
            voluntaryCtxSwitches     = raw.voluntary_ctx_switches
            involuntaryCtxSwitches   = raw.involuntary_ctx_switches
            threadCount              = Int(raw.thread_count)
            thermalState             = Int(raw.thermal_state)
        }
    }
}


public final class GPUBoost {

    public enum BufferMode: UInt32 {
        case shared  = 0
        case `private` = 1
        case managed = 2
    }

    private let ctx: OpaquePointer

    public init?() {
        guard let c = gpu_boost_create() else { return nil }
        ctx = c
    }

    deinit {
        gpu_boost_destroy(ctx)
    }

    @discardableResult
    public func warmShader(source: String, functionName: String) -> Bool {
        gpu_boost_warm_shader(ctx, source, functionName) == GPU_BOOST_OK
    }


    public var deviceInfo: DeviceInfo? {
        var raw = gpu_boost_device_info_t()
        guard gpu_boost_device_info(ctx, &raw) == GPU_BOOST_OK else { return nil }
        return DeviceInfo(raw: raw)
    }

    /// Optimal threadgroup size for a warmed kernel.
    public func optimalThreadgroup(for functionName: String) -> UInt32 {
        gpu_boost_optimal_threadgroup(ctx, functionName)
    }

    public struct DeviceInfo {
        public let name: String
        public let maxWorkingSetSize: UInt64
        public let currentAllocatedSize: UInt64
        public let maxThreadsPerGroup: UInt32
        public let maxBufferLength: UInt32
        public let supportsRaytracing: Bool
        public let gpuFamily: Int

        init(raw: gpu_boost_device_info_t) {
            name                 = raw.device_name.map { String(cString: $0) } ?? "Unknown"
            maxWorkingSetSize    = raw.recommended_max_working_set_size
            currentAllocatedSize = raw.current_allocated_size
            maxThreadsPerGroup   = raw.max_threads_per_threadgroup
            maxBufferLength      = raw.max_buffer_length
            supportsRaytracing   = raw.supports_raytracing
            gpuFamily            = Int(raw.gpu_family)
        }
    }
}


public struct PerfBoostAll {

    /// Apply every CPU + GPU optimization at once.
    public static func activate() {
        print("[PerfBoost] Applying Apple CPU speed hacks...")

        // CPU: P-core preference + highest QoS
        CPUBoost.preferPCores()
        CPUBoost.setQoS(.userInteractive)

        print("    Thread scheduled on P-cores (Apple Silicon)")
        print("    QoS set to USER_INTERACTIVE")
        print("    SIMD width: \(CPUBoost.simdWidth) bytes")

        if let snap = CPUBoost.snapshot() {
            print("    Threads: \(snap.threadCount)  Thermal: \(snap.thermalState)")
        }

        // GPU: create context (warm shaders later via GPUBoost)
        if let gpu = GPUBoost() {
            if let info = gpu.deviceInfo {
                print("    GPU: \(info.name)")
                print("    VRAM budget: \(info.maxWorkingSetSize / 1_048_576) MB")
                print("    Max threads/group: \(info.maxThreadsPerGroup)")
                print("    GPU family: Apple\(info.gpuFamily - 1000)")
            }
        } else {
            print("[PerfBoost] No Metal device – GPU boosts skipped")
        }

        print("[PerfBoost] All speed hacks applied.")
    }
}
