//
//  TestSupport.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

import Foundation
import Testing
@testable import SlopDisk

// MARK: - Temporary directories

/// Runs `body` with a fresh, unique directory that is removed afterwards.
/// Swift Testing runs tests in parallel, so every file-based test gets its own directory.
func withTemporaryDirectory<R>(_ body: (String) throws -> R) throws -> R {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("SlopDiskTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: url) }
    return try body(url.path(percentEncoded: false))
}

func fileBytes(_ path: String) throws -> [UInt8] {
    [UInt8](try Data(contentsOf: URL(fileURLWithPath: path)))
}

func truncateFile(_ path: String, to size: UInt64) throws {
    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    defer { try? handle.close() }
    try handle.truncate(atOffset: size)
}

/// Patches bytes of an image file in place.
func patchFile(_ path: String, at offset: UInt64, _ bytes: [UInt8]) throws {
    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    defer { try? handle.close() }
    try handle.seek(toOffset: offset)
    try handle.write(contentsOf: Data(bytes))
}

// MARK: - External tools

struct ProcessResult {
    var status: Int32
    var stdout: String
    var stderr: String
}

enum Tools {
    static let hdiutil = "/usr/bin/hdiutil"
    static let gpt = "/usr/sbin/gpt"
    static let newfsMSDOS = "/sbin/newfs_msdos"
    static let fsckMSDOS = "/sbin/fsck_msdos"

    static var hasHdiutil: Bool { FileManager.default.isExecutableFile(atPath: hdiutil) }
    static var hasGPT: Bool { FileManager.default.isExecutableFile(atPath: gpt) }
    static var hasMacOSTools: Bool { hasHdiutil && hasGPT }

    /// `hdiutil attach` tests run only when explicitly requested.
    static var attachEnabled: Bool {
        ProcessInfo.processInfo.environment["SLOPDISK_TEST_HDIUTIL_ATTACH"] == "1"
            && hasHdiutil
            && FileManager.default.isExecutableFile(atPath: newfsMSDOS)
            && FileManager.default.isExecutableFile(atPath: fsckMSDOS)
    }

    /// Runs an executable to completion. Output goes through temporary files so that a full pipe cannot deadlock.
    static func run(_ executable: String, _ arguments: [String]) throws -> ProcessResult {
        try withTemporaryDirectory { directory in
            let outURL = URL(fileURLWithPath: directory + "/stdout")
            let errURL = URL(fileURLWithPath: directory + "/stderr")
            _ = FileManager.default.createFile(atPath: outURL.path, contents: nil)
            _ = FileManager.default.createFile(atPath: errURL.path, contents: nil)
            let out = try FileHandle(forWritingTo: outURL)
            let err = try FileHandle(forWritingTo: errURL)
            defer {
                try? out.close()
                try? err.close()
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = out
            process.standardError = err
            try process.run()
            process.waitUntilExit()
            return ProcessResult(
                status: process.terminationStatus,
                stdout: String(decoding: try Data(contentsOf: outURL), as: UTF8.self),
                stderr: String(decoding: try Data(contentsOf: errURL), as: UTF8.self)
            )
        }
    }
}

// MARK: - Golden bytes

/// Bytes taken from a real `hdiutil create -size 8m -layout GPTSPUD -type UDIF` image
/// (Prompts/10-implementation.xml, code#fixture-bytes).
enum Golden {
    static let primaryHeader: [UInt8] = [
        0x45, 0x46, 0x49, 0x20, 0x50, 0x41, 0x52, 0x54, 0x00, 0x00, 0x01, 0x00, 0x5c, 0x00, 0x00, 0x00,
        0xe1, 0xb8, 0x75, 0xd4, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0xff, 0x3f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x22, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0xde, 0x3f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3b, 0xd7, 0x4a, 0xfb, 0x60, 0xfc, 0x17, 0x48,
        0xbd, 0x0a, 0xbc, 0xec, 0x08, 0x0b, 0xa8, 0xcd, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x80, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0xbb, 0x94, 0xf5, 0x1f,
    ]

    static let entry0: [UInt8] = [
        0x00, 0x53, 0x46, 0x48, 0x00, 0x00, 0xaa, 0x11, 0xaa, 0x11, 0x00, 0x30, 0x65, 0x43, 0xec, 0xac,
        0x5e, 0xf8, 0x98, 0x5c, 0x26, 0x9e, 0x22, 0x44, 0xba, 0x5f, 0x33, 0x0e, 0xa5, 0x6a, 0x95, 0x00,
        0x28, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xd7, 0x3f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x64, 0x00, 0x69, 0x00, 0x73, 0x00, 0x6b, 0x00,
        0x20, 0x00, 0x69, 0x00, 0x6d, 0x00, 0x61, 0x00, 0x67, 0x00, 0x65, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]

    /// LBA 0 offset 446: protective record with Apple's start CHS FE FF FF.
    static let mbrRecord0: [UInt8] = [
        0x00, 0xfe, 0xff, 0xff, 0xee, 0xfe, 0xff, 0xff, 0x01, 0x00, 0x00, 0x00, 0xff, 0x3f, 0x00, 0x00,
    ]

    static let headerCRC: UInt32 = 0xD475_B8E1
    static let entriesCRC: UInt32 = 0x1FF5_94BB
    static let diskGUID = UUID(uuidString: "FB4AD73B-FC60-4817-BD0A-BCEC080BA8CD")!
    static let entryType = UUID(uuidString: "48465300-0000-11AA-AA11-00306543ECAC")!
    static let entryUnique = UUID(uuidString: "5C98F85E-9E26-4422-BA5F-330EA56A9500")!
    static let sectorCount: UInt64 = 16384

    /// The 8 MiB fixture rebuilt from golden bytes. LBA 0, LBA 1, and the primary entry array are golden;
    /// the backup header is the golden header with MyLBA, AlternateLBA, and PartitionEntryLBA moved, as hdiutil writes it.
    static func fixtureDevice() -> SDMemoryBlockDevice {
        let device = SDMemoryBlockDevice(sectorSize: 512, sectorCount: sectorCount)
        var lba0 = [UInt8](repeating: 0, count: 512)
        lba0.replaceSubrange(446 ..< 462, with: mbrRecord0)
        lba0[510] = 0x55
        lba0[511] = 0xAA
        var lba1 = [UInt8](repeating: 0, count: 512)
        lba1.replaceSubrange(0 ..< 92, with: primaryHeader)
        var entries = [UInt8](repeating: 0, count: 32 * 512)
        entries.replaceSubrange(0 ..< 128, with: entry0)
        var backup = GPTHeader(decoding: lba1)
        backup.myLBA = sectorCount - 1
        backup.alternateLBA = 1
        backup.partitionEntryLBA = sectorCount - 33
        try! device.writeSectors(lba: 0, lba0)
        try! device.writeSectors(lba: 1, lba1)
        try! device.writeSectors(lba: 2, entries)
        try! device.writeSectors(lba: sectorCount - 33, entries)
        try! device.writeSectors(lba: sectorCount - 1, backup.encode(sectorSize: 512))
        return device
    }
}

// MARK: - Device wrappers

/// Records every call and forwards it to an inner device.
final class RecordingDevice: SDBlockDevice {
    enum Call: Equatable {
        case read(lba: UInt64, sectors: Int)
        case write(lba: UInt64, sectors: Int)
        case synchronize
    }

    let inner: any SDBlockDevice
    private(set) var calls: [Call] = []

    init(_ inner: any SDBlockDevice) {
        self.inner = inner
    }

    var sectorSize: Int { inner.sectorSize }
    var sectorCount: UInt64 { inner.sectorCount }
    var isReadOnly: Bool { inner.isReadOnly }

    func read(lba: UInt64, into buffer: UnsafeMutableRawBufferPointer) throws(SDError) {
        calls.append(.read(lba: lba, sectors: buffer.count / sectorSize))
        try inner.read(lba: lba, into: buffer)
    }

    func write(lba: UInt64, from buffer: UnsafeRawBufferPointer) throws(SDError) {
        calls.append(.write(lba: lba, sectors: buffer.count / sectorSize))
        try inner.write(lba: lba, from: buffer)
    }

    func synchronize() throws(SDError) {
        calls.append(.synchronize)
        try inner.synchronize()
    }
}

/// Simulates a crash: the `failAt`-th write (1-based) and every write after it throw without touching the inner device.
final class CrashingDevice: SDBlockDevice {
    let inner: any SDBlockDevice
    let failAt: Int
    private(set) var writeCount = 0

    init(_ inner: any SDBlockDevice, failAt: Int) {
        self.inner = inner
        self.failAt = failAt
    }

    var sectorSize: Int { inner.sectorSize }
    var sectorCount: UInt64 { inner.sectorCount }
    var isReadOnly: Bool { inner.isReadOnly }

    func read(lba: UInt64, into buffer: UnsafeMutableRawBufferPointer) throws(SDError) {
        try inner.read(lba: lba, into: buffer)
    }

    func write(lba: UInt64, from buffer: UnsafeRawBufferPointer) throws(SDError) {
        writeCount += 1
        if writeCount >= failAt {
            throw .device(description: "simulated crash at write #\(writeCount)")
        }
        try inner.write(lba: lba, from: buffer)
    }

    func synchronize() throws(SDError) {
        try inner.synchronize()
    }
}

/// A read-only view of another device.
final class ReadOnlyDevice: SDBlockDevice {
    let inner: any SDBlockDevice

    init(_ inner: any SDBlockDevice) {
        self.inner = inner
    }

    var sectorSize: Int { inner.sectorSize }
    var sectorCount: UInt64 { inner.sectorCount }
    var isReadOnly: Bool { true }

    func read(lba: UInt64, into buffer: UnsafeMutableRawBufferPointer) throws(SDError) {
        try inner.read(lba: lba, into: buffer)
    }

    func write(lba: UInt64, from buffer: UnsafeRawBufferPointer) throws(SDError) {
        throw .readOnly
    }

    func synchronize() throws(SDError) {}
}

// MARK: - Helpers

extension SDMemoryBlockDevice {
    /// Every byte of the device. Only for small devices; compare `chunks` for large ones.
    var allBytes: [UInt8] {
        bytes(atByteOffset: 0, count: Int(sectorCount) * sectorSize)
    }

    /// A device with the same geometry and a copy of every allocated chunk.
    func copy() -> SDMemoryBlockDevice {
        let copy = SDMemoryBlockDevice(sectorSize: sectorSize, sectorCount: sectorCount)
        let sectorsPerChunk = UInt64(SDMemoryBlockDevice.chunkSize / sectorSize)
        for (index, chunk) in chunks {
            let lba = index * sectorsPerChunk
            let sectors = min(sectorsPerChunk, sectorCount - lba)
            try! copy.writeSectors(lba: lba, Array(chunk[0 ..< Int(sectors) * sectorSize]))
        }
        return copy
    }
}

/// Asserts that `body` throws exactly `expected`.
///
/// The closure is untyped on purpose: typed-throws inference for closures passed to a generic function falls back
/// to `any Error` in some contexts, so the error type is checked at runtime instead.
func expectError<R>(_ expected: SDError, sourceLocation: SourceLocation = #_sourceLocation, _ body: () throws -> R) {
    do {
        _ = try body()
        Issue.record("expected \(expected), but nothing was thrown", sourceLocation: sourceLocation)
    } catch let error as SDError {
        #expect(error == expected, sourceLocation: sourceLocation)
    } catch {
        Issue.record("expected \(expected), got non-SDError \(error)", sourceLocation: sourceLocation)
    }
}

/// A 64 MiB file image with the T3 layout: 16 MiB EFI System, then Microsoft Basic Data for the rest.
/// The disk is released before returning, so the file is closed and unlocked.
@discardableResult
func makeT3Image(at path: String) throws -> [SDPartition] {
    let disk = try SDDiskImage.create(.file(path), desiredSize: .megabytes(64))
    try disk.withTransaction { txn in
        txn.clear()
        try txn.addPartition(.megabytes(16), type: .efiSystem, label: "EFI")
        try txn.addPartition(.remaining, type: .microsoftBasicData, label: "WIN11ISO")
        try txn.commit()
    }
    return disk.partitions
}

/// `true` for `/dev/diskN` or `/dev/rdiskN` (the only whole-disk paths tests may use, and only from attach output).
func isWholeDiskPath(_ path: String) -> Bool {
    path.wholeMatch(of: /\/dev\/r?disk[0-9]+/) != nil
}

/// `true` for `/dev/diskNsK` or `/dev/rdiskNsK`.
func isSliceDevicePath(_ path: String) -> Bool {
    path.wholeMatch(of: /\/dev\/r?disk[0-9]+s[0-9]+/) != nil
}
