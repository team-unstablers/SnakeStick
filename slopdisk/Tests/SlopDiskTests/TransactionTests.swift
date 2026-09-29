//
//  TransactionTests.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

import Foundation
import Testing
@testable import SlopDisk

@Suite struct PlacementTests {
    @Test func synopsisLayoutOn16GiB() throws {
        let disk = try SDDiskImage.create(.inMemory, desiredSize: .gigabytes(16))
        try disk.withTransaction { txn in
            txn.clear()
            let efi = try txn.addPartition(.megabytes(400), type: .efiSystem, label: "EFI")
            #expect(efi.begin == 2048)
            #expect(efi.end == 821_247)
            let data = try txn.addPartition(.megabytes(8192), type: .microsoftBasicData, label: "WIN11ISO")
            #expect(data.begin == 821_248)
            #expect(data.end == 17_598_463)
            #expect(data.size.description == "8 GiB")
            #expect(data.index == 1)
        }
    }

    @Test func remainingOn64MiB512() throws {
        let disk = try SDDiskImage.create(.inMemory, desiredSize: .megabytes(64))
        try disk.withTransaction { txn in
            txn.clear()
            try txn.addPartition(.megabytes(16), type: .efiSystem)
            let rest = try txn.addPartition(.remaining, type: .microsoftBasicData)
            #expect(rest.begin == 34816)
            #expect(rest.end == 131_038)
        }
    }

    @Test func remainingOn64MiB4096() throws {
        let disk = try SDDiskImage.create(.inMemory, desiredSize: .megabytes(64), sectorSize: 4096)
        #expect(disk.sectorCount == 16384)
        try disk.withTransaction { txn in
            txn.clear()
            let efi = try txn.addPartition(.megabytes(16), type: .efiSystem)
            #expect(efi.begin == 256)
            #expect(efi.end == 256 + 4096 - 1)
            let rest = try txn.addPartition(.remaining, type: .microsoftBasicData)
            #expect(rest.begin == 4352)
            #expect(rest.end == disk.sectorCount - 1 - 1 - 4)
        }
    }

    @Test func sizesRoundUpToSectors() throws {
        let disk = try SDDiskImage.create(.inMemory, desiredSize: .megabytes(8))
        try disk.withTransaction { txn in
            txn.clear()
            let tiny = try txn.addPartition(.bytes(1), type: .linuxFilesystem)
            #expect(tiny.begin == 2048 && tiny.end == 2048)
            let odd = try txn.addPartition(.bytes(513), type: .linuxFilesystem)
            #expect(odd.begin == 4096 && odd.end == 4097)
            expectError(.invalidArgument("partition size must be at least one sector")) {
                try txn.addPartition(.bytes(0), type: .linuxFilesystem)
            }
        }
    }

    @Test func firstFitReusesGap() throws {
        let disk = try SDDiskImage.create(.inMemory, desiredSize: .megabytes(64))
        try disk.withTransaction { txn in
            txn.clear()
            let a = try txn.addPartition(.megabytes(4), type: .linuxFilesystem, label: "a")
            let b = try txn.addPartition(.megabytes(4), type: .linuxFilesystem, label: "b")
            let c = try txn.addPartition(.megabytes(4), type: .linuxFilesystem, label: "c")
            try txn.removePartition(b.id)
            #expect(txn.partitions.map(\.index) == [0, 2], "slots are not compacted")

            let small = try txn.addPartition(.megabytes(2), type: .linuxFilesystem, label: "d")
            #expect(small.index == 1, "lowest free slot")
            #expect(small.begin == b.begin, "first free region that fits")

            let big = try txn.addPartition(.megabytes(8), type: .linuxFilesystem, label: "e")
            #expect(big.begin == c.end + 1)
            #expect(big.index == 3)
            #expect(a.begin == 2048)
        }
    }

    @Test func remainingSkipsGapsTooSmallToAlign() throws {
        let disk = try SDDiskImage.create(.inMemory, desiredSize: .megabytes(64))
        try disk.withTransaction { txn in
            txn.clear()
            // Leaves LBA 34...99 free; aligned start 2048 is beyond that gap.
            try txn.addPartition(.bytes(512 * 100), type: .biosBoot, at: 100)
            let rest = try txn.addPartition(.remaining, type: .linuxFilesystem)
            #expect(rest.begin == 2048)
            #expect(rest.end == 131_038)
        }
    }

