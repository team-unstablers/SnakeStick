//
//  SDTransaction.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

import Foundation

/// Staged edits to a disk's GPT, handed out by `SDDisk.withTransaction(_:)`.
///
/// `SDTransaction` is `~Copyable` and passed `inout`, so it cannot escape the closure or be duplicated.
/// Every operation validates immediately and throws on the spot. Nothing is written until `commit()`;
/// once `commit()` succeeds, every further operation throws `.transactionFinished`.
///
/// Placement: starts are aligned to 1 MiB, sizes are rounded up to whole sectors, and a new partition goes into
/// the first free region that fits (first-fit). New partitions take the lowest free slot; removing a partition
/// leaves its slot empty, so the slots of other partitions never move.
public struct SDTransaction: ~Copyable {
    private let disk: SDDisk
    private let geometry: GPTGeometry
    /// `nil` while the disk has no GPT and `clear()` has not been called.
    private var table: GPTTable?
    private var finished = false

    init(disk: SDDisk, geometry: GPTGeometry, table: GPTTable?) {
        self.disk = disk
        self.geometry = geometry
        self.table = table
    }

    /// The staged partitions in slot order.
    public var partitions: [SDPartition] {
        table?.partitions(sectorSize: geometry.sectorSize) ?? []
    }

    /// Replaces the staged table with an empty GPT. `diskID` defaults to a random GUID.
    ///
    /// This is the only way to start editing a disk whose scheme is `.none` or `.mbr`.
    /// Calling it after `commit()` is a programming error and traps: `clear()` cannot throw
    /// `.transactionFinished` because it is non-throwing by design.
    public mutating func clear(diskID: UUID? = nil) {
        precondition(!finished, "SDTransaction.clear() called after commit()")
        table = GPTTable(diskID: diskID ?? UUID(), entries: [:])
    }

    /// Adds a partition and returns it with its placement decided.
    ///
    /// Without `startLBA`, the partition goes into the first free region that can hold it at a 1 MiB-aligned start;
    /// `.remaining` takes that region up to its end. With `startLBA`, no alignment is applied and the partition must
    /// fit into the free region containing `startLBA`.
    @discardableResult
    public mutating func addPartition(
        _ extent: SDPartitionExtent,
        type: SDPartitionType,
        label: String = "",
        attributes: SDPartitionAttributes = [],
        at startLBA: UInt64? = nil,
        uniqueID: UUID? = nil
    ) throws(SDError) -> SDPartition {
        let current = try editableTable()
        guard !type.isUnused else {
            throw .invalidPartitionType
        }
        try UTF16Label.validate(label)
        if let uniqueID, current.entries.values.contains(where: { $0.uniqueGUID == uniqueID }) {
            throw .duplicateUniqueID(uniqueID)
        }
        guard let slot = (0 ..< GPTGeometry.entryCount).first(where: { current.entries[$0] == nil }) else {
            throw .tooManyPartitions
        }
        let range = try place(extent, at: startLBA, in: current)
        let entry = try GPTEntry(
            typeGUID: type.guid,
            uniqueGUID: uniqueID ?? Self.freshUniqueID(in: current),
            firstLBA: range.lowerBound,
            lastLBA: range.upperBound,
            attributes: attributes.rawValue,
            label: label
        )
        table!.entries[slot] = entry
        return entry.partition(index: slot, sectorSize: geometry.sectorSize)
    }

    /// Empties the partition's slot. Other slots are not renumbered.
    public mutating func removePartition(_ id: SDPartition.ID) throws(SDError) {
        let current = try editableTable()
        let slot = try Self.slot(of: id, in: current)
        table!.entries[slot] = nil
    }

    public mutating func setLabel(_ label: String, of id: SDPartition.ID) throws(SDError) {
        let current = try editableTable()
        try UTF16Label.validate(label)
        let slot = try Self.slot(of: id, in: current)
        try table!.entries[slot]!.setLabel(label)
    }

    public mutating func setType(_ type: SDPartitionType, of id: SDPartition.ID) throws(SDError) {
        let current = try editableTable()
        guard !type.isUnused else {
            throw .invalidPartitionType
        }
        let slot = try Self.slot(of: id, in: current)
        table!.entries[slot]!.typeGUID = type.guid
    }

    public mutating func setAttributes(_ attributes: SDPartitionAttributes, of id: SDPartition.ID) throws(SDError) {
        let current = try editableTable()
        let slot = try Self.slot(of: id, in: current)
        table!.entries[slot]!.attributes = attributes.rawValue
    }

