//
//  DiskTests.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

import Foundation
import Testing
@testable import SlopDisk

@Suite struct DiskTests {
    @Test func fixtureOpensHealthy() throws {
        let disk = try SDDisk(device: Golden.fixtureDevice())
        #expect(disk.scheme == .gpt(.healthy))
        #expect(disk.diskID == Golden.diskGUID)
        #expect(disk.partitions.count == 1)
        let partition = try #require(disk.partitions.first)
        #expect(partition.index == 0)
        #expect(partition.begin == 40)
        #expect(partition.end == 16343)
        #expect(partition.label == "disk image")
        #expect(partition.type == .appleHFSPlus)
        #expect(partition.uniqueID == Golden.entryUnique)
        #expect(partition.lbaRange == 40 ... 16343)
        #expect(partition.byteOffset == 40 * 512)
        #expect(partition.size == .bytes(16304 * 512))
        #expect(disk.size == .megabytes(8))
    }

    @Test func damagedPrimaryHeaderIsDegradedAndReadingDoesNotWrite() throws {
        let device = Golden.fixtureDevice()
        var lba1 = try device.readSectors(lba: 1, count: 1)
        lba1[40] &+= 1  // FirstUsableLBA, byte offset 512 + 40
        try device.writeSectors(lba: 1, lba1)
        let before = device.allBytes

        let disk = try SDDisk(device: device)
        guard case .gpt(.degraded(let issues)) = disk.scheme else {
            Issue.record("expected degraded GPT, got \(disk.scheme)")
            return
        }
        #expect(issues.contains(.primaryHeaderInvalid(.headerCRC)))
        #expect(disk.partitions == (try SDDisk(device: Golden.fixtureDevice())).partitions)
        #expect(device.allBytes == before, "reading must not write")

        try disk.repair()
        try disk.refresh()
        #expect(disk.scheme == .gpt(.healthy))
        #expect(disk.diskID == Golden.diskGUID)
        #expect(disk.partitions.first?.label == "disk image")
    }

    @Test func bothHeadersDamagedIsUnrecoverable() throws {
        let device = Golden.fixtureDevice()
        for lba in [1, Golden.sectorCount - 1] {
            var sector = try device.readSectors(lba: lba, count: 1)
            sector[40] &+= 1
            try device.writeSectors(lba: lba, sector)
        }
        expectError(.gptUnrecoverable) { try SDDisk(device: device) }

        let fresh = try SDDisk(device: device, ignoringExistingTable: true)
        #expect(fresh.scheme == .none)
        #expect(fresh.partitions.isEmpty)
        #expect(fresh.diskID == nil)
    }

    @Test func refreshKeepsStateOnFailure() throws {
        let device = Golden.fixtureDevice()
        let disk = try SDDisk(device: device)
        for lba in [1, Golden.sectorCount - 1] {
            try device.writeSectors(lba: lba, [UInt8](repeating: 0xFF, count: 512))
        }
        expectError(.gptUnrecoverable) { try disk.refresh() }
        #expect(disk.scheme == .gpt(.healthy))
        #expect(disk.partitions.count == 1)
    }

    @Test func repairRequiresGPTAndWritableDevice() throws {
        let empty = try SDDisk(device: SDMemoryBlockDevice(sectorSize: 512, sectorCount: 4096))
        expectError(.schemeNotGPT) { try empty.repair() }

        let readOnly = try SDDisk(device: ReadOnlyDevice(Golden.fixtureDevice()))
        #expect(readOnly.scheme == .gpt(.healthy))
        expectError(.readOnly) { try readOnly.repair() }
    }

    @Test func repairIsIdempotent() throws {
        let device = SDMemoryBlockDevice(sectorSize: 512, sectorCount: 131072)
        let disk = try SDDisk(device: device)
        try disk.withTransaction { txn in
            txn.clear(diskID: Golden.diskGUID)
            try txn.addPartition(.megabytes(16), type: .efiSystem, label: "EFI", uniqueID: Golden.entryUnique)
            try txn.commit()
        }
        let committed = device.chunks
        try disk.repair()
        #expect(device.chunks == committed)
        try disk.repair()
        #expect(device.chunks == committed)
    }

    @Test func transactionOnReadOnlyDeviceThrowsBeforeBody() throws {
        let disk = try SDDisk(device: ReadOnlyDevice(Golden.fixtureDevice()))
        var ran = false
        #expect(throws: SDError.readOnly) {
            try disk.withTransaction { _ in ran = true }
        }
        #expect(!ran)
    }

    @Test func reentryIsRejected() throws {
        let disk = try SDDisk(device: Golden.fixtureDevice())
        try disk.withTransaction { txn in
            expectError(.transactionInProgress) { try disk.refresh() }
            expectError(.transactionInProgress) { try disk.repair() }
            #expect(throws: SDError.transactionInProgress) {
                try disk.withTransaction { _ in }
            }
            #expect(txn.partitions.count == 1)
        }
        // The guard is released afterwards.
        try disk.refresh()
        try disk.withTransaction { _ in }
    }

    @Test func tinyDeviceCannotStartTransaction() throws {
        let disk = try SDDisk(device: SDMemoryBlockDevice(sectorSize: 512, sectorCount: 67))
        #expect(disk.scheme == .none)
        #expect(throws: SDError.diskTooSmall(minimum: .bytes(68 * 512))) {
            try disk.withTransaction { txn in txn.clear() }
        }
    }

    @Test func zeroSectorDeviceReadsAsNone() throws {
        let disk = try SDDisk(device: SDMemoryBlockDevice(sectorSize: 512, sectorCount: 0))
        #expect(disk.scheme == .none)
    }
}