    @Test func explicitStart() throws {
        let disk = try SDDiskImage.create(.inMemory, desiredSize: .megabytes(64))
        try disk.withTransaction { txn in
            txn.clear()
            let unaligned = try txn.addPartition(.bytes(512 * 10), type: .biosBoot, at: 34)
            #expect(unaligned.begin == 34 && unaligned.end == 43)

            expectError(.outOfUsableRange) { try txn.addPartition(.bytes(512), type: .biosBoot, at: 33) }
            expectError(.outOfUsableRange) { try txn.addPartition(.bytes(512), type: .biosBoot, at: 131_039) }
            expectError(.overlapsExistingPartition(unaligned.id)) {
                try txn.addPartition(.bytes(512), type: .biosBoot, at: 40)
            }

            let blocker = try txn.addPartition(.megabytes(1), type: .linuxFilesystem, at: 4096)
            expectError(.insufficientSpace(requested: .megabytes(2))) {
                try txn.addPartition(.megabytes(2), type: .linuxFilesystem, at: 3000)
            }
            let filler = try txn.addPartition(.remaining, type: .linuxFilesystem, at: 3000)
            #expect(filler.begin == 3000 && filler.end == blocker.begin - 1)
        }
    }

    @Test func insufficientSpace() throws {
        let disk = try SDDiskImage.create(.inMemory, desiredSize: .megabytes(8))
        try disk.withTransaction { txn in
            txn.clear()
            expectError(.insufficientSpace(requested: .megabytes(8))) {
                try txn.addPartition(.megabytes(8), type: .linuxFilesystem)
            }
            try txn.addPartition(.remaining, type: .linuxFilesystem)
            expectError(.insufficientSpace(requested: .bytes(512))) {
                try txn.addPartition(.remaining, type: .linuxFilesystem)
            }
            #expect(txn.partitions.count == 1)
        }
    }

    @Test func slot128IsTooMany() throws {
        let disk = try SDDiskImage.create(.inMemory, desiredSize: .megabytes(200))
        try disk.withTransaction { txn in
            txn.clear()
            for _ in 0 ..< 128 {
                try txn.addPartition(.bytes(512), type: .linuxFilesystem)
            }
            expectError(.tooManyPartitions) { try txn.addPartition(.bytes(512), type: .linuxFilesystem) }
            #expect(txn.partitions.last?.index == 127)
            try txn.commit()
        }
        #expect(disk.partitions.count == 128)
        #expect(disk.scheme == .gpt(.healthy))
    }
}

@Suite struct TransactionTests {
    private func blankDisk(_ size: SDSize = .megabytes(64)) throws -> (SDDisk, SDMemoryBlockDevice) {
        let disk = try SDDiskImage.create(.inMemory, desiredSize: size)
        return (disk, disk.device as! SDMemoryBlockDevice)
    }

    @Test func labelLengthIsCountedInUTF16Units() throws {
        let (disk, _) = try blankDisk()
        try disk.withTransaction { txn in
            txn.clear()
            #expect(try txn.addPartition(.megabytes(1), type: .microsoftBasicData, label: "윈도우설치").label == "윈도우설치")
            let emoji18 = String(repeating: "💾", count: 18)
            #expect(try txn.addPartition(.megabytes(1), type: .microsoftBasicData, label: emoji18).label == emoji18)
            expectError(.labelTooLong(utf16Count: 38)) {
                try txn.addPartition(.megabytes(1), type: .microsoftBasicData, label: String(repeating: "💾", count: 19))
            }
            try txn.commit()
        }
        #expect(disk.partitions.map(\.label) == ["윈도우설치", String(repeating: "💾", count: 18)])
    }

    @Test func withoutCommitNothingChanges() throws {
        let device = Golden.fixtureDevice()
        let disk = try SDDisk(device: device)
        let bytes = device.allBytes
        let partitions = disk.partitions
        try disk.withTransaction { txn in
            txn.clear()
            try txn.addPartition(.megabytes(1), type: .efiSystem)
        }
        #expect(device.allBytes == bytes)
        #expect(disk.partitions == partitions)
    }

