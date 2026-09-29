//
//  DamageTests.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

import Foundation
import Testing
@testable import SlopDisk

@Suite struct DamageTests {
    /// 64 MiB, 512-byte sectors, with a classic MBR holding one FAT32 LBA (0x0C) partition.
    static func classicMBRDevice() -> SDMemoryBlockDevice {
        let device = SDMemoryBlockDevice(sectorSize: 512, sectorCount: 131072)
        var lba0 = [UInt8](repeating: 0, count: 512)
        for i in 0 ..< 446 {
            lba0[i] = UInt8(truncatingIfNeeded: i &+ 1)  // boot code
        }
        lba0[446] = 0x80
        lba0[446 + 4] = 0x0C
        lba0.storeLE(UInt32(2048), at: 446 + 8)
        lba0.storeLE(UInt32(129_024), at: 446 + 12)
        lba0[510] = 0x55
        lba0[511] = 0xAA
        try! device.writeSectors(lba: 0, lba0)
        return device
    }

    /// A healthy 64 MiB GPT with fixed GUIDs.
    static func healthyDevice(sectorSize: Int = 512) throws -> SDMemoryBlockDevice {
        let device = SDMemoryBlockDevice(sectorSize: sectorSize, sectorCount: (64 << 20) / UInt64(sectorSize))
        let disk = try SDDisk(device: device)
        try disk.withTransaction { txn in
            txn.clear(diskID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!)
            try txn.addPartition(.megabytes(16), type: .efiSystem, label: "EFI",
                                 uniqueID: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!)
            try txn.addPartition(.megabytes(16), type: .microsoftBasicData, label: "DATA",
                                 uniqueID: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!)
            try txn.commit()
        }
        return device
    }

    private func issues(_ scheme: SDPartitionScheme) -> Set<SDGPTIssue>? {
        if case .gpt(.degraded(let issues)) = scheme {
            return issues
        }
        return nil
    }

    // MARK: T6

