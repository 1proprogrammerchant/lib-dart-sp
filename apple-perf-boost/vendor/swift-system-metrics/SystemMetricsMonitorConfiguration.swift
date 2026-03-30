/*
 * SystemMetricsMonitorConfiguration.swift
 *
 * Vendored from: https://github.com/apple/swift-system-metrics
 * Commit: 758865b (2026-03-15)
 * License: Apache 2.0
 *
 * Configuration struct for the system metrics monitor.
 *
 * Original copyright:
 *   Copyright (c) 2025 Apple Inc. and the Swift System Metrics API project authors
 *   Licensed under Apache License v2.0
 *   SPDX-License-Identifier: Apache-2.0
 *
 * ───────────────────────────────────────────────────────────────────────────
 * This is a reference copy. See the original repo for the maintained version:
 *   https://github.com/apple/swift-system-metrics/blob/main/Sources/SystemMetrics/SystemMetricsMonitorConfiguration.swift
 * ───────────────────────────────────────────────────────────────────────────
 */

/*
 Reference structure (adopted in our PerfBoostMetricsLabels):

 extension SystemMetricsMonitor {
     public struct Configuration: Sendable {
         public static let `default`: Self = .init()
         public var interval: Duration

         package let labels: Labels
         package let dimensions: [(String, String)]

         public init(pollInterval interval: Duration = .seconds(15)) {
             self.interval = interval
             self.labels = .init()
             self.dimensions = []
         }
     }
 }

 extension SystemMetricsMonitor.Configuration {
     package struct Labels: Sendable {
         package var prefix: String = "process_"
         package var virtualMemoryBytes: String = "virtual_memory_bytes"
         package var residentMemoryBytes: String = "resident_memory_bytes"
         package var startTimeSeconds: String = "start_time_seconds"
         package var cpuSecondsTotal: String = "cpu_seconds_total"
         package var maxFileDescriptors: String = "max_fds"
         package var openFileDescriptors: String = "open_fds"
         package var threadCount: String = "thread_count"

         package func label(for keyPath: KeyPath<Labels, String>) -> String {
             self.prefix + self[keyPath: keyPath]
         }

         package init() {}
     }
 }
 */
