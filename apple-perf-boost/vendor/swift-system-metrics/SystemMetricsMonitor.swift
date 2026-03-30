/*
 * SystemMetricsMonitor.swift
 *
 * Vendored from: https://github.com/apple/swift-system-metrics
 * Commit: 758865b (2026-03-15) - "Add threadCount gauge (#98)"
 * License: Apache 2.0 (see LICENSE.txt)
 *
 * This is the core monitor from apple/swift-system-metrics that periodically
 * collects process-level system metrics and reports them to Swift Metrics.
 *
 * Included here as reference for the PerfBoost project's MetricsIntegration.
 * See the original repo for the full, maintained version.
 *
 * ───────────────────────────────────────────────────────────────────────────
 * NOTE: This is a *reference copy*. The canonical source is:
 *   https://github.com/apple/swift-system-metrics/blob/main/Sources/SystemMetrics/SystemMetricsMonitor.swift
 *
 * Original copyright:
 *   Copyright (c) 2025 Apple Inc. and the Swift System Metrics API project authors
 *   Licensed under Apache License v2.0
 *   SPDX-License-Identifier: Apache-2.0
 * ───────────────────────────────────────────────────────────────────────────
 */

// The SystemMetricsMonitor is a Service that:
//   1. Uses AsyncTimerSequence to tick at a configurable interval
//   2. On each tick, calls dataProvider.data() to fetch process stats
//   3. Reports those stats as Gauges via Swift Metrics
//
// Gauges reported:
//   - process_virtual_memory_bytes
//   - process_resident_memory_bytes
//   - process_start_time_seconds
//   - process_cpu_seconds_total
//   - process_max_fds
//   - process_open_fds
//   - process_thread_count
//
// Key design decisions we adopt in PerfBoost:
//   - Pre-initialize Gauge objects once (avoid repeated creation)
//   - Use a configurable Labels struct with a prefix
//   - Fail gracefully when metric collection is unavailable

/*
 Simplified reference structure (requires swift-metrics, swift-service-lifecycle,
 swift-async-algorithms as dependencies — see Package.swift in the original repo):

 public struct SystemMetricsMonitor: Service {
     let configuration: Configuration
     let metricsFactory: (any MetricsFactory)?
     let dataProvider: any SystemMetricsProvider
     let logger: Logger

     // Pre-initialized gauges
     let virtualMemoryBytesGauge: Gauge
     let residentMemoryBytesGauge: Gauge
     let startTimeSecondsGauge: Gauge
     let cpuSecondsTotalGauge: Gauge
     let maxFileDescriptorsGauge: Gauge
     let openFileDescriptorsGauge: Gauge
     let threadCountGauge: Gauge

     public func run() async throws {
         for await _ in AsyncTimerSequence(interval: configuration.interval,
                                           clock: .continuous)
             .cancelOnGracefulShutdown()
         {
             await updateMetrics()
         }
     }

     func updateMetrics() async {
         guard let metrics = await dataProvider.data() else { return }
         virtualMemoryBytesGauge.record(metrics.virtualMemoryBytes)
         residentMemoryBytesGauge.record(metrics.residentMemoryBytes)
         startTimeSecondsGauge.record(metrics.startTimeSeconds)
         cpuSecondsTotalGauge.record(metrics.cpuSeconds)
         maxFileDescriptorsGauge.record(metrics.maxFileDescriptors)
         openFileDescriptorsGauge.record(metrics.openFileDescriptors)
         threadCountGauge.record(metrics.threadCount)
     }
 }
 */
