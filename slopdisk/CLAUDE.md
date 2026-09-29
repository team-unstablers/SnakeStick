# CLAUDE.md

Guidance for coding agents working in this repository.

## What this is

SlopDisk is a Swift package that reads and writes GPT partition tables. It is the partition-table layer of **SnakeStick**, a macOS tool for making bootable USB sticks; the Xcode workspace lives one directory up (`../SnakeStick.xcworkspace`, which references this directory as `group:slopdisk`, so do not rename the `slopdisk/` directory itself).

Status: API designed, implementation pending. See `README.md` for the public API and `Prompts/` for the implementation task documents.

## Safety rules (non-negotiable)

- **Never open, read-write, or pass to any SlopDisk API a real disk device.** Not `/dev/disk0`, not "the USB stick that's probably disk4", nothing guessed or hard-coded.
- Tests may only operate on image files the test itself created in a unique temporary directory.
- The only permitted device paths are ones parsed from the output of an `hdiutil attach` that the same test just ran on such an image. Validate against `^/dev/r?disk[0-9]+$` and always `defer` a `hdiutil detach`.
- Always attach with `-nomount -imagekey diskimage-class=CRawDiskImage`.
- Tests that call `hdiutil attach` run only when `SLOPDISK_TEST_HDIUTIL_ATTACH=1`.
- `sdinspect` must stay read-only. It opens everything with `.readOnly`; no write path may be reachable from that target.

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

## Layout

Planned layout (to be updated to reality when stage 10 lands):

```
Package.swift            name "SlopDisk", products: SlopDisk (library), sdinspect (executable)
Sources/SlopDisk/        library. OnDisk/ holds internal byte codecs; Devices/ holds SDBlockDevice implementations
Sources/sdinspect/       read-only CLI
Sources/CSlopDiskShim/   (stage 20) C shim for disk ioctls
Tests/SlopDiskTests/     Swift Testing
Prompts/                 agent task documents and their reports (Korean)
```

## Commands

```sh
swift build
swift test
SLOPDISK_TEST_HDIUTIL_ATTACH=1 swift test      # macOS only; attaches temporary images
swift run sdinspect [--sector-size 512|4096] [--hex] <image>
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
- The README SYNOPSIS is duplicated verbatim in a test. Change both together.

## Prompts workflow

- `Prompts/NN-*.xml` are `<agent-task>` documents (Korean). Execute them in order; each writes `Prompts/NN-*.report.md` separating "verified" from "not verified". Only report commands that were actually run.
- Do not edit a later stage's task document while executing an earlier one.

## Git

This directory is not a git repository, and neither is its parent. Do not run `git init` or commit unless the user asks.

## Language

`README.md` and `CLAUDE.md` are in English. `Prompts/` documents and reports are in Korean.