    @Test func throwingBodyDiscardsAndRethrows() throws {
        struct Abort: Error {}
        let device = Golden.fixtureDevice()
        let disk = try SDDisk(device: device)
        let bytes = device.allBytes
        #expect(throws: Abort.self) {
            try disk.withTransaction { txn in
                txn.clear()
                throw Abort()
            }
        }
        #expect(device.allBytes == bytes)
        #expect(disk.partitions.count == 1)
    }

    @Test func bodyResultIsReturned() throws {
        let (disk, _) = try blankDisk()
        let begin = try disk.withTransaction { txn in
            txn.clear()
            return try txn.addPartition(.megabytes(1), type: .efiSystem).begin
        }
        #expect(begin == 2048)
    }

    @Test func operationsAfterCommitAreFinished() throws {
        let (disk, _) = try blankDisk()
        try disk.withTransaction { txn in
            txn.clear()
            let efi = try txn.addPartition(.megabytes(1), type: .efiSystem)
            try txn.commit()
            expectError(.transactionFinished) { try txn.addPartition(.megabytes(1), type: .efiSystem) }
            expectError(.transactionFinished) { try txn.commit() }
            expectError(.transactionFinished) { try txn.removePartition(efi.id) }
            expectError(.transactionFinished) { try txn.setLabel("x", of: efi.id) }
            expectError(.transactionFinished) { try txn.setType(.linuxFilesystem, of: efi.id) }
            expectError(.transactionFinished) { try txn.setAttributes([], of: efi.id) }
            expectError(.transactionFinished) { try txn.resizePartition(efi.id, to: .remaining) }
            #expect(txn.partitions.count == 1)
        }
    }

    /// `clear()` is non-throwing, so calling it after `commit()` traps instead of throwing `.transactionFinished`.
    @Test func clearAfterCommitTraps() async {
        await #expect(processExitsWith: .failure) {
            let disk = try SDDiskImage.create(.inMemory, desiredSize: .megabytes(8))
            try disk.withTransaction { txn in
                txn.clear()
                try txn.commit()
                txn.clear()
            }
        }
    }

    @Test func nonGPTRequiresClear() throws {
        let (none, _) = try blankDisk()
        #expect(none.scheme == .none)
        try none.withTransaction { txn in
            #expect(txn.partitions.isEmpty)
            expectError(.schemeNotGPT) { try txn.addPartition(.megabytes(1), type: .efiSystem) }
            expectError(.schemeNotGPT) { try txn.removePartition(UUID()) }
            expectError(.schemeNotGPT) { try txn.commit() }
        }

        let mbr = try SDDisk(device: DamageTests.classicMBRDevice())
        guard case .mbr = mbr.scheme else {
            Issue.record("expected MBR, got \(mbr.scheme)")
            return
        }
        try mbr.withTransaction { txn in
            expectError(.schemeNotGPT) { try txn.addPartition(.megabytes(1), type: .efiSystem) }
        }
    }

    @Test func invalidTypeAndDuplicateUniqueID() throws {
        let (disk, _) = try blankDisk()
        try disk.withTransaction { txn in
            txn.clear()
            expectError(.invalidPartitionType) {
                try txn.addPartition(.megabytes(1), type: SDPartitionType(guid: GUIDCodec.zero))
            }
            let id = UUID()
            try txn.addPartition(.megabytes(1), type: .efiSystem, uniqueID: id)
            expectError(.duplicateUniqueID(id)) {
                try txn.addPartition(.megabytes(1), type: .efiSystem, uniqueID: id)
            }
        }
    }

    @Test func editFields() throws {
        let (disk, _) = try blankDisk()
        try disk.withTransaction { txn in
            txn.clear()
            let p = try txn.addPartition(.megabytes(1), type: .microsoftBasicData, label: "old")
            try txn.setLabel("새 이름", of: p.id)
            try txn.setType(.linuxFilesystem, of: p.id)
            try txn.setAttributes([.legacyBIOSBootable, .msHidden, SDPartitionAttributes(rawValue: 1 << 48)], of: p.id)
            expectError(.labelTooLong(utf16Count: 37)) { try txn.setLabel(String(repeating: "x", count: 37), of: p.id) }
            expectError(.invalidPartitionType) { try txn.setType(SDPartitionType(guid: GUIDCodec.zero), of: p.id) }
            let missing = UUID()
            expectError(.partitionNotFound(missing)) { try txn.setLabel("x", of: missing) }
            expectError(.partitionNotFound(missing)) { try txn.removePartition(missing) }
            try txn.commit()
        }
        let p = try #require(disk.partitions.first)
        #expect(p.label == "새 이름")
        #expect(p.type == .linuxFilesystem)
        #expect(p.attributes == [.legacyBIOSBootable, .msHidden, SDPartitionAttributes(rawValue: 1 << 48)])
        #expect(p.attributes.rawValue == (1 << 2) | (1 << 62) | (1 << 48), "unknown bits are preserved")
    }

    @Test func resize() throws {
        let (disk, _) = try blankDisk()
        try disk.withTransaction { txn in
            txn.clear()
            let a = try txn.addPartition(.megabytes(4), type: .linuxFilesystem)
            let b = try txn.addPartition(.megabytes(4), type: .linuxFilesystem)

            let shrunk = try txn.resizePartition(a.id, to: .megabytes(1))
            #expect(shrunk.begin == a.begin && shrunk.end == a.begin + 2047)

            let grown = try txn.resizePartition(a.id, to: .remaining)
            #expect(grown.end == b.begin - 1)

            let unchanged = try txn.resizePartition(a.id, to: .remaining)
            #expect(unchanged.end == grown.end, "no free region after it: size is kept")

            expectError(.overlapsExistingPartition(b.id)) { try txn.resizePartition(a.id, to: .megabytes(5)) }
            expectError(.insufficientSpace(requested: .megabytes(64))) { try txn.resizePartition(b.id, to: .megabytes(64)) }
            expectError(.invalidArgument("partition size must be at least one sector")) {
                try txn.resizePartition(b.id, to: .bytes(0))
            }

            let last = try txn.resizePartition(b.id, to: .remaining)
            #expect(last.end == 131_038)
            #expect(last.begin == b.begin)
            try txn.commit()
        }
        #expect(disk.scheme == .gpt(.healthy))
    }

    @Test func failedCommitLeavesTransactionOpen() throws {
        let inner = SDMemoryBlockDevice(sectorSize: 512, sectorCount: 131072)
        let crashing = CrashingDevice(inner, failAt: 3)
        let disk = try SDDisk(device: crashing)
        try disk.withTransaction { txn in
            txn.clear()
            try txn.addPartition(.megabytes(1), type: .efiSystem)
            #expect(throws: SDError.self) { try txn.commit() }
            #expect(disk.scheme == .none, "state is unchanged after a failed commit")
            try txn.addPartition(.megabytes(1), type: .linuxFilesystem)
        }
    }

    @Test func duplicateUniqueIDsFromDisk() throws {
        let device = SDMemoryBlockDevice(sectorSize: 512, sectorCount: 131072)
        let setup = try SDDisk(device: device)
        let id = UUID()
        let table = GPTTable(diskID: UUID(), entries: [
            0: try GPTEntry(typeGUID: SDPartitionType.efiSystem.guid, uniqueGUID: id, firstLBA: 2048, lastLBA: 4095, attributes: 0, label: "a"),
            1: try GPTEntry(typeGUID: SDPartitionType.efiSystem.guid, uniqueGUID: id, firstLBA: 4096, lastLBA: 6143, attributes: 0, label: "b"),
        ])
        try setup.write(table, geometry: GPTGeometry(device: device))

        let disk = try SDDisk(device: device)
        #expect(disk.partitions.count == 2)
        try disk.withTransaction { txn in
            expectError(.duplicateUniqueID(id)) { try txn.removePartition(id) }
            expectError(.duplicateUniqueID(id)) { try txn.setLabel("c", of: id) }
        }
    }

    @Test func cannotCommitOverlappingEntries() throws {
        let device = SDMemoryBlockDevice(sectorSize: 512, sectorCount: 131072)
        let disk = try SDDisk(device: device)
        let first = UUID()
        let table = GPTTable(diskID: UUID(), entries: [
            0: try GPTEntry(typeGUID: SDPartitionType.efiSystem.guid, uniqueGUID: first, firstLBA: 2048, lastLBA: 8191, attributes: 0, label: ""),
            1: try GPTEntry(typeGUID: SDPartitionType.efiSystem.guid, uniqueGUID: UUID(), firstLBA: 4096, lastLBA: 9000, attributes: 0, label: ""),
        ])
        expectError(.overlapsExistingPartition(first)) { try disk.write(table, geometry: GPTGeometry(device: device)) }
        #expect(device.allocatedByteCount == 0, "validation happens before any write")
    }
}
