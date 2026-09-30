# NAME

WIMLib - read Windows Imaging (WIM) files from Swift, on top of wimlib

# STATUS

The Swift API is implemented. Work is tracked by the task documents in `Prompts/`:

| Stage | Document | Scope | State |
|---|---|---|---|
| 10 | `Prompts/10-swift-api.xml` | Scaffold, open a WIM, image metadata, extract paths, create test WIMs | implemented (`Prompts/10-swift-api.report.md`) |

It has been tested only against WIM files it created itself, not against a `boot.wim` from a Windows ISO (see KNOWN LIMITATIONS).

# SYNOPSIS

```swift
import Foundation
import WIMLib

// sources/boot.wim of a mounted Windows ISO. Image 1 is Windows PE, image 2 is Windows Setup.
let wim = try WIMFile(path: "/Volumes/CCCOMA_X64FRE_EN-US_DV9/sources/boot.wim")
defer { wim.close() }

for image in try wim.images {
    print(image.index, image.name ?? "", image.architecture.map { "\($0)" } ?? "", image.build ?? 0)
}
let setup = try wim.images[1]
let isX64 = setup.architecture == .x64            // WINDOWS/ARCH
let build = setup.build ?? 0                      // WINDOWS/VERSION/BUILD, 26200 for Windows 11 25H2
let edition = try wim.property("WINDOWS/EDITIONID", ofImage: 2)

// Extract the boot files signed with the Windows UEFI CA 2023, as Rufus does. The target
// directory must exist. Each directory lands in it as a whole:
// /tmp/ca2023/EFI_EX/bootmgfw_EX.efi, /tmp/ca2023/EFI_EX/bootmgr_EX.efi, /tmp/ca2023/Fonts_EX/...
let target = URL(fileURLWithPath: "/tmp/ca2023", isDirectory: true)
try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
try wim.extract(paths: ["/Windows/Boot/EFI_EX", "/Windows/Boot/Fonts_EX"], fromImage: 2, to: target)

// For tests: a two-image stand-in for boot.wim, captured from two host directories.
try WIMFile.create(images: [
    WIMImageSource(directory: URL(fileURLWithPath: "/tmp/fixture/pe"), name: "Microsoft Windows PE (x64)"),
    WIMImageSource(directory: URL(fileURLWithPath: "/tmp/fixture/setup"), name: "Microsoft Windows Setup (x64)",
                   properties: ["WINDOWS/ARCH": "9", "WINDOWS/VERSION/BUILD": "26200"]),
], to: "/tmp/fixture/boot.wim")
```

# DESCRIPTION

WIMLib gives SnakeStick the two things it needs from a Windows ISO's `sources/boot.wim`: the image metadata (architecture and build number, shown as ISO information) and a few extracted files (the `Windows/Boot/EFI_EX` and `Windows/Boot/Fonts_EX` directories for the "Windows UEFI CA 2023 signed boot loaders" option). [wimlib](https://wimlib.net) does the WIM work, including LZX and XPRESS decompression.

## Types

| Type | Role |
|---|---|
| `WIMFile` | An open WIM file. `init(path:)`, `images`, `property(_:ofImage:)`, `extract(paths:fromImage:to:)`, `close()`, and for tests `create(images:to:compression:)` and `create(from:to:compression:imageName:properties:)`. `wimlibVersion` is the linked wimlib's version. |
| `WIMImage` | One image's metadata, copied out of the file: `index` (1-based), `name`, `description`, `displayName`, `architecture`, `major`, `minor`, `build` |
| `WIMArchitecture` | `WINDOWS/ARCH`: `x86` (0), `arm` (5), `x64` (9), `arm64` (12), or `other(Int)` |
| `WIMImageSource`, `WIMCompression` | Input to `create`: a directory, a name and properties per image; `none`, `xpress` or `lzx` |
| `WIMLibError` | Every error thrown: `wimlib(code:message:)` with wimlib's `WIMLIB_ERR_*` code, `posix(operation:path:errno:)`, `closed` |

## Behavior

