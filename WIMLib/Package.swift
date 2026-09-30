// swift-tools-version: 6.4
// SPDX-License-Identifier: LGPL-2.1-or-later

import PackageDescription

// libwim, built from the pristine upstream wimlib submodule at Vendor/wimlib.
//
// Vendor/CWIMLib/config.h is generated on macOS at the submodule's tag and committed:
//
//     LIBTOOLIZE=glibtoolize ./bootstrap
//     ./configure --without-fuse --without-ntfs-3g --disable-shared --enable-static
//
// Regenerate it whenever the submodule is moved to another tag, in a scratch clone of the
// submodule (never inside Vendor/wimlib). Unlike ntfs-3g, wimlib does not react to the DEBUG
// macro that SwiftPM and Xcode define in debug builds, so config.h is used as generated.

// libwim_la_SOURCES in Makefile.am, plus the sources its non-Windows branch adds
// (unix_apply.c, unix_capture.c). The ntfs-3g, FUSE-free Windows and test-support sources are
// left out, as configure leaves them out with the options above.
let libwimSources = [
    "add_image.c", "avl_tree.c", "blob_table.c", "compress.c", "compress_common.c",
    "compress_parallel.c", "compress_serial.c", "cpu_features.c", "decompress.c",
    "decompress_common.c", "delete_image.c", "dentry.c", "divsufsort.c", "encoding.c", "error.c",
    "export_image.c", "extract.c", "file_io.c", "header.c", "inode.c", "inode_fixup.c",
    "inode_table.c", "integrity.c", "iterate_dir.c", "join.c", "lcpit_matchfinder.c",
    "lzms_common.c", "lzms_compress.c", "lzms_decompress.c", "lzx_common.c", "lzx_compress.c",
    "lzx_decompress.c", "metadata_resource.c", "mount_image.c", "pathlist.c", "paths.c",
    "pattern.c", "progress.c", "reference.c", "registry.c", "reparse.c", "resource.c", "scan.c",
    "security.c", "sha1.c", "solid.c", "split.c", "tagged_items.c", "template.c", "textfile.c",
    "threads.c", "timestamp.c", "update_image.c", "util.c", "verify.c", "wim.c", "write.c",
    "xml.c", "xml_windows.c", "xmlproc.c", "xpress_compress.c", "xpress_decompress.c",
    "unix_apply.c", "unix_capture.c",
].map { "wimlib/src/\($0)" }

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ApproachableConcurrency"),
]

let package = Package(
    name: "WIMLib",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "WIMLib",
            targets: ["WIMLib"]
        ),
    ],
    targets: [
        .target(
            name: "WIMLib",
            dependencies: ["CWIMLib"],
            swiftSettings: swiftSettings,
        ),
        .target(
            name: "CWIMLib",
            path: "Vendor",
            sources: libwimSources,
            publicHeadersPath: "CWIMLib/include",
            cSettings: [
                // AM_CPPFLAGS and libwim_la_CFLAGS in Makefile.am.
                .define("HAVE_CONFIG_H"),
                .define("BUILDING_WIMLIB"),
                .define("_LARGEFILE_SOURCE"),
                .define("_FILE_OFFSET_BITS", to: "64"),
                .define("_GNU_SOURCE"),
                .headerSearchPath("CWIMLib"),
                .headerSearchPath("wimlib/include"),
                // PLATFORM_CFLAGS and AM_CFLAGS in configure.ac and Makefile.am. -std=gnu99 is
                // cLanguageStandard below. -fno-common is not redundant: SwiftPM passes -fcommon.
                //
                // -fno-modules is a workaround, not an upstream flag. SwiftPM compiles C targets
                // with clang modules, so including any system header makes the whole Darwin
                // module visible, and Mach's thread_create() (mach/task.h) then conflicts with
                // wimlib's internal thread_create() (include/wimlib/threads.h). Without modules
                // the sources see only the headers they include, as in the autotools build.
                .unsafeFlags(["-fvisibility=hidden", "-fno-common", "-Wno-pointer-sign", "-fno-modules"]),
            ],
        ),
        .testTarget(
            name: "CWIMLibTests",
            dependencies: ["CWIMLib"],
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "WIMLibTests",
            // CWIMLib for the WIMLIB_ERR_* constants only; tests call wimlib through WIMLib.
            dependencies: ["WIMLib", "CWIMLib"],
            swiftSettings: swiftSettings,
        ),
    ],
    cLanguageStandard: .gnu99
)
