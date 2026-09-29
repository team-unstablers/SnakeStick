//
//  ImageTests.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

import Foundation
import Testing
@testable import SlopDisk

@Suite struct DiskImageTests {
    @Test func createRoundsUpToSectors() throws {
        let disk = try SDDiskImage.create(.inMemory, desiredSize: .bytes(1_048_577))
        #expect(disk.size.bytes == 1_049_088)
        #expect(disk.sectorSize == 512)
    }

    @Test func createRejectsTooSmall() throws {
        expectError(.diskTooSmall(minimum: .bytes(512 * 68))) {
            try SDDiskImage.create(.inMemory, desiredSize: .bytes(512 * 67))
        }
        #expect(try SDDiskImage.create(.inMemory, desiredSize: .bytes(512 * 68)).sectorCount == 68)
        expectError(.diskTooSmall(minimum: .bytes(4096 * 12))) {
            try SDDiskImage.create(.inMemory, desiredSize: .bytes(4096 * 11), sectorSize: 4096)
        }
    }

    @Test func createStartsWithNoTable() throws {
        let disk = try SDDiskImage.create(.inMemory, desiredSize: .megabytes(4))
        #expect(disk.scheme == .none)
        #expect(disk.partitions.isEmpty)
        #expect(disk.diskID == nil)
        #expect((disk.device as? SDMemoryBlockDevice)?.allocatedByteCount == 0)
    }

