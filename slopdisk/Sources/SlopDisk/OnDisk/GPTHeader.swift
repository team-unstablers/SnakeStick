//
//  GPTHeader.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

import Foundation

/// The GPT header (UEFI 2.x §5.3.2). All integers are little-endian.
///
/// ```
/// off size
/// 0   8   Signature "EFI PART"
/// 8   4   Revision
/// 12  4   HeaderSize
/// 16  4   HeaderCRC32 (computed over HeaderSize bytes with this field zeroed)
/// 20  4   Reserved
/// 24  8   MyLBA
/// 32  8   AlternateLBA
/// 40  8   FirstUsableLBA
/// 48  8   LastUsableLBA
/// 56  16  DiskGUID (mixed-endian)
/// 72  8   PartitionEntryLBA
/// 80  4   NumberOfPartitionEntries
/// 84  4   SizeOfPartitionEntry
/// 88  4   PartitionEntryArrayCRC32 (over Number × Size bytes)
/// ```
struct GPTHeader: Hashable, Sendable {
    static let signature: [UInt8] = Array("EFI PART".utf8)
    static let revision1_0: UInt32 = 0x0001_0000
    static let standardSize = 92
    static let crcOffset = 16

    var revision: UInt32 = revision1_0
    var headerSize: UInt32 = UInt32(standardSize)
    var headerCRC32: UInt32 = 0
    var myLBA: UInt64
    var alternateLBA: UInt64
    var firstUsableLBA: UInt64
    var lastUsableLBA: UInt64
    var diskGUID: UUID
    var partitionEntryLBA: UInt64
    var numberOfPartitionEntries: UInt32
    var sizeOfPartitionEntry: UInt32
    var partitionEntryArrayCRC32: UInt32

    init(
        myLBA: UInt64, alternateLBA: UInt64, firstUsableLBA: UInt64, lastUsableLBA: UInt64, diskGUID: UUID,
        partitionEntryLBA: UInt64, numberOfPartitionEntries: UInt32, sizeOfPartitionEntry: UInt32,
        partitionEntryArrayCRC32: UInt32
    ) {
        self.myLBA = myLBA
        self.alternateLBA = alternateLBA
        self.firstUsableLBA = firstUsableLBA
        self.lastUsableLBA = lastUsableLBA
        self.diskGUID = diskGUID
        self.partitionEntryLBA = partitionEntryLBA
        self.numberOfPartitionEntries = numberOfPartitionEntries
        self.sizeOfPartitionEntry = sizeOfPartitionEntry
        self.partitionEntryArrayCRC32 = partitionEntryArrayCRC32
    }

    /// Decodes the fields of `sector` without validating anything. `sector` must be at least 92 bytes.
    init(decoding sector: [UInt8]) {
        revision = sector.loadLE(UInt32.self, at: 8)
        headerSize = sector.loadLE(UInt32.self, at: 12)
        headerCRC32 = sector.loadLE(UInt32.self, at: 16)
        myLBA = sector.loadLE(UInt64.self, at: 24)
        alternateLBA = sector.loadLE(UInt64.self, at: 32)
        firstUsableLBA = sector.loadLE(UInt64.self, at: 40)
        lastUsableLBA = sector.loadLE(UInt64.self, at: 48)
        diskGUID = GUIDCodec.decode(sector, at: 56)
        partitionEntryLBA = sector.loadLE(UInt64.self, at: 72)
        numberOfPartitionEntries = sector.loadLE(UInt32.self, at: 80)
        sizeOfPartitionEntry = sector.loadLE(UInt32.self, at: 84)
        partitionEntryArrayCRC32 = sector.loadLE(UInt32.self, at: 88)
    }

    static func hasSignature(_ sector: [UInt8]) -> Bool {
        sector.count >= signature.count && Array(sector[0 ..< signature.count]) == signature
    }

    /// CRC32 over the first `headerSize` bytes of `sector` with the CRC field treated as zero.
    static func computeCRC(of sector: [UInt8], headerSize: Int) -> UInt32 {
        var bytes = Array(sector[0 ..< headerSize])
        bytes.storeLE(UInt32(0), at: crcOffset)
        return CRC32.checksum(bytes)
    }

    /// Encodes a full sector, computing HeaderCRC32. Bytes after the header are zero.
    func encode(sectorSize: Int) -> [UInt8] {
        var sector = [UInt8](repeating: 0, count: sectorSize)
        sector.replaceSubrange(0 ..< Self.signature.count, with: Self.signature)
        sector.storeLE(revision, at: 8)
        sector.storeLE(headerSize, at: 12)
        sector.storeLE(myLBA, at: 24)
        sector.storeLE(alternateLBA, at: 32)
        sector.storeLE(firstUsableLBA, at: 40)
        sector.storeLE(lastUsableLBA, at: 48)
        GUIDCodec.encode(diskGUID, into: &sector, at: 56)
        sector.storeLE(partitionEntryLBA, at: 72)
        sector.storeLE(numberOfPartitionEntries, at: 80)
        sector.storeLE(sizeOfPartitionEntry, at: 84)
        sector.storeLE(partitionEntryArrayCRC32, at: 88)
        sector.storeLE(Self.computeCRC(of: sector, headerSize: Int(headerSize)), at: Self.crcOffset)
        return sector
    }

    /// Number × Size.
    var entryArrayByteCount: UInt64 {
        UInt64(numberOfPartitionEntries) * UInt64(sizeOfPartitionEntry)
    }

    func entryArraySectors(sectorSize: Int) -> UInt64 {
        let size = UInt64(sectorSize)
        return (entryArrayByteCount + size - 1) / size
    }

    /// `true` if SizeOfPartitionEntry is 128 × 2^n.
    var hasValidEntrySize: Bool {
        let size = sizeOfPartitionEntry
        return size >= 128 && size % 128 == 0 && (size / 128).nonzeroBitCount == 1
    }

    /// Checks the fields of a header whose signature and CRC are already known to be good.
    /// Returns `false` for any contradiction with where it was read from or with the disk geometry.
    func hasConsistentFields(readAt lba: UInt64, sectorSize: Int, sectorCount: UInt64) -> Bool {
        guard myLBA == lba else {
            return false
        }
        // FirstUsable may exceed LastUsable by one (an empty usable range), but not more.
        if firstUsableLBA > lastUsableLBA && firstUsableLBA - lastUsableLBA > 1 {
            return false
        }
        guard hasValidEntrySize else {
            return false
        }
        let entrySectors = entryArraySectors(sectorSize: sectorSize)
        guard partitionEntryLBA <= sectorCount, entrySectors <= sectorCount - partitionEntryLBA else {
            return false
        }
        let entryRange: ClosedRange<UInt64>? =
            entrySectors == 0 ? nil : partitionEntryLBA ... partitionEntryLBA + entrySectors - 1
        if let entryRange, entryRange.contains(myLBA) {
            return false
        }
        if firstUsableLBA <= lastUsableLBA {
            let usable = firstUsableLBA ... lastUsableLBA
            if let entryRange, usable.overlaps(entryRange) {
                return false
            }
            // The usable range must not cover LBA 0 (MBR) or either header.
            if usable.contains(0) || usable.contains(myLBA) || usable.contains(alternateLBA) {
                return false
            }
        }
        return true
    }
}
