# NAME

NTFS3G - create NTFS partition images from Swift, on top of libntfs-3g

# STATUS

The Swift API is implemented. Work is tracked by the task documents in `Prompts/`:

| Stage | Document | Scope | State |
|---|---|---|---|
| 10 | `Prompts/10-swift-api.xml` | Swift API: format, write, copy a tree, read back, size estimate | implemented (`Prompts/10-swift-api.report.md`) |

Windows itself has not yet read a volume made by this package (see KNOWN LIMITATIONS).

# SYNOPSIS

```swift
import Foundation
import NTFS3G

let source = URL(fileURLWithPath: "/Volumes/CCCOMA_X64FRE_EN-US_DV9")  // a mounted Windows ISO
let image = "/tmp/windows-data.img"

// Size the partition for the ISO's contents and create the image file at that size.
let size = try NTFSVolume.estimatedVolumeSize(forTreeAt: source)
FileManager.default.createFile(atPath: image, contents: nil)
let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: image))
try handle.truncate(atOffset: UInt64(size))
try handle.close()

// Format it. partitionStartSector is where the partition will start in the disk image.
try NTFSVolume.format(path: image, options: .init(label: "WIN11", partitionStartSector: 2048))

// Copy the files. All calls block on I/O; make them from a background task.
let volume = try NTFSVolume(path: image, mode: .readWrite)
let summary = try volume.copyTree(from: source) { progress in
    print("\(progress.completedBytes) / \(progress.totalBytes) \(progress.currentPath)")
}
try volume.close()
print("\(summary.files) files, \(summary.directories) directories, \(summary.bytes) bytes")

// Read it back.
let check = try NTFSVolume(path: image, mode: .readOnly)
for entry in try check.contentsOfDirectory("/") {
    print(entry.name, entry.kind)
}
print(try check.attributesOfItem("/sources/install.wim").size)
try check.close()
```

# DESCRIPTION

NTFS3G builds the NTFS data partition of SnakeStick's Windows installation media in user space. The image file holds exactly one partition, starting at byte 0; placing it inside a disk image is the caller's job. libntfs-3g, the library behind the ntfs-3g driver, does the NTFS work, and mkntfs formats the volume in-process.

## Types

| Type | Role |
|---|---|
| `NTFSVolume` | A mounted volume. `format(path:options:)`, `estimatedVolumeSize(forTreeAt:clusterSize:)`, `init(path:mode:)`, `createDirectory`, `writeFile` (from a host file or from bytes), `copyTree`, `contentsOfDirectory`, `attributesOfItem`, `readFile`, `close()` |
| `NTFSFormatOptions` | Label, cluster size, sector size (512 or 4096) and partition start sector (recorded in the boot sector) |
| `NTFSFileTimes` | Creation, modification and access times |
| `NTFSDirectoryEntry`, `NTFSItemAttributes`, `NTFSItemKind` | Results of the read calls |
| `NTFSCopyProgress`, `NTFSCopySummary` | Progress and result of `copyTree` |
| `NTFS3GError` | Every error thrown |

## Behavior

- **Paths** are absolute NTFS paths such as `/sources/install.wim`. Empty, `.` and `..` components are rejected (`invalidPath`).
- **Names** are normalized to Unicode NFC before they are stored or looked up. Names that Windows cannot use are rejected (`invalidName`): the characters `"*/:<>?\|` and control characters, a trailing dot or space, reserved device names (`CON`, `NUL`, `COM1`, ...), and more than 255 UTF-16 code units. Volume labels follow the same rules except for device names, with a limit of 32 code units.
- **Case.** Lookups match names exactly. Creating an item fails with `alreadyExists` if the directory already has a name that differs only in case, because Windows could not tell the two apart.
- **Nothing is overwritten.** Creating a file or directory that already exists is an error. Parents must exist; intermediate directories are not created. There is no delete, rename or truncate.
- **Times.** `writeFile` and `createDirectory` take optional times, applied after the data is written. `copyTree` maps the host's birth time to creation and the modification time to both modification and access. NTFS's fourth time, the MFT change time, is always the current time.
- **`copyTree`** copies the contents of a host directory into an existing directory, like `cp -R source/. destination`. It scans the whole tree first with `lstat`, so symbolic links, FIFOs, sockets, devices and names Windows cannot use are reported before anything is written. Files and directories are copied in name order in 8 MiB chunks; progress is reported per chunk. An error stops the copy and leaves what was copied; the usual recovery is to discard the image.
- **`estimatedVolumeSize`** returns a conservative size, a multiple of 1 MiB, for which `format` followed by `copyTree` of the same tree succeeds. See DESIGN NOTES.
- **Concurrency.** `NTFSVolume` is a non-`Sendable` class with blocking calls. Use each instance from one task. Calls to `format` are serialized internally.

# DESIGN NOTES

