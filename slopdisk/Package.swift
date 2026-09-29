// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SlopDisk",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "SlopDisk",
            targets: ["SlopDisk"]
        ),
        .executable(
            name: "sdinspect",
            targets: ["sdinspect"]
        ),
    ],
    targets: [
        .target(
            name: "SlopDisk",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .executableTarget(
            name: "sdinspect",
            dependencies: ["SlopDisk"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "SlopDiskTests",
            dependencies: ["SlopDisk"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
