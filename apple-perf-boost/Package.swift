// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "ApplePerfBoost",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "perf-boost", targets: ["PerfBoostCLI"]),
        .library(name: "PerfBoostLib", targets: ["PerfBoostLib"]),
    ],
    dependencies: [
        // Reference dependency — the project we drew patterns from
        .package(url: "https://github.com/apple/swift-system-metrics.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-metrics.git", from: "2.7.1"),
    ],
    targets: [
        // ── C/ObjC bridge target ──────────────────────────────
        .target(
            name: "CPerfBoost",
            dependencies: [],
            path: "src",
            exclude: ["perf_engine.cpp", "perf_engine.hpp"],
            sources: ["cpu_boost.c", "perf_utils.c", "gpu_boost.mm"],
            publicHeadersPath: "../include",
            cSettings: [
                .headerSearchPath("../include"),
            ],
            linkerSettings: [
                .linkedFramework("Metal", .when(platforms: [.macOS])),
                .linkedFramework("Foundation", .when(platforms: [.macOS])),
            ]
        ),

        // ── Swift library ─────────────────────────────────────
        .target(
            name: "PerfBoostLib",
            dependencies: [
                "CPerfBoost",
                .product(name: "SystemMetrics", package: "swift-system-metrics"),
                .product(name: "Metrics", package: "swift-metrics"),
            ],
            path: "swift",
            exclude: ["main.swift"]
        ),

        // ── CLI executable ────────────────────────────────────
        .executableTarget(
            name: "PerfBoostCLI",
            dependencies: ["PerfBoostLib"],
            path: "swift",
            sources: ["main.swift"]
        ),
    ]
)