- **libntfs-3g, unmodified.** `Vendor/ntfs-3g` is the upstream [tuxera/ntfs-3g](https://github.com/tuxera/ntfs-3g) repository as a submodule pinned to tag 2026.9.28, and is never patched. Where upstream behavior has to change, C code outside the submodule works around it (next two points). The C target `CNTFS3G` compiles the library and mkntfs from the submodule; the Swift target `NTFS3G` imports it with `internal import`, so no C type appears in the public API.
- **`config.h`** is generated once on macOS and committed as `Vendor/CNTFS3G/config.h`. After moving the submodule to another tag, regenerate it in a scratch copy of the submodule (never inside `Vendor/ntfs-3g`):

  ```sh
  LIBTOOLIZE=glibtoolize ./autogen.sh
  ./configure --disable-ntfs-3g --disable-plugins --disable-nfconv --disable-crypto \
              --disable-shared --enable-static
  ```

  The sources do not include it directly. `Vendor/CNTFS3G/override/config.h`, first in the header search paths, includes it and then undefines `DEBUG`: SwiftPM and Xcode define `DEBUG=1` for C targets in debug builds, and libntfs-3g treats that macro as its own debug switch (trace logging from every function, extra `exit()` checks).
- **mkntfs in-process.** mkntfs is a program meant to run once per process. `Vendor/CNTFS3G/mkntfs_entry.c` compiles `ntfsprogs/mkntfs.c` as part of itself (it is left out of the sources list) so that it can: reset mkntfs's static variables after each run, because `mkntfs_cleanup()` leaves a dangling list pointer that makes a second run crash or hang; redirect mkntfs's `utils_set_locale()` call, which would switch the whole process to the environment's locale (turning the decimal point into a comma under a German locale, for every thread, even while mkntfs runs), to a function that does nothing; and restore the libntfs-3g log handler and log levels that mkntfs changes. `main` is renamed with `-Dmain=ntfs3g_mkntfs_main`, and runs are serialized with a mutex. When the submodule moves to another tag, check the list of statics in `reset_mkntfs_globals()` against `mkntfs.c`.
- **Logging.** The first call to `NTFSVolume.format` or `NTFSVolume.init` installs libntfs-3g's stderr log handler for the whole process (the library default discards messages). Errors and warnings from libntfs-3g therefore appear on stderr. There is no API to redirect them.
- **Names in NFC.** NTFS stores names as UTF-16 without normalization. Windows produces NFC; Foundation and many macOS tools produce NFD (decomposed) names on the host, which a byte-exact copy would carry over. macOS's own NTFS driver (FSKit) cannot open items whose names are stored in NFD: it lists them, but every lookup fails. NTFS3G therefore normalizes every name it writes or looks up to NFC.
- **Case collisions** are found with libntfs-3g's own lookup run case-insensitively: `cntfs3g_lookup_ignoring_case()` clears the volume's case-sensitive flag for the duration of one `ntfs_inode_lookup_by_name()` call. The directory index is ordered by upper-cased name, so this is a normal B+tree lookup. `ntfs_set_ignore_case()` is not used because it would also make listings return lower-cased names.
- **Size estimate.** The sum of: file data rounded up to clusters (even files small enough to live in their MFT record count as one cluster); a 4 KiB MFT record per item plus 16 records of slack (records are 1 KiB with 512-byte sectors and 4 KiB with 4096-byte sectors; the estimate does not know which); for each non-empty directory, three times its index entries plus one 4 KiB index block, because B+tree nodes may be half empty; 1 MiB + 8 clusters for the empty volume's metadata (measured at 435 to 896 KiB); `$LogFile` (2 MiB below 200 MiB, 1/200 of the volume up to 12 GiB, 64 MiB above) and the cluster bitmap for the resulting size, found by iterating to a fixed point; one cluster for the backup boot sector; and a margin of 4 MiB plus 1/512 of the data. Measurements are in `Prompts/10-swift-api.report.md`.

# KNOWN LIMITATIONS

These are accepted trade-offs, not design goals.

- **Images hold one partition, starting at byte 0.** This is forced by mkntfs, which opens its target by path through libntfs-3g's POSIX file I/O and cannot start at an offset inside a larger file. The partition's position on the disk is only recorded in the boot sector (`partitionStartSector`, "hidden sectors"). SnakeStick copies the partition image into the disk image afterwards, which costs one extra copy.
- **File names are in the POSIX namespace, with no DOS 8.3 names.** `ntfs_create()` creates names that way; Windows creates Win32 names and, depending on settings, 8.3 aliases. Windows is expected to read such volumes, but that has not been verified, nor has Windows `chkdsk` been run on one.
- **Names stored in NFD cannot be opened.** Volumes written by NTFS3G contain only NFC names, but a volume written elsewhere may contain NFD names; they appear in listings and cannot be looked up through this API, nor through macOS's NTFS driver. NFC normalization also replaces the few characters with singleton decompositions, such as CJK compatibility ideographs, with their canonical equivalents.
- **mkntfs is patched from the outside.** The reset of its statics and the redirected locale call depend on the internals of `mkntfs.c` at the pinned tag.
- **No delete, rename, truncate or attribute changes**, and no alternate data streams, sparse files, compression or security descriptors beyond libntfs-3g's defaults. SnakeStick only builds new volumes.
- **macOS only.**

# REQUIREMENTS

- macOS 13 or later
- Swift 6.4 toolchain
- To regenerate `config.h` only: autoconf, automake and libtool (`glibtoolize`)

# TESTING

```sh
swift test                           # everything that runs on scratch image files
NTFS3G_INTEGRATION=1 swift test      # also attaches images with hdiutil and reads them through macOS's NTFS driver
```

The integration tests need no root privileges. They write a file of 4 GiB + 1 MiB (about 4.2 GB of disk space), attach images with `hdiutil attach -nomount`, mount them read-only with `diskutil mount readOnly`, and unmount and detach them afterwards, also when a test fails.

# LICENSE

GPL-2.0-or-later, the license of libntfs-3g. The full text is in `COPYING`.
