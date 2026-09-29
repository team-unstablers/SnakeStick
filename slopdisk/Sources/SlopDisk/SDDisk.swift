//
//  SDDisk.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

import Foundation

/// The GPT engine. All partition-table logic lives here and in `SDTransaction`.
///
/// The API is synchronous and `SDDisk` is not `Sendable`. To use a disk from more than one isolation domain,
/// wrap it in an actor.
public final class SDDisk {
    public let device: any SDBlockDevice

    public var sectorSize: Int {
        device.sectorSize
    }

    public var sectorCount: UInt64 {
        device.sectorCount
    }

    public var size: SDSize {
        let (bytes, overflow) = sectorCount.multipliedReportingOverflow(by: UInt64(sectorSize))
        return SDSize(bytes: overflow ? .max : bytes)
    }

    public private(set) var scheme: SDPartitionScheme
    /// Used GPT entries in slot order. Empty unless `scheme` is `.gpt`.
    public private(set) var partitions: [SDPartition]
    /// The GPT disk GUID. `nil` unless `scheme` is `.gpt`.
    public private(set) var diskID: UUID?

    /// The adopted table with raw entry bytes, or `nil` if the disk has no GPT.
    private(set) var table: GPTTable?
    private var transactionActive = false

    /// Opens a disk on `device`.
    ///
    /// Reading never writes. If only one GPT copy is intact, the disk opens with `scheme == .gpt(.degraded(...))`.
    /// If both copies are damaged, this throws `.gptUnrecoverable`; pass `ignoringExistingTable: true` to skip reading
    /// and start from `.none`, e.g. to write a fresh table.
    public init(device: any SDBlockDevice, ignoringExistingTable: Bool = false) throws(SDError) {
        self.device = device
        if ignoringExistingTable {
            scheme = .none
            partitions = []
            diskID = nil
            table = nil
        } else {
            let state = try State(inspection: SDInspection.read(from: device))
            scheme = state.scheme
            partitions = state.partitions
            diskID = state.diskID
            table = state.table
        }
    }

    /// Discards the cached state and reads the device again. On failure the previous state is kept.
    public func refresh() throws(SDError) {
        guard !transactionActive else {
            throw .transactionInProgress
        }
        try apply(State(inspection: SDInspection.read(from: device)))
    }

    /// Rewrites the adopted GPT (same disk GUID and entries) using the commit procedure.
    ///
    /// This fixes a damaged or displaced copy, a missing or hybrid protective MBR, and a backup that is not at the
    /// end of an enlarged image. It is idempotent: repairing a healthy disk writes the same bytes again.
    public func repair() throws(SDError) {
        guard !transactionActive else {
            throw .transactionInProgress
        }
        guard case .gpt = scheme, let table else {
            throw .schemeNotGPT
        }
        guard !device.isReadOnly else {
            throw .readOnly
        }
        try write(table, geometry: GPTGeometry(device: device))
    }

    /// Runs `body` with a transaction staged from the current table.
    ///
    /// Nothing is written until `commit()`. If `body` returns or throws without committing, the staged changes are
    /// discarded. Throws `.readOnly` before running `body` on a read-only device.
    public func withTransaction<R>(_ body: (inout SDTransaction) throws -> R) throws -> R {
        guard !transactionActive else {
            throw SDError.transactionInProgress
        }
        guard !device.isReadOnly else {
            throw SDError.readOnly
        }
        let geometry = try GPTGeometry(device: device)
        transactionActive = true
        defer { transactionActive = false }
        var transaction = SDTransaction(disk: self, geometry: geometry, table: table)
        return try body(&transaction)
    }

    // MARK: - Writing

