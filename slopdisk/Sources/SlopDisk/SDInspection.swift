//
//  SDInspection.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

import Foundation

/// Everything SlopDisk learns from reading a device's partition table structures.
///
/// Building an inspection never writes to the device and never throws because of on-disk damage;
/// only I/O errors are thrown. Damage is described by `scheme`, `primary`, `backup`, and `mbr`.
/// `SDDisk` and `sdinspect` are both derived from this one reading.
public struct SDInspection: Sendable {
    public let sectorSize: Int
    public let sectorCount: UInt64
    public let mbr: MBRReport
    /// The header at LBA 1, or `nil` if LBA 1 has no "EFI PART" signature.
    public let primary: HeaderReport?
    /// The header at the primary's AlternateLBA (or the last LBA if the primary is unusable),
    /// or `nil` if no "EFI PART" signature was found there.
    public let backup: HeaderReport?
    /// The table verdict. `.failure(.gptUnrecoverable)` if GPT structures exist but neither copy is usable.
    public let scheme: Result<SDPartitionScheme, SDError>
    /// Which GPT copy `diskID` and `partitions` come from.
    public let adoptedCopy: GPTCopy?
    public let diskID: UUID?
    /// Partitions of the adopted copy, in slot order.
    public let partitions: [SDPartition]
    /// LBA 0, LBA 1, and the sector examined for the backup header, as read. Intended for hex dumps.
    public let rawSectors: [RawSector]

    /// The adopted table with raw entry bytes, used by `SDDisk` so that `repair()` rewrites it unchanged.
    let table: GPTTable?

    public enum GPTCopy: Hashable, Sendable {
        case primary
        case backup
    }

    public struct RawSector: Hashable, Sendable {
        public let lba: UInt64
        public let bytes: [UInt8]
    }

    public struct MBRReport: Hashable, Sendable {
        public enum Kind: Hashable, Sendable {
            /// A 0xEE record and nothing else.
            case protective
            /// A 0xEE record plus other records.
            case hybrid
            /// A classic MBR without 0xEE.
            case mbr
            /// No 55 AA signature, no used records, or records that are not plausible.
            case missing
        }

        /// Bytes 510 and 511 are 55 AA.
        public let hasSignature: Bool
        /// All four records as stored, including empty ones.
        public let entries: [SDMBRPartition]
        public let kind: Kind
    }

    public struct HeaderReport: Hashable, Sendable {
        /// Where the header was read from.
        public let lba: UInt64
        /// `nil` if the header is valid.
        public let damage: SDGPTHeaderDamage?
        public let storedHeaderCRC: UInt32
        public let computedHeaderCRC: UInt32
        public let storedEntriesCRC: UInt32
        /// `nil` if the entry array was not read because the header is invalid.
        public let computedEntriesCRC: UInt32?
        public let revision: UInt32
        public let headerSize: UInt32
        public let myLBA: UInt64
        public let alternateLBA: UInt64
        public let firstUsableLBA: UInt64
        public let lastUsableLBA: UInt64
        public let diskGUID: UUID
        public let partitionEntryLBA: UInt64
        public let numberOfPartitionEntries: UInt32
        public let sizeOfPartitionEntry: UInt32

        /// The header is valid and its entry array matches its CRC.
        public var isUsable: Bool {
            damage == nil && computedEntriesCRC == storedEntriesCRC
        }

        /// Sectors covered by the entry array.
        public var entryArraySectorCount: UInt64 {
            let bytes = UInt64(numberOfPartitionEntries) * UInt64(sizeOfPartitionEntry)
            return sectorSize == 0 ? 0 : (bytes + UInt64(sectorSize) - 1) / UInt64(sectorSize)
        }

        let sectorSize: Int
    }

