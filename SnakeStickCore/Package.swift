// swift-tools-version: 6.4

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ApproachableConcurrency"),
]

let package = Package(
    name: "SnakeStickCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "SnakeStickCore",
            targets: ["SnakeStickCore"]
        ),
        .executable(
            name: "snakestick",
            targets: ["snakestick"]
        ),
    ],
    dependencies: [
        .package(path: "../slopdisk"),
        .package(path: "../NTFS3G"),
        .package(path: "../WIMLib"),
    ],
    targets: [
        .target(
            name: "SnakeStickCore",
            dependencies: [
                .product(name: "SlopDisk", package: "slopdisk"),
                .product(name: "NTFS3G", package: "NTFS3G"),
                .product(name: "WIMLib", package: "WIMLib"),
            ],
            resources: [
                .copy("Resources/UEFI-NTFS"),
            ],
            swiftSettings: swiftSettings,
            linkerSettings: [
                .linkedFramework("DiskArbitration"),
                .linkedFramework("IOKit"),
            ]
        ),
        .executableTarget(
            name: "snakestick",
            dependencies: ["SnakeStickCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SnakeStickCoreTests",
            dependencies: [
                "SnakeStickCore",
                .product(name: "SlopDisk", package: "slopdisk"),
                .product(name: "NTFS3G", package: "NTFS3G"),
                .product(name: "WIMLib", package: "WIMLib"),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
