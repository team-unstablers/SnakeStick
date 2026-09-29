//
//  DeviceTests.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

import Foundation
import Testing
@testable import SlopDisk

@Suite struct MemoryBlockDeviceTests {
    @Test func eightTiBDeviceStartsEmpty() {
        let device = SDMemoryBlockDevice(sectorSize: 512, sectorCount: 8 << 40 / 512)
        #expect(device.allocatedByteCount == 0)
    }

    @Test func oneSectorAllocatesOneChunk() throws {
        let device = SDMemoryBlockDevice(sectorSize: 512, sectorCount: 8 << 40 / 512)
        try device.writeSectors(lba: 0, [UInt8](repeating: 0x5A, count: 512))
        #expect(device.allocatedByteCount == 65536)
    }

    @Test func unwrittenSectorsReadAsZero() throws {
        let device = SDMemoryBlockDevice(sectorSize: 512, sectorCount: 8 << 40 / 512)
        try device.writeSectors(lba: 0, [UInt8](repeating: 0x5A, count: 512))
        for lba: UInt64 in [1, 127, 128, 1 << 20, device.sectorCount - 1] {
            #expect(try device.readSectors(lba: lba, count: 1).allSatisfy { $0 == 0 })
        }
        #expect(device.allocatedByteCount == 65536, "reads do not allocate")
    }

    @Test func writesAcrossChunkBoundaries() throws {
        let device = SDMemoryBlockDevice(sectorSize: 512, sectorCount: 1024)
        let pattern = (0 ..< 512 * 4).map { UInt8(truncatingIfNeeded: $0) }
        try device.writeSectors(lba: 126, pattern)  // LBAs 126...129 straddle the first 64 KiB boundary
        #expect(try device.readSectors(lba: 126, count: 4) == pattern)
        #expect(device.bytes(atByteOffset: 126 * 512, count: pattern.count) == pattern)
        #expect(device.allocatedByteCount == 2 * 65536)
    }

    @Test func contractViolations() {
        let device = SDMemoryBlockDevice(sectorSize: 512, sectorCount: 8)
        var odd = [UInt8](repeating: 0, count: 100)
        odd.withUnsafeMutableBytes { buffer in
            _ = #expect(throws: SDError.self) { try device.read(lba: 0, into: buffer) }
        }
        #expect(throws: SDError.self) { try device.readSectors(lba: 7, count: 2) }
        #expect(throws: SDError.self) { try device.writeSectors(lba: 8, [UInt8](repeating: 0, count: 512)) }
        #expect(throws: SDError.self) { try device.readSectors(lba: .max, count: 1) }
    }

    @Test func exportMatchesContents() throws {
        try withTemporaryDirectory { directory in
            let device = SDMemoryBlockDevice(sectorSize: 512, sectorCount: 300_000)
            try device.writeSectors(lba: 3, [UInt8](repeating: 0x11, count: 1024))
            try device.writeSectors(lba: 299_999, [UInt8](repeating: 0x22, count: 512))
            let path = directory + "/export.img"
            try device.export(toFile: path)

            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            #expect((attributes[.size] as? NSNumber)?.uint64Value == 300_000 * 512)

            let file = try SDFileBlockDevice(path: path, mode: .readOnly, sectorSize: 512)
            #expect(file.sectorCount == 300_000)
            for (lba, count) in [(0 as UInt64, 8), (299_990, 10), (150_000, 4)] {
                #expect(try file.readSectors(lba: lba, count: count)
                    == device.bytes(atByteOffset: lba * 512, count: count * 512))
            }
            #expect(try fileBytes(path) == device.allBytes)

            expectError(.fileExists(path: path)) { try device.export(toFile: path) }
        }
    }
}