    /// Reads and judges the partition table structures of `device`. Never writes.
    public static func read(from device: any SDBlockDevice) throws(SDError) -> SDInspection {
        let sectorSize = device.sectorSize
        let sectorCount = device.sectorCount
        guard SDBlockRequest.isSupported(sectorSize: sectorSize) else {
            throw .invalidArgument("unsupported sector size \(sectorSize)")
        }
        var rawSectors: [RawSector] = []

        // 1. LBA 0.
        var lba0 = [UInt8](repeating: 0, count: sectorSize)
        if sectorCount > 0 {
            lba0 = try device.readSectors(lba: 0, count: 1)
            rawSectors.append(RawSector(lba: 0, bytes: lba0))
        }
        let mbrBlock = MBRBlock(sector: lba0)

        // 2. Primary header at LBA 1.
        var primary: CopyExamination?
        if sectorCount > 1 {
            primary = try CopyExamination(device: device, lba: 1)
            rawSectors.append(RawSector(lba: 1, bytes: primary!.sector))
        }

        // 3. Backup header: the primary's AlternateLBA if the primary header is valid, otherwise the last LBA.
        var backupLBA: UInt64?
        if let header = primary?.validHeader {
            backupLBA = header.alternateLBA
        } else if sectorCount > 2 {
            backupLBA = sectorCount - 1
        }
        if let lba = backupLBA, lba == 1 || lba >= sectorCount {
            // AlternateLBA points at the primary itself or beyond the device (e.g. a shrunk image).
            backupLBA = nil
        }
        var backup: CopyExamination?
        if let backupLBA {
            backup = try CopyExamination(device: device, lba: backupLBA)
            rawSectors.append(RawSector(lba: backupLBA, bytes: backup!.sector))
        }

        // 4-5. Collect issues and adopt a copy (primary first).
        var issues = Set<SDGPTIssue>()
        if let primary {
            if let damage = primary.damage {
                issues.insert(.primaryHeaderInvalid(damage))
            } else if primary.entries == nil {
                issues.insert(.primaryEntriesCRCMismatch)
            }
            if let header = primary.validHeader, header.alternateLBA != sectorCount - 1 {
                issues.insert(.backupNotAtEndOfDisk)
            }
        } else {
            issues.insert(.primaryHeaderInvalid(.signature))
        }
        if let backup {
            if let damage = backup.damage {
                issues.insert(.backupHeaderInvalid(damage))
            } else if backup.entries == nil {
                issues.insert(.backupEntriesCRCMismatch)
            }
        } else {
            issues.insert(.backupHeaderInvalid(.signature))
        }

        let adoptedCopy: GPTCopy?
        let adopted: CopyExamination?
        if let primary, primary.entries != nil {
            adoptedCopy = .primary
            adopted = primary
            if let backup, backup.entries != nil, !primary.sameTable(as: backup) {
                issues.insert(.copiesDiffer)
            }
        } else if let backup, backup.entries != nil {
            adoptedCopy = .backup
            adopted = backup
        } else {
            adoptedCopy = nil
            adopted = nil
        }

        let mbrKind: MBRReport.Kind
        if mbrBlock.hasProtectiveRecord {
            mbrKind = mbrBlock.hasOtherRecords ? .hybrid : .protective
        } else if mbrBlock.isClassicMBR(diskSectorCount: sectorCount) {
            mbrKind = .mbr
        } else {
            mbrKind = .missing
        }
        let mbrEntries = mbrBlock.records.enumerated().map { index, record in
            SDMBRPartition(
                index: index, isBootable: record.status == 0x80, type: record.type,
                firstLBA: record.firstLBA, sectorCount: record.sectorCount
            )
        }
        let mbr = MBRReport(hasSignature: mbrBlock.hasSignature, entries: mbrEntries, kind: mbrKind)

        // 6-7. Verdict.
        let scheme: Result<SDPartitionScheme, SDError>
        var table: GPTTable?
        if let adopted, let header = adopted.validHeader, let entries = adopted.entries {
            if !mbrBlock.hasProtectiveRecord {
                issues.insert(.protectiveMBRMissing)
            }
            if mbrBlock.hasOtherRecords {
                issues.insert(.hybridMBR)
            }
            if !Self.entriesAreValid(entries, header: header, sectorCount: sectorCount) {
                issues.insert(.invalidEntries)
            }
            scheme = .success(.gpt(issues.isEmpty ? .healthy : .degraded(issues)))
            table = GPTTable(diskID: header.diskGUID, entries: entries)
        } else {
            // "EFI PART" at LBA 1 or at the backup location, or a 0xEE record in LBA 0.
            let gptEvidence = primary?.header != nil || backup?.header != nil || mbrBlock.hasProtectiveRecord
            if gptEvidence {
                scheme = .failure(.gptUnrecoverable)
            } else if mbrKind == .mbr {
                scheme = .success(.mbr(mbrEntries.enumerated().filter { !mbrBlock.records[$0.offset].isEmpty }.map(\.element)))
            } else {
                scheme = .success(.none)
            }
        }

        return SDInspection(
            sectorSize: sectorSize,
            sectorCount: sectorCount,
            mbr: mbr,
            primary: primary?.report(sectorSize: sectorSize),
            backup: backup?.report(sectorSize: sectorSize),
            scheme: scheme,
            adoptedCopy: adoptedCopy,
            diskID: table?.diskID,
            partitions: table?.partitions(sectorSize: sectorSize) ?? [],
            rawSectors: rawSectors,
            table: table
        )
    }

    /// No entry is reversed, outside [FirstUsable, LastUsable], beyond the device, or overlapping another.
    static func entriesAreValid(_ entries: [Int: GPTEntry], header: GPTHeader, sectorCount: UInt64) -> Bool {
        let sorted = entries.values.sorted { $0.firstLBA < $1.firstLBA }
        var previousEnd: UInt64?
        for entry in sorted {
            if entry.firstLBA > entry.lastLBA
                || entry.firstLBA < header.firstUsableLBA
                || entry.lastLBA > header.lastUsableLBA
                || entry.lastLBA >= sectorCount {
                return false
            }
            if let previousEnd, entry.firstLBA <= previousEnd {
                return false
            }
            previousEnd = max(previousEnd ?? 0, entry.lastLBA)
        }
        return true
    }
}

