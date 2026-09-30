# CLAUDE.md

Guidance for coding agents working in this repository.

## What this is

SlopDisk is a Swift package that reads and writes GPT partition tables. It is the partition-table layer of **SnakeStick**, a macOS tool for making bootable USB sticks; the Xcode workspace lives one directory up (`../SnakeStick.xcworkspace`, which references this directory as `group:slopdisk`, so do not rename the `slopdisk/` directory itself).

Status: stage 10 (GPT core, memory/file backends, `sdinspect`) and stage 20 (`SDRawDevice`, `sdinspect` on `/dev/` paths) are implemented; see `Prompts/10-implementation.report.md` and `Prompts/20-raw-device.report.md`. See `README.md` for the public API and `Prompts/` for the task documents.

## Safety rules (non-negotiable)

- **Never open, read-write, or pass to any SlopDisk API a real disk device.** Not `/dev/disk0`, not "the USB stick that's probably disk4", nothing guessed or hard-coded.
- Tests may only operate on image files the test itself created in a unique temporary directory.
- The only permitted device paths are ones parsed from the output of an `hdiutil attach` that the same test just ran on such an image. Validate against `^/dev/r?disk[0-9]+$` and always `defer` a `hdiutil detach`.
  - `/dev/rdiskN` is derived from that `/dev/diskN`. A slice that appears only after SlopDisk wrote the table (`/dev/rdiskNsK`) is derived the same way and used only once `hdiutil info` lists it under the test's own image (`RawDeviceAttachTests.AttachedImage.rawSlice`). Validate against `^/dev/r?disk[0-9]+s[0-9]+$`.
- Always attach with `-nomount -imagekey diskimage-class=CRawDiskImage`.
- Tests that call `hdiutil attach` run only when `SLOPDISK_TEST_HDIUTIL_ATTACH=1`.
- Close every descriptor on an attached device (release the `SDDisk` / `SDRawDevice`) before `hdiutil detach`.
- `sdinspect` must stay read-only. It opens image files with `.readOnly` and `/dev/` paths with `SDRawDevice(readOnlyPath:)`; no write path may be reachable from that target. `SDInspectTests.sourceUsesNoWritePath` greps its sources for write APIs, including `dataLossRisk`.
- Every read-write `SDRawDevice` open takes `acknowledging: .dataLossRisk`. Do not add a public read-write path without it (`grep -rn dataLossRisk Sources/` must show only the definition and its call sites).

## Design decisions

The authoritative list is in `Prompts/10-implementation.xml` (`<decisions>`: D1–D31 were chosen by the user, P1–P10 by the planner) and `Prompts/20-raw-device.xml` (R1–R2, RP1–RP6). **Do not re-litigate user decisions.** If the code cannot follow one, stop and report instead of working around it silently. If a workaround is chosen, record that it was a workaround, and why, in a code comment.

The ones most likely to matter day to day:

- `SDBlockDevice` (public protocol) → `SDDisk` (the only place with GPT logic) ← `SDDiskImage` (factory enum).
- Synchronous API, `SDDisk` is non-`Sendable`. Library functions use `throws(SDError)`; only `withTransaction` is untyped.
- `SDTransaction` is `~Copyable` and passed `inout`. Explicit `commit()` is required; without it, changes are discarded. Operations validate and throw immediately.
- Sizes are binary units only (`.megabytes(1)` == 1 MiB). LBA `end` is **inclusive**.
- 512 and 4096 byte sectors. 1 MiB alignment, first-fit placement.
- Reading never writes. Damage is reported via `scheme == .gpt(.degraded(...))`; writes happen only in `repair()` / `commit()`.
- FAT32 and other file systems are out of scope (callers use `hdiutil attach -nomount` + `newfs_msdos`).
- macOS 13+ and Linux. Zero third-party dependencies. CRC32 and everything else are implemented in-house.
- Chosen by the user while implementing stage 10 (details in `Prompts/10-implementation.report.md`): `clear()` after `commit()` traps (it is non-throwing, so it cannot report `.transactionFinished`), and `SDFileBlockDevice` opens regular files only (device nodes throw `.invalidArgument`).
- Stage 20: `SDRawDevice` does not select disks, unmount, or escalate privileges (R1). Read-write opens need the `.dataLossRisk` token (R2); `init(readOnlyPath:)` does not (RP1). Ioctls go through the `CSlopDiskShim` C target, never hard-coded request numbers (RP2). A borrowed descriptor (`closeOnDeinit: false`) is never `flock`ed (RP3). Only character/block devices with 512/4096-byte sectors are accepted (RP5, RP6).