@Suite struct FileBlockDeviceTests {
    @Test func createMakesSparseFileOfRequestedSize() throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/new.img"
            let device = try SDFileBlockDevice.create(path: path, byteCount: 64 << 20, sectorSize: 512)
            #expect(device.sectorCount == 131072)
            #expect(!device.isReadOnly)
            #expect(device.path == path)
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            #expect((attributes[.size] as? NSNumber)?.uint64Value == 64 << 20)
            #expect(try device.readSectors(lba: 131071, count: 1).allSatisfy { $0 == 0 })
        }
    }

    @Test func readWriteRoundTrip() throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/rw.img"
            let device = try SDFileBlockDevice.create(path: path, byteCount: 1 << 20, sectorSize: 4096)
            let pattern = (0 ..< 8192).map { UInt8(truncatingIfNeeded: $0 * 3) }
            try device.writeSectors(lba: 10, pattern)
            try device.synchronize()
            #expect(try device.readSectors(lba: 10, count: 2) == pattern)
            #expect(throws: SDError.self) { try device.readSectors(lba: 255, count: 2) }
        }
    }

    @Test func secondReadWriteOpenIsLocked() throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/lock.img"
            let first = try SDFileBlockDevice.create(path: path, byteCount: 1 << 20, sectorSize: 512)
            expectError(.locked(path: path)) {
                try SDFileBlockDevice(path: path, mode: .readWrite, sectorSize: 512)
            }
            expectError(.locked(path: path)) {
                try SDFileBlockDevice(path: path, mode: .readOnly, sectorSize: 512)
            }
            withExtendedLifetime(first) {}
        }
    }

    @Test func readWriteThenReadWriteIsLocked() throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/lock.img"
            _ = try SDFileBlockDevice.create(path: path, byteCount: 1 << 20, sectorSize: 512)
            let first = try SDFileBlockDevice(path: path, mode: .readWrite, sectorSize: 512)
            expectError(.locked(path: path)) {
                try SDFileBlockDevice(path: path, mode: .readWrite, sectorSize: 512)
            }
            withExtendedLifetime(first) {}
        }
    }

    @Test func sharedReadOnlyOpens() throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/shared.img"
            _ = try SDFileBlockDevice.create(path: path, byteCount: 1 << 20, sectorSize: 512)
            let first = try SDFileBlockDevice(path: path, mode: .readOnly, sectorSize: 512)
            let second = try SDFileBlockDevice(path: path, mode: .readOnly, sectorSize: 512)
            #expect(first.isReadOnly && second.isReadOnly)
            expectError(.locked(path: path)) {
                try SDFileBlockDevice(path: path, mode: .readWrite, sectorSize: 512)
            }
            withExtendedLifetime((first, second)) {}
        }
    }

    @Test func lockIsReleasedOnDeinit() throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/release.img"
            do {
                _ = try SDFileBlockDevice.create(path: path, byteCount: 1 << 20, sectorSize: 512)
            }
            let again = try SDFileBlockDevice(path: path, mode: .readWrite, sectorSize: 512)
            #expect(again.sectorCount == 2048)
        }
    }

    @Test func createDoesNotTouchExistingFile() throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/existing.img"
            let original = Data("precious".utf8)
            try original.write(to: URL(fileURLWithPath: path))
            expectError(.fileExists(path: path)) {
                try SDFileBlockDevice.create(path: path, byteCount: 1 << 20, sectorSize: 512)
            }
            #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == original)
        }
    }

    @Test func readOnlyRejectsWrites() throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/ro.img"
            _ = try SDFileBlockDevice.create(path: path, byteCount: 1 << 20, sectorSize: 512)
            let device = try SDFileBlockDevice(path: path, mode: .readOnly, sectorSize: 512)
            expectError(.readOnly) { try device.writeSectors(lba: 0, [UInt8](repeating: 1, count: 512)) }
            #expect(try fileBytes(path).allSatisfy { $0 == 0 })
        }
    }

    @Test func trailingBytesAreIgnored() throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/odd.img"
            try Data(count: 512 * 3 + 100).write(to: URL(fileURLWithPath: path))
            let device = try SDFileBlockDevice(path: path, mode: .readOnly, sectorSize: 512)
            #expect(device.sectorCount == 3)
        }
    }

    @Test func rejectsNonRegularFiles() throws {
        try withTemporaryDirectory { directory in
            _ = #expect {
                try SDFileBlockDevice(path: directory, mode: .readOnly, sectorSize: 512)
            } throws: { error in
                guard case .invalidArgument = error as? SDError else {
                    return false
                }
                return true
            }
        }
    }

    @Test func missingFileIsIOError() {
        expectError(.io(operation: "open", errno: ENOENT)) {
            try SDFileBlockDevice(path: "/nonexistent-\(UUID().uuidString)", mode: .readOnly, sectorSize: 512)
        }
    }

    @Test func unsupportedSectorSize() throws {
        try withTemporaryDirectory { directory in
            #expect(throws: SDError.self) {
                try SDFileBlockDevice.create(path: directory + "/x.img", byteCount: 1 << 20, sectorSize: 1000)
            }
            #expect(!FileManager.default.fileExists(atPath: directory + "/x.img"))
        }
    }
}
