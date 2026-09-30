// swift-tools-version: 6.4
// SPDX-License-Identifier: GPL-2.0-or-later

import PackageDescription

// libntfs-3g and mkntfs, built from the pristine upstream submodule at Vendor/ntfs-3g.
//
// Vendor/CNTFS3G/config.h is generated on macOS at the submodule's tag and committed:
//
//     LIBTOOLIZE=glibtoolize ./autogen.sh
//     ./configure --disable-ntfs-3g --disable-plugins --disable-nfconv --disable-crypto \
//                 --disable-shared --enable-static
//
// Regenerate it whenever the submodule is moved to another tag. The sources do not include it
// directly: Vendor/CNTFS3G/override/config.h, found first in the header search paths, includes
// it and undefines the DEBUG macro that SwiftPM and Xcode define in debug builds.

let libntfs3gSources = [
    "acls.c", "attrib.c", "attrlist.c", "bitmap.c", "bootsect.c", "cache.c", "collate.c",
    "compat.c", "compress.c", "debug.c", "device.c", "dir.c", "ea.c", "efs.c", "index.c",
    "inode.c", "ioctl.c", "lcnalloc.c", "logfile.c", "logging.c", "mft.c", "misc.c", "mst.c",
    "object_id.c", "realpath.c", "reparse.c", "runlist.c", "security.c", "unistr.c",
    "volume.c", "xattrs.c", "unix_io.c",
].map { "ntfs-3g/libntfs-3g/\($0)" }

// mkntfs_SOURCES in ntfsprogs/Makefile.am. main() is renamed to ntfs3g_mkntfs_main so that
// mkntfs can be called in-process without patching the submodule; CNTFS3G/mkntfs_entry.c wraps it.
//
// ntfsprogs/mkntfs.c itself is not listed: mkntfs_entry.c #includes it, so that it can reset
// mkntfs's file-scope statics between runs (mkntfs_cleanup() leaves a dangling pointer behind,
// and a second run in the same process walks freed memory).
let mkntfsSources = [
    "attrdef.c", "boot.c", "sd.c", "utils.c",
].map { "ntfs-3g/ntfsprogs/\($0)" } + [
    "CNTFS3G/mkntfs_entry.c",
]

// C helpers for the Swift target: logging setup and function-like macros that Swift cannot import.
let helperSources = [
    "CNTFS3G/cntfs3g_helpers.c",
]

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ApproachableConcurrency"),
]

let package = Package(
    name: "NTFS3G",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "NTFS3G",
            targets: ["NTFS3G"]
        ),
    ],
    targets: [
        .target(
            name: "NTFS3G",
            dependencies: ["CNTFS3G"],
            swiftSettings: swiftSettings,
        ),
        .target(
            name: "CNTFS3G",
            path: "Vendor",
            sources: libntfs3gSources + mkntfsSources + helperSources,
            publicHeadersPath: "CNTFS3G/include",
            cSettings: [
                .define("HAVE_CONFIG_H"),
                .define("main", to: "ntfs3g_mkntfs_main"),
                // Must stay ahead of "CNTFS3G" so that "config.h" resolves to the override.
                .headerSearchPath("CNTFS3G/override"),
                .headerSearchPath("CNTFS3G"),
                .headerSearchPath("ntfs-3g/include/ntfs-3g"),
            ],
        ),
        .testTarget(
            name: "CNTFS3GTests",
            dependencies: ["CNTFS3G"],
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "NTFS3GTests",
            dependencies: ["NTFS3G"],
            swiftSettings: swiftSettings,
        ),
    ]
)
