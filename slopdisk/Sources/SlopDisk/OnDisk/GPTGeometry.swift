//
//  GPTGeometry.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

/// Where SlopDisk puts each GPT structure when it writes a table.
///
/// ```
/// LBA 0                     protective MBR
/// LBA 1                     primary header
/// LBA 2 ..< 2+ES            primary entry array
/// FirstUsable = 2 + ES      (34 for 512-byte sectors, 6 for 4096)
/// LastUsable  = N - 2 - ES
/// LBA N-1-ES ..< N-1        backup entry array
/// LBA N-1                   backup header
/// ```
struct GPTGeometry: Hashable, Sendable {
    /// Entries are always written as 128 × 128 bytes. Reading accepts other layouts.
    static let entryCount = 128
    static let entrySize = 128
    static let entryArrayByteCount = entryCount * entrySize
    static let alignmentBytes = 1 << 20

    let sectorSize: Int
    let sectorCount: UInt64

    /// Throws `.diskTooSmall` if the device cannot hold both copies plus one usable sector.
    init(sectorSize: Int, sectorCount: UInt64) throws(SDError) {
        let minimum = Self.minimumSectorCount(sectorSize: sectorSize)
        guard sectorCount >= minimum else {
            throw .diskTooSmall(minimum: SDSize(bytes: minimum * UInt64(sectorSize)))
        }
        self.sectorSize = sectorSize
        self.sectorCount = sectorCount
    }

    init(device: any SDBlockDevice) throws(SDError) {
        try self.init(sectorSize: device.sectorSize, sectorCount: device.sectorCount)
    }

    /// ES: sectors occupied by one entry array (32 for 512-byte sectors, 4 for 4096).
    static func entryArraySectors(sectorSize: Int) -> UInt64 {
        UInt64((entryArrayByteCount + sectorSize - 1) / sectorSize)
    }

    /// 2·ES + 4 (68 for 512-byte sectors, 12 for 4096).
    static func minimumSectorCount(sectorSize: Int) -> UInt64 {
        2 * entryArraySectors(sectorSize: sectorSize) + 4
    }

    var entryArraySectors: UInt64 {
        Self.entryArraySectors(sectorSize: sectorSize)
    }

    var primaryHeaderLBA: UInt64 { 1 }
    var primaryEntriesLBA: UInt64 { 2 }
    var backupHeaderLBA: UInt64 { sectorCount - 1 }
    var backupEntriesLBA: UInt64 { sectorCount - 1 - entryArraySectors }
    var firstUsableLBA: UInt64 { 2 + entryArraySectors }
    var lastUsableLBA: UInt64 { sectorCount - 2 - entryArraySectors }

    /// Partition start alignment in sectors: 1 MiB (2048 for 512-byte sectors, 256 for 4096).
    var alignment: UInt64 {
        UInt64(max(1, Self.alignmentBytes / sectorSize))
    }
}
