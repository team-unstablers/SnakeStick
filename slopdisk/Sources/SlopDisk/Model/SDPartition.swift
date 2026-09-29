//
//  SDPartition.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

import Foundation

/// One used GPT entry.
///
/// `begin` and `end` are LBAs and `end` is **inclusive**, as on disk.
public struct SDPartition: Identifiable, Hashable, Sendable {
    public var id: UUID { uniqueID }

    /// Entry slot, starting at 0. On Linux, slot `n` becomes `/dev/sdX(n+1)`.
    public let index: Int
    public let type: SDPartitionType
    public let uniqueID: UUID
    /// First LBA.
    public let begin: UInt64
    /// Last LBA, inclusive.
    public let end: UInt64
    public let attributes: SDPartitionAttributes
    public let label: String
    public let sectorSize: Int

    init(
        index: Int, type: SDPartitionType, uniqueID: UUID, begin: UInt64, end: UInt64,
        attributes: SDPartitionAttributes, label: String, sectorSize: Int
    ) {
        self.index = index
        self.type = type
        self.uniqueID = uniqueID
        self.begin = begin
        self.end = end
        self.attributes = attributes
        self.label = label
        self.sectorSize = sectorSize
    }

    /// Number of sectors, `end - begin + 1`. Zero for a malformed entry whose `end` precedes `begin`.
    var sectorCount: UInt64 {
        guard end >= begin else {
            return 0
        }
        let (count, overflow) = (end - begin).addingReportingOverflow(1)
        return overflow ? .max : count
    }

    /// `(end - begin + 1) * sectorSize`.
    public var size: SDSize {
        let (bytes, overflow) = sectorCount.multipliedReportingOverflow(by: UInt64(sectorSize))
        return SDSize(bytes: overflow ? .max : bytes)
    }

    /// `begin ... end`. For a malformed entry whose `end` precedes `begin` (reported as `.invalidEntries`),
    /// this is `begin ... begin` so that the property cannot trap.
    public var lbaRange: ClosedRange<UInt64> {
        begin ... max(begin, end)
    }

    /// `begin * sectorSize`.
    public var byteOffset: UInt64 {
        let (offset, overflow) = begin.multipliedReportingOverflow(by: UInt64(sectorSize))
        return overflow ? .max : offset
    }
}