    /// Writes `table` in the crash-safe order, then reads it back from the device and compares.
    ///
    /// Order: backup entries → backup header → sync → primary entries → primary header → protective MBR → sync.
    /// A crash at any point leaves at least one intact copy of either the old or the new table.
    func write(_ table: GPTTable, geometry: GPTGeometry) throws(SDError) {
        try Self.validateForWrite(table, geometry: geometry)

        let sectorSize = geometry.sectorSize
        let entryArray = try table.encodeEntryArray(sectorSize: sectorSize)
        let entriesCRC = CRC32.checksum(Array(entryArray[0 ..< GPTGeometry.entryArrayByteCount]))
        // The two headers differ in MyLBA, AlternateLBA, and PartitionEntryLBA, so each gets its own CRC.
        let backupHeader = GPTHeader(
            myLBA: geometry.backupHeaderLBA,
            alternateLBA: geometry.primaryHeaderLBA,
            firstUsableLBA: geometry.firstUsableLBA,
            lastUsableLBA: geometry.lastUsableLBA,
            diskGUID: table.diskID,
            partitionEntryLBA: geometry.backupEntriesLBA,
            numberOfPartitionEntries: UInt32(GPTGeometry.entryCount),
            sizeOfPartitionEntry: UInt32(GPTGeometry.entrySize),
            partitionEntryArrayCRC32: entriesCRC
        )
        var primaryHeader = backupHeader
        primaryHeader.myLBA = geometry.primaryHeaderLBA
        primaryHeader.alternateLBA = geometry.backupHeaderLBA
        primaryHeader.partitionEntryLBA = geometry.primaryEntriesLBA

        try device.writeSectors(lba: geometry.backupEntriesLBA, entryArray)
        try device.writeSectors(lba: geometry.backupHeaderLBA, backupHeader.encode(sectorSize: sectorSize))
        try device.synchronize()
        try device.writeSectors(lba: geometry.primaryEntriesLBA, entryArray)
        try device.writeSectors(lba: geometry.primaryHeaderLBA, primaryHeader.encode(sectorSize: sectorSize))
        try device.writeSectors(
            lba: 0, MBRBlock.protectiveSector(sectorSize: sectorSize, sectorCount: geometry.sectorCount)
        )
        try device.synchronize()

        // Read back from the device itself, not from anything cached here.
        let inspection = try SDInspection.read(from: device)
        try Self.verify(inspection, matches: table, geometry: geometry)
        apply(try State(inspection: inspection))
    }

    /// Checks that `table` can be written without producing a table that reads back as damaged.
    private static func validateForWrite(_ table: GPTTable, geometry: GPTGeometry) throws(SDError) {
        guard table.entries.keys.allSatisfy({ (0 ..< GPTGeometry.entryCount).contains($0) }) else {
            throw .tooManyPartitions
        }
        let sorted = table.entries.values.sorted { $0.firstLBA < $1.firstLBA }
        var previous: GPTEntry?
        for entry in sorted {
            guard entry.firstLBA <= entry.lastLBA else {
                throw .invalidArgument("partition \(entry.uniqueGUID) ends before it begins")
            }
            guard entry.firstLBA >= geometry.firstUsableLBA, entry.lastLBA <= geometry.lastUsableLBA else {
                throw .outOfUsableRange
            }
            if let previous, entry.firstLBA <= previous.lastLBA {
                throw .overlapsExistingPartition(previous.uniqueGUID)
            }
            if previous == nil || entry.lastLBA > previous!.lastLBA {
                previous = entry
            }
        }
    }

    private static func verify(_ inspection: SDInspection, matches table: GPTTable, geometry: GPTGeometry) throws(SDError) {
        guard case .success(.gpt(.healthy)) = inspection.scheme else {
            throw .verificationFailed("read-back scheme is \(inspection.scheme), expected a healthy GPT")
        }
        guard let written = inspection.table, let primary = inspection.primary else {
            throw .verificationFailed("read-back found no GPT")
        }
        guard written.diskID == table.diskID else {
            throw .verificationFailed("read-back disk GUID \(written.diskID) differs from \(table.diskID)")
        }
        guard written.entries == table.entries else {
            throw .verificationFailed("read-back entries differ from the staged entries")
        }
        guard primary.firstUsableLBA == geometry.firstUsableLBA, primary.lastUsableLBA == geometry.lastUsableLBA else {
            throw .verificationFailed(
                "read-back usable range \(primary.firstUsableLBA)...\(primary.lastUsableLBA) differs from "
                    + "\(geometry.firstUsableLBA)...\(geometry.lastUsableLBA)"
            )
        }
    }

    // MARK: - State

    private struct State {
        var scheme: SDPartitionScheme
        var partitions: [SDPartition]
        var diskID: UUID?
        var table: GPTTable?

        init(inspection: SDInspection) throws(SDError) {
            scheme = try inspection.scheme.get()
            partitions = inspection.partitions
            diskID = inspection.diskID
            table = inspection.table
        }
    }

    private func apply(_ state: State) {
        scheme = state.scheme
        partitions = state.partitions
        diskID = state.diskID
        table = state.table
    }
}

@available(*, unavailable, message: "SDDisk is not thread-safe; wrap it in an actor")
extension SDDisk: Sendable {}
