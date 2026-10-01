// swift-tools-version: 6.4
// SPDX-License-Identifier: GPL-3.0-or-later

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
            swiftSettings: swiftSettings,
            linkerSettings: [
                // The app bundles this tool as Contents/Helpers/snakestick. Linked into both the
                // app and the tool, the packages become frameworks in Contents/Frameworks, and
                // Xcode gives the tool only @loader_path and a path into its build directory.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "SnakeStickCoreTests",
            dependencies: [
                "SnakeStickCore",
                // For the argument parser and exit codes; the built binary is run as well.
                "snakestick",
                .product(name: "SlopDisk", package: "slopdisk"),
                .product(name: "NTFS3G", package: "NTFS3G"),
                .product(name: "WIMLib", package: "WIMLib"),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
