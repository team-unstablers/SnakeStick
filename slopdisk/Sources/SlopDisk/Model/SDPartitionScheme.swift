//
//  SDPartitionScheme.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

/// What kind of partition table a disk holds.
public enum SDPartitionScheme: Hashable, Sendable {
    /// No GPT evidence and no valid MBR.
    case none
    /// A GPT, possibly read from its backup copy.
    case gpt(SDGPTHealth)
    /// A real (non-protective) MBR. Reported only; SlopDisk never edits MBR tables.
    case mbr([SDMBRPartition])
}

public enum SDGPTHealth: Hashable, Sendable {
    case healthy
    /// The table was readable, but these problems were found. Reading never fixes them;
    /// `SDDisk.repair()` or the next commit does.
    case degraded(Set<SDGPTIssue>)
}

public enum SDGPTIssue: Hashable, Sendable {
    case primaryHeaderInvalid(SDGPTHeaderDamage)
    case primaryEntriesCRCMismatch
    case backupHeaderInvalid(SDGPTHeaderDamage)
    case backupEntriesCRCMismatch
    /// The primary header's AlternateLBA is not the last LBA, typically because the image was enlarged.
    case backupNotAtEndOfDisk
    /// The GPT is valid but LBA 0 holds no 0xEE entry.
    case protectiveMBRMissing
    /// LBA 0 holds MBR entries other than 0xEE. Commit and repair write a pure protective MBR, which removes them.
    case hybridMBR
    /// Both copies are valid but disagree. The primary copy is used.
    case copiesDiffer
    /// The entry array CRC matches, but some entries overlap or lie outside the usable range.
    case invalidEntries
}

public enum SDGPTHeaderDamage: Hashable, Sendable {
    /// No "EFI PART" signature.
    case signature
    /// HeaderSize is out of range or the header CRC does not match.
    case headerCRC
    /// The header is intact but its fields contradict each other or the disk geometry.
    case fields
}

/// One of the four primary entries of a classic MBR.
public struct SDMBRPartition: Hashable, Sendable {
    /// Slot, `0 ..< 4`.
    public let index: Int
    public let isBootable: Bool
    public let type: UInt8
    public let firstLBA: UInt32
    public let sectorCount: UInt32

    init(index: Int, isBootable: Bool, type: UInt8, firstLBA: UInt32, sectorCount: UInt32) {
        self.index = index
        self.isBootable = isBootable
        self.type = type
        self.firstLBA = firstLBA
        self.sectorCount = sectorCount
    }
}