- **Paths inside an image** are absolute, such as `/Windows/Boot/EFI_EX`. `\` is accepted as a separator too, and the leading separator may be left out, so Rufus's `Windows\Boot\EFI_EX` works. Names are matched **ignoring case**, as on Windows.
- **`extract`** places each path directly in the target directory, without the directories above it: a file `/a/b/c.efi` becomes `target/c.efi`, and a directory `/a/b` becomes `target/b` with everything below it. It uses wimlib's `WIMLIB_EXTRACT_FLAG_NO_PRESERVE_DIR_STRUCTURE | WIMLIB_EXTRACT_FLAG_NO_ACLS`, the flags Rufus uses. Existing files are replaced. If one path does not exist, nothing is extracted (`WIMLIB_ERR_PATH_DOES_NOT_EXIST`). The target directory must exist (`posix` `ENOENT` otherwise).
- **Image metadata.** `images` reads the WIM's XML metadata. Missing properties are `nil`, and so are numeric properties that are not plain decimal integers. `property(_:ofImage:)` reads any other element with wimlib's syntax: element names separated by `/`, and `[N]` for the Nth of several elements with the same name, as in `WINDOWS/LANGUAGES/LANGUAGE[2]`. Element names are case-sensitive.
- **Image indexes** start at 1. An index that is not an image of the file is `WIMLIB_ERR_INVALID_IMAGE`.
- **`create`** is for tests and fixtures. It captures host directories into a new WIM, one image per directory, sets the given XML properties, and replaces an existing file. It is not meant for making Windows images: it stores no Windows security descriptors and no UNIX owners or modes.
- **`close()`** releases the file and may be called more than once. Other methods then throw `closed`. `deinit` closes too. `WIMImage` values stay valid after closing.
- **Concurrency.** `WIMFile` is a non-`Sendable` class with blocking calls: wimlib allows different WIM files to be used from different threads, but not one WIM file from several threads at once. Use each instance from one task. `WIMImage` is `Sendable`.

# DESIGN NOTES

- **wimlib, unmodified.** `Vendor/wimlib` is the upstream [ebiggers/wimlib](https://github.com/ebiggers/wimlib) repository as a submodule pinned to tag `v1.14.5`, and is never patched. The C target `CWIMLib` compiles the library's sources (`libwim_la_SOURCES` in `Makefile.am`, plus `unix_apply.c` and `unix_capture.c`) straight from the submodule; the Swift target `WIMLib` imports it with `internal import`, so no C type appears in the public API.
- **`config.h`** is generated once on macOS and committed as `Vendor/CWIMLib/config.h`. After moving the submodule to another tag, regenerate it in a scratch clone of the submodule (never inside `Vendor/wimlib`) and check the source list in `Package.swift` against `Makefile.am`:

  ```sh
  LIBTOOLIZE=glibtoolize ./bootstrap
  ./configure --without-fuse --without-ntfs-3g --disable-shared --enable-static
  ```

  Unlike libntfs-3g, wimlib does not look at the `DEBUG` macro that SwiftPM and Xcode define in debug builds, so `config.h` is used as generated. Neither configuration defines `NDEBUG`, so wimlib's assertions are on in both, as in upstream builds.
- **Compiler flags.** The C target uses upstream's `-std=gnu99`, `-fvisibility=hidden`, `-fno-common` (SwiftPM passes `-fcommon` otherwise) and `-Wno-pointer-sign`, plus one workaround: `-fno-modules`. SwiftPM compiles C targets with clang modules, so including any system header makes the whole `Darwin` module visible, and Mach's `thread_create()` then conflicts with wimlib's internal function of the same name. Without modules the sources see only the headers they include, as in the autotools build.
- **Symbol visibility.** SwiftPM links the C target's objects into one relocatable object (`CWIMLib.o`), and in that step every symbol hidden by `-fvisibility=hidden` becomes local. Only the `wimlib_*` API stays global, so wimlib's internal names (`sha1_*`, `lzx_*`, `xml_*`, ...) cannot clash with libntfs-3g or anything else linked into SnakeStick.
- **Initialization.** The first use of `WIMFile` calls `wimlib_global_init` with `WIMLIB_INIT_FLAG_DEFAULT_CASE_INSENSITIVE` (wimlib's default on UNIX-like systems is case-sensitive) and turns off wimlib's error printing; errors are reported through `WIMLibError` instead. This happens once per process, and nothing in the process may call wimlib before it: wimlib's own functions initialize the library implicitly with default flags, after which the case setting can no longer change.

# KNOWN LIMITATIONS

These are accepted trade-offs, not design goals.

- **Not yet run against a real `boot.wim`.** Every test uses WIM files that wimlib wrote. Reading WIMs written by Microsoft's tools is wimlib's everyday use, but it has not been checked here.
- **Read and extract only.** No mounting (FUSE), no capture to or apply from NTFS volumes (wimlib is built without libntfs-3g), no modifying, deleting, splitting or exporting images, and no split WIMs (`.swm`): `install.swm` parts would need `wimlib_reference_resource_files`, which is not wrapped. `create` exists for fixtures only.
- **No progress reporting.** SnakeStick extracts a few small files.
- **Case-insensitive lookups for the whole process.** The setting is global in wimlib.
- **macOS on arm64 only.** `config.h` was generated on macOS 26 (arm64); x86_64 builds have not been tried.

# REQUIREMENTS

- macOS 13 or later
- Swift 6.4 toolchain
- To regenerate `config.h` only: autoconf, automake, libtool (`glibtoolize`) and pkg-config

# TESTING

```sh
swift test
swift test -c release
```

The tests need no network access or privileges. They create WIM files from small trees under the temporary directory and remove them afterwards.

# LICENSE

LGPL-2.1-or-later. The full text is in `LICENSE`.

wimlib is copyright 2012-2023 Eric Biggers and is used at tag `v1.14.5`. wimlib as a whole is licensed under GPL-3.0-or-later; libwim, the library part that this package compiles, may alternatively be used under LGPL-2.1-or-later when it is built without libntfs-3g, as it is here (see `Vendor/wimlib/COPYING`). This package takes the LGPL option. Some wimlib source files carry a more permissive MIT-style license in their headers, among them `divsufsort.c` (copyright 2003-2008 Yuta Mori).
