//
//  ProtectiveMBR.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

/// One 16-byte MBR partition record.
struct MBRRecord: Hashable, Sendable {
    static let byteCount = 16

    let status: UInt8
    let type: UInt8
    let firstLBA: UInt32
    let sectorCount: UInt32
    /// All 16 bytes are zero.
    let isEmpty: Bool

    init(_ bytes: [UInt8], at offset: Int) {
        status = bytes[offset]
        type = bytes[offset + 4]
        firstLBA = bytes.loadLE(UInt32.self, at: offset + 8)
        sectorCount = bytes.loadLE(UInt32.self, at: offset + 12)
        isEmpty = bytes.isZero(offset ..< offset + Self.byteCount)
    }

    /// The plausibility test that separates a real MBR from, for example, a FAT boot sector (which also ends in 55 AA).
    func isPlausible(diskSectorCount: UInt64) -> Bool {
        (status == 0x00 || status == 0x80)
            && type != 0
            && firstLBA >= 1
            && UInt64(firstLBA) + UInt64(sectorCount) <= diskSectorCount
    }
}

/// The first 512 bytes of LBA 0.
struct MBRBlock: Hashable, Sendable {
    static let byteCount = 512
    static let recordsOffset = 446
    static let recordCount = 4
    static let signatureOffset = 510
    static let protectiveType: UInt8 = 0xEE

    let hasSignature: Bool
    let records: [MBRRecord]

    init(sector: [UInt8]) {
        hasSignature = sector[Self.signatureOffset] == 0x55 && sector[Self.signatureOffset + 1] == 0xAA
        records = (0 ..< Self.recordCount).map { index in
            MBRRecord(sector, at: Self.recordsOffset + index * MBRRecord.byteCount)
        }
    }

    /// A 0xEE record is present. Only the type byte is examined; Apple writes a start CHS of FE FF FF,
    /// the UEFI specification 00 02 00, and both are accepted.
    var hasProtectiveRecord: Bool {
        hasSignature && records.contains { $0.type == Self.protectiveType }
    }

    /// Records other than 0xEE are present.
    var hasOtherRecords: Bool {
        hasSignature && records.contains { !$0.isEmpty && $0.type != Self.protectiveType }
    }

    /// A classic MBR: signature, at least one used record, and every used record plausible.
    func isClassicMBR(diskSectorCount: UInt64) -> Bool {
        let used = records.filter { !$0.isEmpty }
        return hasSignature && !used.isEmpty && used.allSatisfy { $0.isPlausible(diskSectorCount: diskSectorCount) }
    }

    /// Builds a full LBA 0 sector holding a pure protective MBR.
    ///
    /// Bytes 0 ..< 446 (boot code and disk signature) are zeroed on purpose: a leftover FAT BPB there makes
    /// some systems treat the disk as a FAT superfloppy instead of GPT. For 4096-byte sectors the MBR occupies
    /// the first 512 bytes and the rest of the sector is zero.
    static func protectiveSector(sectorSize: Int, sectorCount: UInt64) -> [UInt8] {
        var sector = [UInt8](repeating: 0, count: sectorSize)
        let record = recordsOffset
        sector[record + 0] = 0x00                              // status
        sector[record + 1] = 0x00                              // start CHS
        sector[record + 2] = 0x02
        sector[record + 3] = 0x00
        sector[record + 4] = protectiveType
        sector[record + 5] = 0xFF                              // end CHS
        sector[record + 6] = 0xFF
        sector[record + 7] = 0xFF
        sector.storeLE(UInt32(1), at: record + 8)              // starting LBA
        let size = min(sectorCount - 1, UInt64(UInt32.max))    // clamps above 2 TiB with 512-byte sectors
        sector.storeLE(UInt32(size), at: record + 12)
        sector[signatureOffset] = 0x55
        sector[signatureOffset + 1] = 0xAA
        return sector
    }
}