    @Test(arguments: [false, true])
    func crashAtEveryWriteLeavesAReadableTable(startEmpty: Bool) throws {
        let reference: SDMemoryBlockDevice = startEmpty
            ? SDMemoryBlockDevice(sectorSize: 512, sectorCount: 131072)
            : try Self.healthyDevice()
        let before = try SDDisk(device: reference).partitions

        // Count the writes of an uninterrupted commit.
        let recorder = RecordingDevice(Self.copy(of: reference))
        let expectedAfter = try Self.applyEdit(to: SDDisk(device: recorder))
        let writes = recorder.calls.filter { if case .write = $0 { true } else { false } }.count
        #expect(writes == 5)

        for k in 1 ... writes {
            let inner = Self.copy(of: reference)
            let crashing = CrashingDevice(inner, failAt: k)
            let disk = try SDDisk(device: crashing)
            #expect(throws: SDError.self, "commit must fail at write #\(k)") {
                try Self.applyEdit(to: disk)
            }
            let reopened: SDDisk
            do {
                reopened = try SDDisk(device: inner)
            } catch {
                Issue.record("crash at write #\(k) left the disk unreadable: \(error)")
                continue
            }
            #expect(
                reopened.partitions == before || reopened.partitions == expectedAfter,
                "crash at write #\(k): \(reopened.partitions.map(\.label))"
            )
        }
    }

    private static func applyEdit(to disk: SDDisk) throws -> [SDPartition] {
        try disk.withTransaction { txn in
            txn.clear(diskID: UUID(uuidString: "99999999-2222-3333-4444-555555555555")!)
            try txn.addPartition(.megabytes(8), type: .linuxFilesystem, label: "NEW",
                                 uniqueID: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!)
            let staged = txn.partitions
            try txn.commit()
            return staged
        }
    }

    private static func copy(of device: SDMemoryBlockDevice) -> SDMemoryBlockDevice {
        device.copy()
    }

    // MARK: T7

    @Test func writeOrder() throws {
        let recorder = RecordingDevice(SDMemoryBlockDevice(sectorSize: 512, sectorCount: 131072))
        let disk = try SDDisk(device: recorder)
        try disk.withTransaction { txn in
            txn.clear()
            try txn.addPartition(.megabytes(1), type: .efiSystem)
            try txn.commit()
        }
        let n: UInt64 = 131072
        let mutations = recorder.calls.filter { if case .read = $0 { false } else { true } }
        #expect(mutations == [
            .write(lba: n - 33, sectors: 32),   // backup entries
            .write(lba: n - 1, sectors: 1),     // backup header
            .synchronize,
            .write(lba: 2, sectors: 32),        // primary entries
            .write(lba: 1, sectors: 1),         // primary header
            .write(lba: 0, sectors: 1),         // protective MBR
            .synchronize,
        ])
        // The verification read happens after the final sync.
        let lastSync = try #require(recorder.calls.lastIndex(of: .synchronize))
        #expect(recorder.calls[(lastSync + 1)...].contains(.read(lba: 1, sectors: 1)))
    }

    @Test func writeOrder4Kn() throws {
        let recorder = RecordingDevice(SDMemoryBlockDevice(sectorSize: 4096, sectorCount: 16384))
        let disk = try SDDisk(device: recorder)
        try disk.withTransaction { txn in
            txn.clear()
            try txn.commit()
        }
        let mutations = recorder.calls.filter { if case .read = $0 { false } else { true } }
        #expect(mutations == [
            .write(lba: 16384 - 5, sectors: 4), .write(lba: 16383, sectors: 1), .synchronize,
            .write(lba: 2, sectors: 4), .write(lba: 1, sectors: 1), .write(lba: 0, sectors: 1), .synchronize,
        ])
    }

    // MARK: T11

    @Test func enlargedImageIsRepairedToNewEnd() throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/grow.img"
            let original = try makeT3Image(at: path)
            try truncateFile(path, to: 128 << 20)

            let disk = try SDDiskImage.open(.file(path))
            #expect(disk.sectorCount == 262_144)
            let found = try #require(issues(disk.scheme))
            #expect(found.contains(.backupNotAtEndOfDisk))
            #expect(disk.partitions == original)

            try disk.repair()
            #expect(disk.scheme == .gpt(.healthy))
            let inspection = try SDInspection.read(from: disk.device)
            #expect(inspection.backup?.lba == 262_143)
            #expect(inspection.primary?.alternateLBA == 262_143)
            #expect(inspection.primary?.lastUsableLBA == 262_144 - 34)
            #expect(disk.partitions == original)
        }
    }

    // MARK: T12

    @Test func classicMBRIsRecognizedAndReplaced() throws {
        let device = Self.classicMBRDevice()
        let disk = try SDDisk(device: device)
        #expect(disk.scheme == .mbr([
            SDMBRPartition(index: 0, isBootable: true, type: 0x0C, firstLBA: 2048, sectorCount: 129_024),
        ]))
        #expect(disk.partitions.isEmpty)
        #expect(disk.diskID == nil)

        try disk.withTransaction { txn in
            txn.clear()
            try txn.addPartition(.remaining, type: .microsoftBasicData, label: "DATA")
            try txn.commit()
        }
        #expect(disk.scheme == .gpt(.healthy))
        let lba0 = try device.readSectors(lba: 0, count: 1)
        #expect(lba0[0 ..< 446].allSatisfy { $0 == 0 }, "boot code and disk signature are cleared")
        #expect(lba0[446 + 4] == 0xEE)
    }

    @Test func fatSuperfloppyIsNone() throws {
        let device = SDMemoryBlockDevice(sectorSize: 512, sectorCount: 131072)
        var vbr = [UInt8](repeating: 0, count: 512)
        vbr.replaceSubrange(0 ..< 3, with: [0xEB, 0x58, 0x90])
        for i in 90 ..< 510 {
            vbr[i] = UInt8(truncatingIfNeeded: i &* 13 &+ 5)
        }
        vbr[510] = 0x55
        vbr[511] = 0xAA
        try device.writeSectors(lba: 0, vbr)
        let disk = try SDDisk(device: device)
        #expect(disk.scheme == .none)
    }

    // MARK: Other damage

    @Test func hybridMBRIsReportedAndRemovedByRepair() throws {
        let device = try Self.healthyDevice()
        var lba0 = try device.readSectors(lba: 0, count: 1)
        lba0[462 + 4] = 0x0C
        lba0.storeLE(UInt32(2048), at: 462 + 8)
        lba0.storeLE(UInt32(32768), at: 462 + 12)
        try device.writeSectors(lba: 0, lba0)

        let disk = try SDDisk(device: device)
        #expect(issues(disk.scheme) == [.hybridMBR])
        #expect(try SDInspection.read(from: device).mbr.kind == .hybrid)
        try disk.repair()
        #expect(disk.scheme == .gpt(.healthy))
        #expect(try device.readSectors(lba: 0, count: 1)[462 ..< 478].allSatisfy { $0 == 0 })
    }

    @Test func missingProtectiveMBR() throws {
        let device = try Self.healthyDevice()
        try device.writeSectors(lba: 0, [UInt8](repeating: 0, count: 512))
        let disk = try SDDisk(device: device)
        #expect(issues(disk.scheme) == [.protectiveMBRMissing])
        #expect(disk.partitions.count == 2)
    }

    @Test func primaryEntriesCRCMismatchFallsBackToBackup() throws {
        let device = try Self.healthyDevice()
        let expected = try SDDisk(device: device).partitions
        var entries = try device.readSectors(lba: 2, count: 1)
        entries[56] ^= 0xFF  // first label unit of entry 0
        try device.writeSectors(lba: 2, entries)

        let inspection = try SDInspection.read(from: device)
        #expect(inspection.adoptedCopy == .backup)
        let disk = try SDDisk(device: device)
        #expect(issues(disk.scheme) == [.primaryEntriesCRCMismatch])
        #expect(disk.partitions == expected)
        try disk.repair()
        #expect(disk.scheme == .gpt(.healthy))
    }

    @Test func backupDamage() throws {
        let device = try Self.healthyDevice()
        let n = device.sectorCount
        try device.writeSectors(lba: n - 1, [UInt8](repeating: 0, count: 512))
        #expect(issues(try SDDisk(device: device).scheme) == [.backupHeaderInvalid(.signature)])

        let device2 = try Self.healthyDevice()
        var entries = try device2.readSectors(lba: n - 33, count: 1)
        entries[40] ^= 0x01
        try device2.writeSectors(lba: n - 33, entries)
        #expect(issues(try SDDisk(device: device2).scheme) == [.backupEntriesCRCMismatch])
    }

    @Test func fieldsDamageWithValidCRC() throws {
        let device = try Self.healthyDevice()
        var header = GPTHeader(decoding: try device.readSectors(lba: 1, count: 1))
        header.myLBA = 5  // contradicts where it was read from; CRC is recomputed so only the fields are wrong
        try device.writeSectors(lba: 1, header.encode(sectorSize: 512))
        let disk = try SDDisk(device: device)
        #expect(issues(disk.scheme) == [.primaryHeaderInvalid(.fields)])
        #expect(try SDInspection.read(from: device).primary?.damage == .fields)
    }

    @Test func copiesDifferPrefersPrimary() throws {
        let device = try Self.healthyDevice()
        let geometry = try GPTGeometry(device: device)
        let original = try SDInspection.read(from: device).table!
        var other = original
        other.entries[1] = nil

        // Rewrite only the backup copy with a table lacking slot 1.
        let array = try other.encodeEntryArray(sectorSize: 512)
        var backup = GPTHeader(decoding: try device.readSectors(lba: geometry.backupHeaderLBA, count: 1))
        backup.partitionEntryArrayCRC32 = CRC32.checksum(Array(array[0 ..< 16384]))
        try device.writeSectors(lba: geometry.backupEntriesLBA, array)
        try device.writeSectors(lba: geometry.backupHeaderLBA, backup.encode(sectorSize: 512))

        let disk = try SDDisk(device: device)
        #expect(issues(disk.scheme) == [.copiesDiffer])
        #expect(disk.partitions.count == 2, "the primary copy is adopted")
    }

    @Test func invalidEntriesAreExposedButNotWritten() throws {
        let device = SDMemoryBlockDevice(sectorSize: 512, sectorCount: 131072)
        let geometry = try GPTGeometry(device: device)
        let first = UUID()
        let table = GPTTable(diskID: UUID(), entries: [
            0: try GPTEntry(typeGUID: SDPartitionType.efiSystem.guid, uniqueGUID: first, firstLBA: 2048, lastLBA: 8191, attributes: 0, label: "a"),
            1: try GPTEntry(typeGUID: SDPartitionType.efiSystem.guid, uniqueGUID: UUID(), firstLBA: 4096, lastLBA: 9000, attributes: 0, label: "b"),
        ])
        // Hand-write both copies, bypassing SDDisk's pre-write validation.
        let array = try table.encodeEntryArray(sectorSize: 512)
        let crc = CRC32.checksum(Array(array[0 ..< 16384]))
        let primary = GPTHeader(
            myLBA: 1, alternateLBA: geometry.backupHeaderLBA, firstUsableLBA: 34, lastUsableLBA: geometry.lastUsableLBA,
            diskGUID: table.diskID, partitionEntryLBA: 2, numberOfPartitionEntries: 128, sizeOfPartitionEntry: 128,
            partitionEntryArrayCRC32: crc
        )
        var backup = primary
        backup.myLBA = geometry.backupHeaderLBA
        backup.alternateLBA = 1
        backup.partitionEntryLBA = geometry.backupEntriesLBA
        try device.writeSectors(lba: 0, MBRBlock.protectiveSector(sectorSize: 512, sectorCount: 131072))
        try device.writeSectors(lba: 1, primary.encode(sectorSize: 512))
        try device.writeSectors(lba: 2, array)
        try device.writeSectors(lba: geometry.backupEntriesLBA, array)
        try device.writeSectors(lba: geometry.backupHeaderLBA, backup.encode(sectorSize: 512))

        let disk = try SDDisk(device: device)
        #expect(issues(disk.scheme) == [.invalidEntries])
        #expect(disk.partitions.count == 2)
        let chunks = device.chunks
        expectError(.overlapsExistingPartition(first)) { try disk.repair() }
        #expect(device.chunks == chunks)

        // Removing the offending partition makes the table writable again.
        try disk.withTransaction { txn in
            try txn.removePartition(disk.partitions[1].id)
            try txn.commit()
        }
        #expect(disk.scheme == .gpt(.healthy))
    }

    @Test func nonStandardEntryLayoutIsRead() throws {
        // 64 entries of 256 bytes, as some tools may write.
        let device = SDMemoryBlockDevice(sectorSize: 512, sectorCount: 131072)
        let id = UUID()
        var array = [UInt8](repeating: 0, count: 64 * 256)
        let entry = try GPTEntry(typeGUID: SDPartitionType.linuxFilesystem.guid, uniqueGUID: id, firstLBA: 2048, lastLBA: 4095, attributes: 0, label: "wide")
        entry.encode(into: &array, at: 3 * 256)
        array[3 * 256 + 200] = 0x77  // reserved bytes beyond 128 are part of the CRC
        let header = GPTHeader(
            myLBA: 1, alternateLBA: 131071, firstUsableLBA: 34, lastUsableLBA: 131038, diskGUID: UUID(),
            partitionEntryLBA: 2, numberOfPartitionEntries: 64, sizeOfPartitionEntry: 256,
            partitionEntryArrayCRC32: CRC32.checksum(array)
        )
        var backup = header
        backup.myLBA = 131071
        backup.alternateLBA = 1
        backup.partitionEntryLBA = 131039
        try device.writeSectors(lba: 0, MBRBlock.protectiveSector(sectorSize: 512, sectorCount: 131072))
        try device.writeSectors(lba: 1, header.encode(sectorSize: 512))
        try device.writeSectors(lba: 2, array)
        try device.writeSectors(lba: 131039, array)
        try device.writeSectors(lba: 131071, backup.encode(sectorSize: 512))

        let disk = try SDDisk(device: device)
        #expect(disk.scheme == .gpt(.healthy))
        #expect(disk.partitions.map(\.index) == [3])
        #expect(disk.partitions.first?.label == "wide")

        // Rewriting normalizes to 128 × 128 and keeps the slot.
        try disk.repair()
        let inspection = try SDInspection.read(from: device)
        #expect(inspection.primary?.sizeOfPartitionEntry == 128)
        #expect(inspection.primary?.numberOfPartitionEntries == 128)
        #expect(inspection.partitions.map(\.index) == [3])
    }
}
