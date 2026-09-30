# NAME

SlopDisk - a lightweight GPT partition table management module for Swift, written by an LLM coding agent

# WARNING: NOT FOR PRODUCTION USE

- **Do not point this at a real disk.** You may end up royally f\*cked. (Seriously.)
- The raw device backend (`SDRawDevice`) exists only so that disposable media (e.g. a USB stick you are about to wipe) can be written. It does **not** check which disk you hand it: not whether it is your boot disk, not whether it is internal, not whether anything on it is mounted. Choosing the right device, and unmounting it, is entirely your problem.
- Every read-write open of a device has to say `acknowledging: .dataLossRisk`. Grep for it before you ship.

# STATUS

Stages 10 and 20 are implemented. Implementation is tracked by the task documents in `Prompts/`:

| Stage | Document | Scope | State |
|---|---|---|---|
| 10 | `Prompts/10-implementation.xml` | GPT core, in-memory / file backends, MBR detection, `sdinspect` | implemented (`Prompts/10-implementation.report.md`) |
| 20 | `Prompts/20-raw-device.xml` | Raw device backend (`SDRawDevice`), `sdinspect` on devices | implemented (`Prompts/20-raw-device.report.md`) |

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
                                                                         ├─ SDRawDevice          (disk device node, e.g. /dev/rdiskN)
                                                                         └─ your own             (e.g. an XPC-backed helper)
```

## Types

| Type | Role |
|---|---|
| `SDBlockDevice` | Public protocol: `sectorSize`, `sectorCount`, `isReadOnly`, sector-aligned `read` / `write`, `synchronize`. Implement it to plug in your own backend. |
| `SDMemoryBlockDevice` | Sparse in-memory backend (64 KiB chunks, allocated on first write). `allocatedByteCount`, `bytes(atByteOffset:count:)`, `export(toFile:)`. |
| `SDFileBlockDevice` | Image-file backend. `create(path:byteCount:sectorSize:)` makes a sparse file; `init(path:mode:sectorSize:)` opens one. Regular files only. |
| `SDRawDevice` | Disk-device backend (character or block device nodes only). `init(path:acknowledging:)`, `init(readOnlyPath:)`, `init(fileDescriptor:closeOnDeinit:acknowledging:)`. Geometry comes from the device. See [RAW DEVICES](#raw-devices). |
| `SDDisk` | GPT engine. `scheme`, `partitions`, `diskID`, `refresh()`, `repair()`, `withTransaction(_:)`. |
| `SDInspection` | One read-only pass over a device: protective MBR, both headers with their CRCs, the verdict, and the adopted table. Throws only on I/O errors, so it also describes unrecoverable disks. `SDDisk` and `sdinspect` are built on it. |
| `SDDiskImage` | Factory: `create(_:desiredSize:sectorSize:)`, `open(_:mode:sectorSize:)`. |
| `SDTransaction` | Staged edits. `~Copyable`, passed `inout`, so it cannot escape the closure. |
| `SDPartition` | `index` (entry slot), `type`, `uniqueID`, `begin` / `end` (LBA, **end inclusive**), `size`, `attributes`, `label`. |
| `SDPartitionType` | GUID wrapper with well-known constants (`.efiSystem`, `.microsoftBasicData`, `.microsoftReserved`, `.linuxFilesystem`, `.appleAPFS`, ...). |
| `SDSize` | Byte count. `.kilobytes` / `.megabytes` / `.gigabytes` / `.terabytes` are **binary** (1024-based). Printed as `400 MiB`. |
| `SDError` | The single error type. Library functions use typed throws: `throws(SDError)`. |

## Behavior

- **Sector sizes.** 512 and 4096 are supported. `open` detects the sector size by looking for the `EFI PART` signature.
- **Placement.** Partition starts are aligned to 1 MiB. Sizes are rounded up to whole sectors. New partitions go into the first free region that fits (first-fit), and `.remaining` fills that region to its end. With an explicit `at:` start LBA no alignment is applied.
- **Slots.** A new partition takes the lowest free entry slot. Removing a partition leaves its slot empty, so the other partitions keep their numbers (`/dev/sdX1`, ...).
- **Transactions.** Every edit is validated immediately and throws on the spot. `addPartition` returns the placed partition, so you can inspect `begin` / `end` right away. Nothing touches the disk until `commit()`. If the closure returns or throws without committing, all changes are discarded. After a successful `commit()`, every further operation throws `.transactionFinished`, except `clear()`, which cannot throw and traps instead. If `commit()` itself throws, the transaction stays open and the disk's cached state is unchanged; call `refresh()` to see what reached the device.
- **Commit.** Writes happen in this order: backup entries → backup header → sync → primary entries → primary header → protective MBR → sync. The table is then **read back from the device** and compared. If the process dies mid-commit, the disk still opens and shows either the old table or the new one. Tables are always written with 128 entries of 128 bytes; other layouts are accepted when reading.
- **Damage.** If one GPT copy is corrupt, SlopDisk reads the other and reports it via `scheme == .gpt(.degraded(...))`. **Reading never writes.** Call `repair()` or commit a transaction to fix the disk. If both copies are gone, opening throws `.gptUnrecoverable`. Use `SDDisk(device:, ignoringExistingTable: true)` to start over.
- **Non-GPT disks.** `scheme` is `.none` (no table) or `.mbr([...])` (MBR is detected and reported, never edited). A transaction that starts with `clear()` turns either one into a fresh GPT.
- **Reproducibility.** Pass `diskID:` / `uniqueID:` to get byte-identical images.
- **Image files.** `SDFileBlockDevice` (and therefore `SDDiskImage.open(.file(...))`) only opens regular files. A device node such as `/dev/disk4` is rejected with `.invalidArgument`; devices go through `SDRawDevice`, which in turn rejects regular files.
- **Locking.** Image files are `flock`ed: exclusive for read-write, shared for read-only. The lock is per open file description, so a second read-write open in the same process fails with `.locked` too.
- **Concurrency.** The API is synchronous and `SDDisk` is not `Sendable`. Wrap it in an actor if you need to use it from more than one isolation domain.

# RAW DEVICES

`SDRawDevice` writes the table to a disk device node. Everything above applies unchanged; only the backend differs.

```swift
// Read-write. The token is required; there is no read-write open without it.
let device = try SDRawDevice(path: "/dev/rdisk4", acknowledging: .dataLossRisk)
let disk = try SDDisk(device: device)

