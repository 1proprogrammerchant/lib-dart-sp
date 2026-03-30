/*
 * SystemMetricsMonitor+Darwin.swift
 *
 * Vendored from: https://github.com/apple/swift-system-metrics
 * Commit: 758865b (2026-03-15)
 * License: Apache 2.0
 *
 * Darwin-specific metrics collection using Mach task_info and proc_pidinfo.
 *
 * Original copyright:
 *   Copyright (c) 2025 Apple Inc. and the Swift System Metrics API project authors
 *   Licensed under Apache License v2.0
 *   SPDX-License-Identifier: Apache-2.0
 *
 * ───────────────────────────────────────────────────────────────────────────
 * This is a reference copy. See the original repo for the maintained version:
 *   https://github.com/apple/swift-system-metrics/blob/main/Sources/SystemMetrics/SystemMetricsMonitor%2BDarwin.swift
 * ───────────────────────────────────────────────────────────────────────────
 */

/*
 Key Darwin APIs used (adopted in our cpu_boost.c and MetricsIntegration.swift):

 1. proc_pidinfo(getpid(), PROC_PIDTASKALLINFO, ...)
    → Returns proc_taskallinfo containing:
      - pti_virtual_size     (virtual memory)
      - pti_resident_size    (resident memory)
      - pti_threadnum        (thread count)
      - pti_total_user       (user CPU Mach ticks)
      - pti_total_system     (system CPU Mach ticks)
      - pbi_start_tvsec      (process start time)

 2. mach_timebase_info()
    → Converts Mach absolute time ticks to nanoseconds
    → ratio = numer / denom

 3. proc_pidinfo(getpid(), PROC_PIDLISTFDS, ...)
    → Counts open file descriptors

 4. getrlimit(RLIMIT_NOFILE, ...)
    → Maximum file descriptors

 Reference implementation:

 #if canImport(Darwin)
 import Darwin

 extension SystemMetricsMonitorDataProvider: SystemMetricsProvider {
     package func data() async -> SystemMetricsMonitor.Data? {
         #if os(macOS)
         Self.darwinSystemMetrics()
         #else
         return nil
         #endif
     }

     #if os(macOS)
     package static func darwinSystemMetrics() -> SystemMetricsMonitor.Data? {
         guard let taskInfo = ProcessTaskInfo.snapshot() else { return nil }
         guard let fileCounts = FileDescriptorCounts.snapshot() else { return nil }

         let virtualMemoryBytes = Int(taskInfo.ptinfo.pti_virtual_size)
         let residentMemoryBytes = Int(taskInfo.ptinfo.pti_resident_size)
         let threadCount = Int(taskInfo.ptinfo.pti_threadnum)

         let userMachTicks = taskInfo.ptinfo.pti_total_user
         let systemMachTicks = taskInfo.ptinfo.pti_total_system
         let cpuTimeSeconds: Double = {
             let totalUserTime = Double(userMachTicks) * machTimebaseRatio
             let totalSystemTime = Double(systemMachTicks) * machTimebaseRatio
             return (totalUserTime + totalSystemTime) / Double(NSEC_PER_SEC)
         }()

         return .init(
             virtualMemoryBytes: virtualMemoryBytes,
             residentMemoryBytes: residentMemoryBytes,
             startTimeSeconds: Int(taskInfo.pbsd.pbi_start_tvsec),
             cpuSeconds: cpuTimeSeconds,
             maxFileDescriptors: fileCounts.maximum,
             openFileDescriptors: fileCounts.open,
             threadCount: threadCount
         )
     }
     #endif
 }
 #endif
 */