## Layout

```
Package.swift                 name "SlopDisk", macOS 13+; products: SlopDisk (library), sdinspect (executable);
                              targets: CSlopDiskShim (C) ← SlopDisk ← sdinspect
Sources/SlopDisk/
  SDSize.swift                SDSize, SDPartitionExtent
  SDError.swift
  SDBlockDevice.swift         protocol, SDOpenMode, request validation shared by the built-in backends
  SDInspection.swift          the read path: MBR/header reports and the scheme verdict (never writes)
  SDDisk.swift                GPT engine: refresh, repair, the crash-safe write procedure and read-back check
  SDTransaction.swift         staged edits and placement (first-fit, 1 MiB alignment, lowest free slot)
  SDDiskImage.swift           factory, SDDiskImageSource, sector-size detection (package access, used by sdinspect)
  Devices/                    SDMemoryBlockDevice (sparse 64 KiB chunks), SDFileBlockDevice (flock), POSIXIO,
                              SDRawDevice (device nodes: ioctl geometry, aligned 1 MiB bounce buffer, cache flush)
  Model/                      SDPartition, SDPartitionType, SDPartitionAttributes, SDPartitionScheme and friends
  OnDisk/                     internal codecs: CRC32, GUIDCodec, UTF16Label, ProtectiveMBR, GPTHeader, GPTEntry,
                              GPTGeometry, Bytes (little-endian access, typed-throws buffer helpers)
Sources/sdinspect/            read-only CLI: main, Arguments (hand-written parser), Report, HexDump
Sources/CSlopDiskShim/        C shim for disk ioctls: include/CSlopDiskShim.h, shim.c (returns 0 or errno)
Tests/SlopDiskTests/          Swift Testing
  Support/TestSupport.swift   golden bytes, temp directories, Process runner, recording/crashing device wrappers
  ToolCrossCheckTests.swift   (b) gpt(8) / hdiutil cross-checks, skipped without the tools
  SDInspectTests.swift        runs the built sdinspect binary (found next to the test bundle)
  HdiutilAttachTests.swift    (c) opt-in attach + newfs_msdos; attach parsing, hdiutil info lookup, detachAll
  RawDeviceTests.swift        SDRawDevice: RawDeviceTests (no device, always runs),
                              RawDeviceAttachTests (c, RT1–RT7 and more, on attached images)
Prompts/                      agent task documents and their reports (Korean)
```

## Commands

```sh
swift build
swift test
SLOPDISK_TEST_HDIUTIL_ATTACH=1 swift test      # macOS only; attaches temporary images
SLOPDISK_TEST_HDIUTIL_ATTACH=1 swift test --filter RawDevice   # SDRawDevice suites only
swift run sdinspect [--sector-size 512|4096] [--hex] <image>
swift run sdinspect [--hex] /dev/rdiskN        # only on a device you attached yourself with -nomount
```

Useful macOS tools for checking an image by hand (no attach needed):

```sh
gpt -r show <image>                  # type GUIDs; exit code is 0 even for blank images, so parse the output
gpt -r show -l <image>               # labels
hdiutil imageinfo -plist <image>     # partition-scheme, partition-UUID per partition
hdiutil create -size 8m -layout GPTSPUD -type UDIF <name>   # raw GPT fixture (no -fs; it fails in sandboxes)
```

`sgdisk` and `sfdisk` are not installed on the development machine and are not used.

## Conventions