    /// Moves the partition's end LBA; `begin` never changes. File systems inside are not touched.
    ///
    /// `.remaining` grows the partition to the end of the free region right after it. If there is none,
    /// the size is kept and the call succeeds.
    @discardableResult
    public mutating func resizePartition(_ id: SDPartition.ID, to extent: SDPartitionExtent) throws(SDError) -> SDPartition {
        let current = try editableTable()
        let slot = try Self.slot(of: id, in: current)
        let entry = current.entries[slot]!
        let begin = entry.firstLBA
        let next = current.entries
            .filter { $0.key != slot && $0.value.firstLBA > begin }
            .min { $0.value.firstLBA < $1.value.firstLBA }?
            .value

        let newEnd: UInt64
        switch extent {
        case .size(let size):
            let sectors = try sectorCount(for: size)
            let (end, overflow) = begin.addingReportingOverflow(sectors - 1)
            if let next, overflow || end >= next.firstLBA {
                throw .overlapsExistingPartition(next.uniqueGUID)
            }
            guard !overflow, end <= geometry.lastUsableLBA else {
                throw .insufficientSpace(requested: size)
            }
            newEnd = end
        case .remaining:
            let limit = min(next.map { $0.firstLBA - 1 } ?? geometry.lastUsableLBA, geometry.lastUsableLBA)
            newEnd = max(entry.lastLBA, limit)
        }
        table!.entries[slot]!.lastLBA = newEnd
        return table!.entries[slot]!.partition(index: slot, sectorSize: geometry.sectorSize)
    }

    /// Writes the staged table (see `SDDisk` for the write order) and reads it back to verify it.
    ///
    /// If `commit()` throws, the transaction stays open and the disk's cached state is unchanged;
    /// call `SDDisk.refresh()` after the closure to see what reached the device.
    public mutating func commit() throws(SDError) {
        let current = try editableTable()
        try disk.write(current, geometry: geometry)
        finished = true
    }

    // MARK: - Helpers

    private func editableTable() throws(SDError) -> GPTTable {
        guard !finished else {
            throw .transactionFinished
        }
        guard let table else {
            throw .schemeNotGPT
        }
        return table
    }

    /// `size` rounded up to whole sectors. Throws `.invalidArgument` for zero.
    private func sectorCount(for size: SDSize) throws(SDError) -> UInt64 {
        let sectorSize = UInt64(geometry.sectorSize)
        let sectors = size.bytes / sectorSize + (size.bytes % sectorSize == 0 ? 0 : 1)
        guard sectors > 0 else {
            throw .invalidArgument("partition size must be at least one sector")
        }
        return sectors
    }

    /// Unused LBA ranges within [FirstUsable, LastUsable], in ascending order.
    private func freeRegions(in table: GPTTable) -> [ClosedRange<UInt64>] {
        let first = geometry.firstUsableLBA
        let last = geometry.lastUsableLBA
        var regions: [ClosedRange<UInt64>] = []
        var cursor = first
        for entry in table.entries.values.sorted(by: { $0.firstLBA < $1.firstLBA }) {
            if cursor > last {
                break
            }
            let begin = entry.firstLBA
            let end = max(entry.firstLBA, entry.lastLBA)
            if end < cursor {
                continue
            }
            if begin > cursor {
                let regionEnd = min(begin - 1, last)
                regions.append(cursor ... regionEnd)
            }
            guard end < .max else {
                cursor = .max
                break
            }
            cursor = max(cursor, end + 1)
        }
        if cursor <= last {
            regions.append(cursor ... last)
        }
        return regions
    }

    private func place(_ extent: SDPartitionExtent, at startLBA: UInt64?, in table: GPTTable) throws(SDError) -> ClosedRange<UInt64> {
        let requested: SDSize
        let sectors: UInt64?
        switch extent {
        case .size(let size):
            requested = size
            sectors = try sectorCount(for: size)
        case .remaining:
            requested = SDSize(bytes: UInt64(geometry.sectorSize))
            sectors = nil
        }
        let regions = freeRegions(in: table)

        if let start = startLBA {
            guard start >= geometry.firstUsableLBA, start <= geometry.lastUsableLBA else {
                throw .outOfUsableRange
            }
            guard let region = regions.first(where: { $0.contains(start) }) else {
                let owner = table.entries.values.first { $0.firstLBA <= start && start <= max($0.firstLBA, $0.lastLBA) }
                guard let owner else {
                    throw .outOfUsableRange
                }
                throw .overlapsExistingPartition(owner.uniqueGUID)
            }
            guard let sectors else {
                return start ... region.upperBound
            }
            let (end, overflow) = start.addingReportingOverflow(sectors - 1)
            guard !overflow, end <= region.upperBound else {
                throw .insufficientSpace(requested: requested)
            }
            return start ... end
        }

        let alignment = geometry.alignment
        for region in regions {
            let remainder = region.lowerBound % alignment
            let (aligned, overflow) = region.lowerBound.addingReportingOverflow(remainder == 0 ? 0 : alignment - remainder)
            guard !overflow, aligned <= region.upperBound else {
                continue
            }
            guard let sectors else {
                return aligned ... region.upperBound
            }
            if sectors <= region.upperBound - aligned + 1 {
                return aligned ... aligned + sectors - 1
            }
        }
        throw .insufficientSpace(requested: requested)
    }

    private static func slot(of id: SDPartition.ID, in table: GPTTable) throws(SDError) -> Int {
        let slots = table.entries.filter { $0.value.uniqueGUID == id }.map(\.key)
        guard let slot = slots.first else {
            throw .partitionNotFound(id)
        }
        guard slots.count == 1 else {
            throw .duplicateUniqueID(id)
        }
        return slot
    }

    private static func freshUniqueID(in table: GPTTable) -> UUID {
        while true {
            let candidate = UUID()
            if !table.entries.values.contains(where: { $0.uniqueGUID == candidate }) {
                return candidate
            }
        }
    }
}