    @Test func inMemoryCannotBeOpened() {
        #expect {
            try SDDiskImage.open(.inMemory)
        } throws: { error in
            guard case .invalidArgument = error as? SDError else {
                return false
            }
            return true
        }
    }

    @Test func unsupportedSectorSizes() throws {
        #expect(throws: SDError.self) { try SDDiskImage.create(.inMemory, desiredSize: .megabytes(1), sectorSize: 1024) }
        try withTemporaryDirectory { directory in
            let path = directory + "/a.img"
            _ = try SDDiskImage.create(.file(path), desiredSize: .megabytes(1))
            #expect(throws: SDError.self) { try SDDiskImage.open(.file(path), sectorSize: 2048) }
        }
    }

    @Test func fileImageRoundTrip() throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/disk.img"
            let written = try makeT3Image(at: path)
            #expect(written.map(\.label) == ["EFI", "WIN11ISO"])

            let disk = try SDDiskImage.open(.file(path))
            #expect(disk.scheme == .gpt(.healthy))
            #expect(disk.partitions == written)
            #expect(disk.sectorSize == 512)

            expectError(.fileExists(path: path)) {
                try SDDiskImage.create(.file(path), desiredSize: .megabytes(64))
            }
        }
    }

    @Test func readOnlyOpen() throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/ro.img"
            try makeT3Image(at: path)
            let before = try fileBytes(path)
            let disk = try SDDiskImage.open(.file(path), mode: .readOnly)
            #expect(disk.device.isReadOnly)
            #expect(disk.partitions.count == 2)
            #expect(throws: SDError.readOnly) { try disk.withTransaction { _ in } }
            expectError(.readOnly) { try disk.repair() }
            // A second read-only open shares the lock; a read-write open does not.
            _ = try SDDiskImage.open(.file(path), mode: .readOnly)
            expectError(.locked(path: path)) { try SDDiskImage.open(.file(path)) }
            #expect(try fileBytes(path) == before)
        }
    }

    // MARK: T8

    @Test func sameInputsGiveIdenticalBytes() throws {
        func build() throws -> SDMemoryBlockDevice {
            let disk = try SDDiskImage.create(.inMemory, desiredSize: .gigabytes(2))
            try disk.withTransaction { txn in
                txn.clear(diskID: UUID(uuidString: "0D15C0DE-0000-4000-8000-000000000000")!)
                try txn.addPartition(.megabytes(100), type: .efiSystem, label: "EFI",
                                     uniqueID: UUID(uuidString: "0D15C0DE-0000-4000-8000-000000000001")!)
                try txn.addPartition(.remaining, type: .microsoftBasicData, label: "윈도우",
                                     attributes: [.msNoDriveLetter],
                                     uniqueID: UUID(uuidString: "0D15C0DE-0000-4000-8000-000000000002")!)
                try txn.commit()
            }
            return disk.device as! SDMemoryBlockDevice
        }
        let a = try build()
        let b = try build()
        #expect(!a.chunks.isEmpty)
        #expect(a.chunks == b.chunks)
    }

    @Test func randomIDsDiffer() throws {
        func build() throws -> SDDisk {
            let disk = try SDDiskImage.create(.inMemory, desiredSize: .megabytes(8))
            try disk.withTransaction { txn in
                txn.clear()
                try txn.addPartition(.remaining, type: .efiSystem)
                try txn.commit()
            }
            return disk
        }
        let a = try build()
        let b = try build()
        #expect(a.diskID != b.diskID)
        #expect(a.partitions.first?.uniqueID != b.partitions.first?.uniqueID)
    }

    // MARK: T9

    @Test func eightTiBDisk() throws {
        let disk = try SDDiskImage.create(.inMemory, desiredSize: .terabytes(8))
        let device = disk.device as! SDMemoryBlockDevice
        try disk.withTransaction { txn in
            txn.clear()
            try txn.addPartition(.megabytes(512), type: .efiSystem, label: "EFI")
            let rest = try txn.addPartition(.remaining, type: .linuxFilesystem, label: "big")
            #expect(rest.end == disk.sectorCount - 34)
            #expect(rest.size > .terabytes(7))
            try txn.commit()
        }
        #expect(disk.scheme == .gpt(.healthy))
        let lba0 = try device.readSectors(lba: 0, count: 1)
        #expect(lba0.loadLE(UInt32.self, at: 446 + 12) == 0xFFFF_FFFF)
        let inspection = try SDInspection.read(from: device)
        #expect(inspection.backup?.lba == disk.sectorCount - 1)
        #expect(inspection.primary?.alternateLBA == disk.sectorCount - 1)
        #expect(device.allocatedByteCount < 1 << 20)
    }

    // MARK: T10

    @Test func fourKnLayout() throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/4kn.img"
            do {
                let disk = try SDDiskImage.create(.file(path), desiredSize: .megabytes(64), sectorSize: 4096)
                try disk.withTransaction { txn in
                    txn.clear()
                    let efi = try txn.addPartition(.megabytes(16), type: .efiSystem, label: "EFI")
                    #expect(efi.begin == 256)
                    try txn.addPartition(.remaining, type: .microsoftBasicData, label: "DATA")
                    try txn.commit()
                }
                let inspection = try SDInspection.read(from: disk.device)
                #expect(inspection.primary?.firstUsableLBA == 6)
                #expect(inspection.primary?.partitionEntryLBA == 2)
                #expect(inspection.primary?.entryArraySectorCount == 4)
                #expect(inspection.backup?.partitionEntryLBA == 16384 - 5)
            }

            let bytes = try fileBytes(path)
            #expect(bytes[510] == 0x55 && bytes[511] == 0xAA)
            #expect(bytes[446 + 4] == 0xEE)
            #expect(bytes[512 ..< 4096].allSatisfy { $0 == 0 }, "the MBR occupies only the first 512 bytes of LBA 0")
            #expect(Array(bytes[4096 ..< 4104]) == Array("EFI PART".utf8), "primary header at byte 4096")
            #expect(bytes[512 ..< 520].allSatisfy { $0 == 0 })

            let reopened = try SDDiskImage.open(.file(path))
            #expect(reopened.sectorSize == 4096)
            #expect(reopened.scheme == .gpt(.healthy))
            #expect(reopened.partitions.map(\.begin) == [256, 4352])
        }
    }

    @Test func sectorSizeDetection() throws {
        try withTemporaryDirectory { directory in
            let gpt512 = directory + "/512.img"
            try makeT3Image(at: gpt512)
            #expect(try SDDiskImage.detectSectorSize(path: gpt512) == 512)

            let blank = directory + "/blank.img"
            _ = try SDDiskImage.create(.file(blank), desiredSize: .megabytes(1), sectorSize: 4096)
            #expect(try SDDiskImage.detectSectorSize(path: blank) == 512, "no signature: default to 512")

            let tiny = directory + "/tiny.img"
            try Data(count: 100).write(to: URL(fileURLWithPath: tiny))
            #expect(try SDDiskImage.detectSectorSize(path: tiny) == 512)
        }
    }
}