- Swift 6.4 tools, `.enableUpcomingFeature("ApproachableConcurrency")` on every target.
- Public symbols use the `SD` prefix. Internal on-disk codecs are pure functions or value types over byte buffers, so they can be tested without a device.
- Platform branches: `#if canImport(Darwin)` in Swift, `__APPLE__` / `__linux__` in C.
- New files keep the Xcode header comment style used by the original skeleton (`//  FileName.swift`, `//  slopdisk`, `//  Created by ... on M/D/YY.`).
- Comments, commit messages, and user-facing docs are written in a neutral, professional tone.
- Prefer `[UInt8]` / `withUnsafeBytes` over `Data` slicing for offset arithmetic, because `Data` slices keep their parent's indices.

## Testing expectations

- Codecs are checked against **golden bytes** taken from a real `hdiutil` image (see `code#fixture-bytes` in `Prompts/10-implementation.xml`), not just round-trips. Round-trips hide mixed-endian GUID and off-by-one bugs.
- On macOS, images SlopDisk writes are cross-checked with `gpt -r show` and `hdiutil imageinfo -plist`. These tests skip when the tools are missing, as on Linux.
- Always cover 4096-byte sectors, non-ASCII labels (Hangul, emoji: labels are limited to 36 **UTF-16 code units**), and >2 TiB disks (the protective MBR size clamps to `0xFFFFFFFF`). The sparse in-memory backend makes an 8 TiB disk cheap.
- The README SYNOPSIS is duplicated verbatim in `SynopsisTests.swift` (between `// BEGIN SYNOPSIS` and `// END SYNOPSIS`), and `readmeMatchesTest` fails if the two drift apart. Change both together. That file imports SlopDisk without `@testable` so the SYNOPSIS is checked against the public API.
- Compare large in-memory devices through `SDMemoryBlockDevice.chunks` (internal) rather than reading every byte.
- `expectError` takes an untyped closure on purpose: typed-throws inference for closures passed to a generic helper falls back to `any Error` in some contexts.
- Array's `withUnsafeBytes` is `rethrows` and erases `SDError`; inside `throws(SDError)` code use the `withBytes` / `withMutableBytes` helpers in `OnDisk/Bytes.swift`.
- Linux: `docker run --rm -v "$PWD":/w:ro -w /w swift:latest bash -c 'swift build --scratch-path /tmp/build && swift test --scratch-path /tmp/build'`. The read-only mount and separate scratch path keep the macOS `.build` untouched.
- `SDRawDevice` is tested only on macOS, against `hdiutil`-attached images (512-byte sectors). Linux loop devices need root, so on Linux the shim's `BLKSSZGET` / `BLKGETSIZE64` branch is build-tested only; 4Kn devices are not tested anywhere.
- Opt-in attach suites are `.serialized`, open the device only after validating the path, and release every `SDRawDevice` (scope it in a `do { }` block) before detaching. Check `hdiutil info | grep -c image-path` before and after a run: nothing the tests attached may remain.
- Swift may release an object after its last use, so keep a lock holder alive with `withExtendedLifetime` while asserting `.locked`, and scope it in `do { }` so it is gone before the next open.

## Prompts workflow

- `Prompts/NN-*.xml` are `<agent-task>` documents (Korean). Execute them in order; each writes `Prompts/NN-*.report.md` separating "verified" from "not verified". Only report commands that were actually run.
- Do not edit a later stage's task document while executing an earlier one.

## Git

The parent directory (`SnakeStick/`) is the git repository; this package lives at `slopdisk/` inside it. Other sessions work on other directories of the same repository (e.g. `NTFS3G/`) and share the index, so stage and commit only `slopdisk/` paths, and commit only when the user asks.

The file system is case-insensitive but git is not. When a directory is renamed by case only (as `Sources/slopdisk` → `Sources/SlopDisk` was), git keeps the old spelling in the index, which breaks the build on Linux. Check `git ls-files slopdisk` after such a rename and fix it with `git rm -r --cached <old>` followed by `git add <new>`.

## Language

`README.md` and `CLAUDE.md` are in English. `Prompts/` documents and reports are in Korean.