// Read-only. No token, since nothing can be written.
let probe = try SDRawDevice(readOnlyPath: "/dev/rdisk4")

// A descriptor opened elsewhere, e.g. by a privileged helper.
let borrowed = try SDRawDevice(fileDescriptor: fd, closeOnDeinit: false, acknowledging: .dataLossRisk)
```

**The caller's job, not SlopDisk's:**

- **Choosing the disk.** Nothing checks whether the path is your boot disk, an internal disk, or the USB stick you meant. Use DiskArbitration (macOS) or sysfs (Linux) to decide, and show the user what is about to be wiped.
- **Privileges.** A real disk usually needs root, `authopen`, or a privileged helper. `SDRawDevice` only opens what it is allowed to open; the descriptor initializer is the hook for anything that opens the device on your behalf.
- **Unmounting.** Unmount every volume on the disk first (`diskutil unmountDisk /dev/disk4`) and keep it from being mounted again while you write. Writing to a disk with mounted partitions corrupts those file systems silently. `SDRawDevice` never unmounts anything.

**Details:**

- **Nodes.** Only character and block devices are accepted; a regular file throws `.invalidArgument` (use `SDFileBlockDevice`). On macOS, use `/dev/rdiskN` (raw, unbuffered). `/dev/diskN` goes through the kernel's buffer cache; it is accepted, and its `synchronize()` runs `fsync` first so the cached writes reach the drive before its cache is flushed.
- **Geometry.** The sector size and count are read once, when the device is opened: `DKIOCGETBLOCKSIZE` / `DKIOCGETBLOCKCOUNT` on macOS, `BLKSSZGET` / `BLKGETSIZE64` on Linux. Devices with sectors other than 512 or 4096 bytes throw `.invalidArgument`.
- **I/O.** Raw devices reject transfers whose offset or length is not a whole number of sectors (`EINVAL`). The `SDBlockDevice` contract already guarantees that; in addition, every transfer goes through an internal buffer aligned to the sector and page size, at most 1 MiB at a time.
- **Sync.** `synchronize()` issues `DKIOCSYNCHRONIZECACHE` on macOS and `fsync` on Linux, falling back to `fsync` where the ioctl is not supported. A commit calls it twice (see [Behavior](#behavior)). On a read-only device it does nothing.
- **Locking.** A device opened by path is `flock`ed like an image file (exclusive for read-write, shared for read-only), so two SlopDisk writers cannot collide. The lock only covers the same node: on macOS `/dev/disk4` and `/dev/rdisk4` are separate nodes and do not see each other's lock, and other tools (`dd`, `newfs_msdos`, ...) do not take it at all.
- **Descriptors.** `closeOnDeinit: true` hands the descriptor over: it is locked as above and closed with the device, or right away if the initializer throws (do not close it again). `closeOnDeinit: false` borrows it: it is never locked or closed, even on failure, because `flock` belongs to the open file description and a lock taken here would stay on the caller's descriptor. The access mode of the descriptor (`O_RDONLY` / `O_RDWR`) sets `isReadOnly`; write-only descriptors are rejected.
- **Slices.** On macOS the kernel re-reads the partition table when a device that was open for writing is closed, and publishes the slices (`/dev/rdisk4s1`, ...) shortly after. Release the `SDDisk` / `SDRawDevice` before you look for them. (Verified with `hdiutil`-attached images; see `RawDeviceAttachTests.fat32OnSliceAfterRawWrite`.)

To try this without a real disk, attach a raw image. **Always pass `-nomount`**:

```sh
hdiutil attach -nomount -imagekey diskimage-class=CRawDiskImage disk.img   # prints /dev/diskN
# ... SDRawDevice(path: "/dev/rdiskN", acknowledging: .dataLossRisk) ...
hdiutil detach /dev/diskN   # close every descriptor on the device first
```

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
- **Hybrid MBRs.** Committing to a disk with a hybrid MBR replaces it with a pure protective MBR. SlopDisk reports `.hybridMBR` beforehand so this never happens silently. The same issue is reported when a valid GPT sits behind a classic MBR without a 0xEE record (together with `.protectiveMBRMissing`), because those MBR records are overwritten as well. Boot code in LBA 0 is always cleared.
- **Disk selection / unmounting / privilege escalation** for raw devices. That is the caller's job.

# TOOLS

`sdinspect` is a read-only dump of the protective MBR, both GPT headers (with CRC status), and the partition table of an image file or a disk device:

```sh
swift run sdinspect [--sector-size 512|4096] [--hex] <image>
swift run sdinspect [--hex] /dev/rdiskN
```

Paths under `/dev/` are opened with `SDRawDevice(readOnlyPath:)`, which takes a shared lock and reads the geometry from the device; `--sector-size` is a usage error for them. Nothing is ever opened for writing.

Exit codes: `0` healthy / no table / MBR, `1` degraded GPT, `2` unrecoverable GPT, `64` usage error, `74` I/O error (including a device locked by a SlopDisk writer).

# REQUIREMENTS

- Swift 6.4 toolchain
- macOS 13+ or Linux
- No third-party dependencies

# TESTING

```sh
swift test                                              # unit + golden-byte tests; macOS also cross-checks with gpt(8) / hdiutil
SLOPDISK_TEST_HDIUTIL_ATTACH=1 swift test               # additionally attaches temporary images via hdiutil (macOS)
SLOPDISK_TEST_HDIUTIL_ATTACH=1 swift test --filter RawDevice   # just the SDRawDevice tests
```

Tests only ever touch images they create in a temporary directory. Device paths are taken exclusively from the output of the `hdiutil attach` the same test ran on such an image, and are checked against `^/dev/r?disk[0-9]+(s[0-9]+)?$` before use. `SDRawDevice` on Linux is only build-tested: loop devices need root.

# LICENSE

Artistic License 2.0
