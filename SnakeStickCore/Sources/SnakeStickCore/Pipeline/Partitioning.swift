// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SlopDisk

/// The table written in step 3 (`code#layout`).
struct PartitionTable {
    let ntfs: SDPartition
    let fat: SDPartition
    let sectorSize: Int
    let sectorCount: UInt64
}

enum Partitioning {
    /// The UEFI:NTFS partition: 1 MiB, at the very end of the disk (decision 23).
    static let fatBytes: UInt64 = 1 << 20
    static let fatPartitionName = "UEFI:NTFS"

    /// The smallest device that can hold the layout: 2 MiB plus both GPT copies (C10). The
    /// pipeline checks the far larger ``ISOInfo/requiredBytes`` before it gets here.
    static func minimumBytes(sectorSize: Int) -> UInt64 {
        2 * fatBytes + UInt64(34 + 33) * UInt64(sectorSize)
    }

    /// Writes a fresh GPT to the whole disk at `devicePath` (`/dev/rdiskN`): partition 1 is
    /// Microsoft Basic Data named `label` and takes everything up to partition 2, the 1 MiB
    /// EFI System Partition named `UEFI:NTFS` that ends at the last usable LBA.
    ///
    /// The device is opened and released inside this function: the kernel publishes the new
    /// slices only after the writer closes the device (F8).
    ///
    /// This is the only read-write open of a device in SnakeStickCore.
    static func writePartitionTable(devicePath: String, label: String, willCommit: () -> Void = {}) throws -> PartitionTable {
        let device = try SDRawDevice(path: devicePath, acknowledging: .dataLossRisk)
        let sectorSize = device.sectorSize
        let sectorCount = device.sectorCount
        let totalBytes = UInt64(sectorSize) * sectorCount
        guard totalBytes >= minimumBytes(sectorSize: sectorSize) else {
            throw InstallerError(
                phase: .writePartitionTable, kind: .insufficientSpace,
                message: "\(devicePath) holds \(totalBytes) bytes; at least \(minimumBytes(sectorSize: sectorSize)) are needed.",
                path: devicePath
            )
        }
        let disk = try SDDisk(device: device, ignoringExistingTable: true)
        let fatSectors = fatBytes / UInt64(sectorSize)
        let (ntfs, fat) = try disk.withTransaction { txn in
            txn.clear()
            // Place the NTFS partition first to learn LastUsableLBA (F6), then shrink it and put
            // the FAT partition in the last 1 MiB, right before the backup GPT (decisions 2, 23).
            // The FAT start is therefore not 1 MiB aligned, and the NTFS partition, which does
            // start aligned, is not a whole number of MiB. The user chose this on 2026-09-30 over
            // an aligned FAT start that leaves up to 1 MiB unused at the end.
            var ntfs = try txn.addPartition(.remaining, type: .microsoftBasicData, label: VolumeLabel.partitionName(for: label))
            let fatBegin = ntfs.end + 1 - fatSectors
            guard fatBegin > ntfs.begin else {
                throw InstallerError(
                    phase: .writePartitionTable, kind: .insufficientSpace,
                    message: "\(devicePath) is too small for the partition layout.", path: devicePath
                )
            }
            ntfs = try txn.resizePartition(ntfs.id, to: .size(.bytes((fatBegin - ntfs.begin) * UInt64(sectorSize))))
            let fat = try txn.addPartition(
                .size(.bytes(fatSectors * UInt64(sectorSize))), type: .efiSystem, label: fatPartitionName, at: fatBegin
            )
            willCommit()
            try txn.commit()
            return (ntfs, fat)
        }
        return PartitionTable(ntfs: ntfs, fat: fat, sectorSize: sectorSize, sectorCount: sectorCount)
    }

    /// Checks that `slice` is the partition SlopDisk wrote (C17, P11): its IOMedia sits on
    /// `target`, starts at the partition's byte offset, has its size and the target's block size.
    /// Waits up to 10 seconds for the kernel to publish it.
    static func checkSlice(
        _ slice: PartitionSlice, of target: TargetDevice, expected partition: SDPartition, cancellation: CancellationFlag
    ) throws {
        guard slice.hasSlicePaths else {
            throw InstallerError(phase: .checkPartitions, kind: .other, message: "\(slice.bsdName) is not a partition slice name.")
        }
        var media: IORegistry.Media?
        let deadline = Date().addingTimeInterval(10)
        while true {
            try cancellation.check()
            media = IORegistry.media(bsdName: slice.bsdName)
            if media != nil, FileManager.default.fileExists(atPath: slice.raw), FileManager.default.fileExists(atPath: slice.buffered) {
                break
            }
            guard Date() < deadline else {
                throw InstallerError(
                    phase: .checkPartitions, kind: .other,
                    message: "\(slice.buffered) did not appear within 10 seconds after the partition table was written.",
                    targetModified: true, path: slice.buffered
                )
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        guard let media else {
            return
        }
        var mismatches: [String] = []
        if media.wholeDisk != target.wholeBSD {
            mismatches.append("parent \(media.wholeDisk ?? "none"), expected \(target.wholeBSD)")
        }
        if media.isWhole {
            mismatches.append("it is a whole disk")
        }
        if media.base != partition.byteOffset {
            mismatches.append("offset \(media.base), expected \(partition.byteOffset)")
        }
        if media.size != partition.size.bytes {
            mismatches.append("size \(media.size), expected \(partition.size.bytes)")
        }
        if media.preferredBlockSize != UInt64(partition.sectorSize) {
            mismatches.append("block size \(media.preferredBlockSize), expected \(partition.sectorSize)")
        }
        guard mismatches.isEmpty else {
            throw InstallerError(
                phase: .checkPartitions, kind: .other,
                message: "\(slice.buffered) does not match the partition table: \(mismatches.joined(separator: "; ")).",
                targetModified: true, path: slice.buffered
            )
        }
    }
}
