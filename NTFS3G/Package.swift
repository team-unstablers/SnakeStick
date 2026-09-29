// swift-tools-version: 6.4

import PackageDescription

// libntfs-3g and mkntfs, built from the pristine upstream submodule at Vendor/ntfs-3g.
//
// Vendor/CNTFS3G/config.h is generated on macOS at the submodule's tag and committed:
//
//     LIBTOOLIZE=glibtoolize ./autogen.sh
//     ./configure --disable-ntfs-3g --disable-plugins --disable-nfconv --disable-crypto \
//                 --disable-shared --enable-static
//
// Regenerate it whenever the submodule is moved to another tag.

let libntfs3gSources = [
    "acls.c", "attrib.c", "attrlist.c", "bitmap.c", "bootsect.c", "cache.c", "collate.c",
    "compat.c", "compress.c", "debug.c", "device.c", "dir.c", "ea.c", "efs.c", "index.c",
    "inode.c", "ioctl.c", "lcnalloc.c", "logfile.c", "logging.c", "mft.c", "misc.c", "mst.c",
    "object_id.c", "realpath.c", "reparse.c", "runlist.c", "security.c", "unistr.c",
    "volume.c", "xattrs.c", "unix_io.c",
].map { "ntfs-3g/libntfs-3g/\($0)" }

// mkntfs_SOURCES in ntfsprogs/Makefile.am. main() is renamed to ntfs3g_mkntfs_main so that
// mkntfs can be called in-process without patching the submodule; CNTFS3G/mkntfs_entry.c wraps it.
let mkntfsSources = [
    "attrdef.c", "boot.c", "sd.c", "mkntfs.c", "utils.c",
].map { "ntfs-3g/ntfsprogs/\($0)" } + [
    "CNTFS3G/mkntfs_entry.c",
]

let package = Package(
    name: "NTFS3G",
    products: [
        .library(
            name: "CNTFS3G",
            targets: ["CNTFS3G"]
        ),
    ],
    targets: [
        .target(
            name: "CNTFS3G",
            path: "Vendor",
            sources: libntfs3gSources + mkntfsSources,
            publicHeadersPath: "CNTFS3G/include",
            cSettings: [
                .define("HAVE_CONFIG_H"),
                .define("main", to: "ntfs3g_mkntfs_main"),
                .headerSearchPath("CNTFS3G"),
                .headerSearchPath("ntfs-3g/include/ntfs-3g"),
            ],
        ),
        .testTarget(
            name: "CNTFS3GTests",
            dependencies: ["CNTFS3G"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
