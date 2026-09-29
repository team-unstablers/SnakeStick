# NAME

SlopDisk - a lightweight GPT partition table management module for Swift, written by an LLM coding agent

# WARNING: NOT FOR PRODUCTION USE

- **Do not point this at a real disk.** You may end up royally f\*cked. (Seriously.)
- The raw device backend exists only so that disposable media (e.g. a USB stick you are about to wipe) can be written. It does **not** check which disk you hand it. Choosing the right device is entirely your problem.

# STATUS

The API below is **designed but not yet implemented**. Implementation is tracked by the task documents in `Prompts/`:

| Stage | Document | Scope |
|---|---|---|
| 10 | `Prompts/10-implementation.xml` | GPT core, in-memory / file backends, MBR detection, `sdinspect` |
| 20 | `Prompts/20-raw-device.xml` | Raw device backend (`SDRawDevice`) |

# SYNOPSIS

```swift
import Foundation
import SlopDisk

let disk = try SDDiskImage.create(.inMemory, desiredSize: .gigabytes(16))
// let disk = try SDDiskImage.open(.file("/tmp/disk-image.img"))
// try disk.refresh()

if disk.partitions.isEmpty {
    print("== NO PARTITIONS ==")
} else {
    for partition in disk.partitions {
        print("Partition #\(partition.index): \(partition.begin) ~ \(partition.end) (\(partition.size))")
    }
}

try disk.withTransaction { txn in
    txn.clear()

    try txn.addPartition(.megabytes(400), type: .efiSystem, label: "EFI")
    try txn.addPartition(.megabytes(8192), type: .microsoftBasicData, label: "WIN11ISO")
    // writes partition table and sync()
    try txn.commit()
}
```

# DESCRIPTION

SlopDisk reads and writes GUID Partition Tables (GPT): the protective MBR, the primary and backup headers, the partition entry arrays, and their CRC32s. Partition-table logic lives in exactly one place (`SDDisk`). The bytes come from a pluggable block device.

```
SDDiskImage (factory) ──creates──▶ SDDisk (GPT logic) ──reads/writes──▶ any SDBlockDevice
                                                                         ├─ SDMemoryBlockDevice  (sparse, in-memory)
                                                                         ├─ SDFileBlockDevice    (image file)
                                                                         ├─ SDRawDevice          (/dev/rdiskN, stage 20)
                                                                         └─ your own             (e.g. an XPC-backed helper)
```

## Types

| Type | Role |
|---|---|
| `SDBlockDevice` | Public protocol: `sectorSize`, `sectorCount`, `isReadOnly`, sector-aligned `read` / `write`, `synchronize`. Implement it to plug in your own backend. |
| `SDDisk` | GPT engine. `scheme`, `partitions`, `diskID`, `refresh()`, `repair()`, `withTransaction(_:)`. |
| `SDDiskImage` | Factory: `create(_:desiredSize:sectorSize:)`, `open(_:mode:sectorSize:)`. |
| `SDTransaction` | Staged edits. `~Copyable`, passed `inout`, so it cannot escape the closure. |
| `SDPartition` | `index` (entry slot), `type`, `uniqueID`, `begin` / `end` (LBA, **end inclusive**), `size`, `attributes`, `label`. |
| `SDPartitionType` | GUID wrapper with well-known constants (`.efiSystem`, `.microsoftBasicData`, `.microsoftReserved`, `.linuxFilesystem`, `.appleAPFS`, ...). |
| `SDSize` | Byte count. `.kilobytes` / `.megabytes` / `.gigabytes` / `.terabytes` are **binary** (1024-based). Printed as `400 MiB`. |
| `SDError` | The single error type. Library functions use typed throws: `throws(SDError)`. |

## Behavior

- **Sector sizes.** 512 and 4096 are supported. `open` detects the sector size by looking for the `EFI PART` signature.
- **Placement.** Partition starts are aligned to 1 MiB. Sizes are rounded up to whole sectors. New partitions go into the first free region that fits (first-fit), and `.remaining` fills that region to its end.
- **Transactions.** Every edit is validated immediately and throws on the spot. `addPartition` returns the placed partition, so you can inspect `begin` / `end` right away. Nothing touches the disk until `commit()`. If the closure returns or throws without committing, all changes are discarded.
- **Commit.** Writes happen in this order: backup entries → backup header → sync → primary entries → primary header → protective MBR → sync. The table is then **read back from the device** and compared. If the process dies mid-commit, the disk still opens and shows either the old table or the new one.
- **Damage.** If one GPT copy is corrupt, SlopDisk reads the other and reports it via `scheme == .gpt(.degraded(...))`. **Reading never writes.** Call `repair()` or commit a transaction to fix the disk. If both copies are gone, opening throws `.gptUnrecoverable`. Use `SDDisk(device:, ignoringExistingTable: true)` to start over.
- **Non-GPT disks.** `scheme` is `.none` (no table) or `.mbr([...])` (MBR is detected and reported, never edited). A transaction that starts with `clear()` turns either one into a fresh GPT.
- **Reproducibility.** Pass `diskID:` / `uniqueID:` to get byte-identical images.
- **Locking.** Image files are `flock`ed: exclusive for read-write, shared for read-only.
- **Concurrency.** The API is synchronous and `SDDisk` is not `Sendable`. Wrap it in an actor if you need to use it from more than one isolation domain.

# NON-GOALS

- **File systems.** SlopDisk writes partition tables only. To put FAT32 on a partition, attach the image and use the system tools:

  ```sh
  hdiutil attach -nomount -imagekey diskimage-class=CRawDiskImage disk.img
  # /dev/disk23      GUID_partition_scheme
  # /dev/disk23s1    ...
  # /dev/disk23s2    ...
  newfs_msdos -F 32 -v WIN11ISO /dev/rdisk23s2
  hdiutil detach /dev/disk23
  ```

- **MBR editing.** MBR tables are recognized, not edited.
- **Hybrid MBRs.** Committing to a disk with a hybrid MBR replaces it with a pure protective MBR. SlopDisk reports `.hybridMBR` beforehand so this never happens silently.
- **Disk selection / unmounting / privilege escalation** for raw devices. That is the caller's job.

# TOOLS

`sdinspect` is a read-only dump of an image's protective MBR, both GPT headers (with CRC status), and the partition table:

```sh
swift run sdinspect [--sector-size 512|4096] [--hex] <image>
```

Exit codes: `0` healthy / no table / MBR, `1` degraded GPT, `2` unrecoverable GPT, `64` usage error, `74` I/O error.

# REQUIREMENTS

- Swift 6.4 toolchain
- macOS 13+ or Linux
- No third-party dependencies

# TESTING

```sh
swift test                                              # unit + golden-byte tests; macOS also cross-checks with gpt(8) / hdiutil
SLOPDISK_TEST_HDIUTIL_ATTACH=1 swift test               # additionally attaches temporary images via hdiutil (macOS)
```

Tests only ever touch images they create in a temporary directory. Device paths are taken exclusively from `hdiutil attach` output.

# LICENSE

Artistic License 2.0