/// The result of examining one GPT copy: a header sector and, if the header is valid, its entry array.
private struct CopyExamination {
    let lba: UInt64
    let sector: [UInt8]
    /// Decoded fields, or `nil` without an "EFI PART" signature.
    let header: GPTHeader?
    let damage: SDGPTHeaderDamage?
    let computedHeaderCRC: UInt32
    let computedEntriesCRC: UInt32?
    /// Used entries, present only when the header is valid and the entry array matches its CRC.
    let entries: [Int: GPTEntry]?

    /// Entry arrays are streamed in chunks of this size so that a header claiming a huge array cannot exhaust memory.
    static let chunkByteCount: UInt64 = 1 << 20

    init(device: any SDBlockDevice, lba: UInt64) throws(SDError) {
        let sectorSize = device.sectorSize
        let sectorCount = device.sectorCount
        self.lba = lba
        sector = try device.readSectors(lba: lba, count: 1)

        guard GPTHeader.hasSignature(sector) else {
            header = nil
            damage = .signature
            computedHeaderCRC = 0
            computedEntriesCRC = nil
            entries = nil
            return
        }
        let header = GPTHeader(decoding: sector)
        self.header = header

        let sizeInRange = header.headerSize >= GPTHeader.standardSize && header.headerSize <= sectorSize
        let crcLength = sizeInRange ? Int(header.headerSize) : GPTHeader.standardSize
        computedHeaderCRC = GPTHeader.computeCRC(of: sector, headerSize: crcLength)
        if !sizeInRange || computedHeaderCRC != header.headerCRC32 {
            damage = .headerCRC
        } else if !header.hasConsistentFields(readAt: lba, sectorSize: sectorSize, sectorCount: sectorCount) {
            damage = .fields
        } else {
            damage = nil
        }
        guard damage == nil else {
            computedEntriesCRC = nil
            entries = nil
            return
        }

        let (crc, used) = try Self.readEntries(device: device, header: header)
        computedEntriesCRC = crc
        entries = crc == header.partitionEntryArrayCRC32 ? used : nil
    }

    var validHeader: GPTHeader? {
        damage == nil ? header : nil
    }

    /// Same disk GUID, used entries, and usable range.
    func sameTable(as other: CopyExamination) -> Bool {
        guard let mine = validHeader, let theirs = other.validHeader else {
            return false
        }
        return mine.diskGUID == theirs.diskGUID
            && mine.firstUsableLBA == theirs.firstUsableLBA
            && mine.lastUsableLBA == theirs.lastUsableLBA
            && entries == other.entries
    }

    func report(sectorSize: Int) -> SDInspection.HeaderReport? {
        guard let header else {
            return nil
        }
        return SDInspection.HeaderReport(
            lba: lba,
            damage: damage,
            storedHeaderCRC: header.headerCRC32,
            computedHeaderCRC: computedHeaderCRC,
            storedEntriesCRC: header.partitionEntryArrayCRC32,
            computedEntriesCRC: computedEntriesCRC,
            revision: header.revision,
            headerSize: header.headerSize,
            myLBA: header.myLBA,
            alternateLBA: header.alternateLBA,
            firstUsableLBA: header.firstUsableLBA,
            lastUsableLBA: header.lastUsableLBA,
            diskGUID: header.diskGUID,
            partitionEntryLBA: header.partitionEntryLBA,
            numberOfPartitionEntries: header.numberOfPartitionEntries,
            sizeOfPartitionEntry: header.sizeOfPartitionEntry,
            sectorSize: sectorSize
        )
    }

    /// Streams the entry array, returning its CRC over Number × Size bytes and the used entries.
    /// Only the first 128 bytes of each slot are decoded; larger entry sizes carry reserved bytes after that.
    private static func readEntries(device: any SDBlockDevice, header: GPTHeader) throws(SDError) -> (UInt32, [Int: GPTEntry]) {
        let sectorSize = UInt64(device.sectorSize)
        let total = header.entryArrayByteCount
        let entrySize = UInt64(header.sizeOfPartitionEntry)
        let chunkBytes = max(sectorSize, chunkByteCount)
        var crc = CRC32()
        var used: [Int: GPTEntry] = [:]
        var offset: UInt64 = 0
        while offset < total {
            let length = min(chunkBytes, total - offset)
            let sectors = (length + sectorSize - 1) / sectorSize
            let chunk = try device.readSectors(lba: header.partitionEntryLBA + offset / sectorSize, count: Int(sectors))
            chunk.withUnsafeBytes { bytes in
                crc.update(UnsafeRawBufferPointer(rebasing: bytes[0 ..< Int(length)]))
            }
            // Slot starts and chunk boundaries are multiples of 128, so each slot's first 128 bytes lie in one chunk.
            var index = (offset + entrySize - 1) / entrySize
            while index * entrySize < offset + length {
                let entry = GPTEntry(decoding: chunk, at: Int(index * entrySize - offset))
                if !entry.isUnused {
                    used[Int(index)] = entry
                }
                index += 1
            }
            offset += length
        }
        return (crc.value, used)
    }
}
