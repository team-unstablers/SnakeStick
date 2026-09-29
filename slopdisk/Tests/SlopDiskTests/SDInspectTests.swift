//
//  SDInspectTests.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//
//  T13. Runs the sdinspect executable that `swift test` builds next to the test bundle.
//

import Foundation
import Testing
@testable import SlopDisk

private final class BundleMarker {}

enum SDInspectBinary {
    /// The first existing candidate. `swift build` / `swift test` place executables next to the test bundle.
    static let path: String? = {
        var candidates: [String] = []
        if let override = ProcessInfo.processInfo.environment["SLOPDISK_SDINSPECT_PATH"] {
            candidates.append(override)
        }
        let bundleDirectory = Bundle(for: BundleMarker.self).bundleURL.deletingLastPathComponent()
        candidates.append(bundleDirectory.appendingPathComponent("sdinspect").path)
        if let argument0 = CommandLine.arguments.first {
            let executableDirectory = URL(fileURLWithPath: argument0).resolvingSymlinksInPath().deletingLastPathComponent()
            candidates.append(executableDirectory.appendingPathComponent("sdinspect").path)
        }
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(packageRoot.appendingPathComponent(".build/debug/sdinspect").path)
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    static func run(_ arguments: [String]) throws -> ProcessResult {
        let path = try #require(path, "sdinspect executable not found; run `swift build` first")
        return try Tools.run(path, arguments)
    }
}

@Suite struct SDInspectTests {
    @Test func binaryIsBuilt() {
        #expect(SDInspectBinary.path != nil, "sdinspect must be built alongside the tests")
    }

    @Test func help() throws {
        let result = try SDInspectBinary.run(["--help"])
        #expect(result.status == 0)
        #expect(result.stdout.contains("usage: sdinspect"))
    }

    @Test(arguments: [
        [],
        ["--bogus", "x.img"],
        ["--sector-size", "1024", "x.img"],
        ["--sector-size"],
        ["a.img", "b.img"],
    ])
    func usageErrors(arguments: [String]) throws {
        let result = try SDInspectBinary.run(arguments)
        #expect(result.status == 64)
        #expect(result.stderr.contains("usage: sdinspect"))
    }

    @Test func missingFileIsIOError() throws {
        let result = try SDInspectBinary.run(["/tmp/does-not-exist-\(UUID().uuidString)"])
        #expect(result.status == 74)
    }

    @Test func healthyDegradedAndUnrecoverable() throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/t3.img"
            try makeT3Image(at: path)

            let healthy = try Self.runUnchanged(path, ["--hex", path])
            #expect(healthy.status == 0)
            #expect(healthy.stdout.contains("GPT (healthy)"))
            #expect(healthy.stdout.contains("EFI System"))
            #expect(healthy.stdout.contains("WIN11ISO"))
            #expect(healthy.stdout.contains("pmbr        : protective"))
            #expect(healthy.stdout.contains("LBA 131071 (512 bytes)"))
            #expect(healthy.stdout.contains("|EFI PART"))

            try patchFile(path, at: 512 + 40, [0xFF])
            let degraded = try Self.runUnchanged(path, [path])
            #expect(degraded.status == 1)
            #expect(degraded.stdout.contains("GPT (degraded: primaryHeaderInvalid(headerCRC))"))
            #expect(degraded.stdout.contains("header crc BAD("))

            try patchFile(path, at: 131_071 * 512 + 40, [0xFF])
            let unrecoverable = try Self.runUnchanged(path, ["--hex", path])
            #expect(unrecoverable.status == 2)
            #expect(unrecoverable.stdout.contains("GPT UNRECOVERABLE"))
            #expect(unrecoverable.stdout.contains("primary hdr : LBA 1"))
            #expect(unrecoverable.stdout.contains("backup  hdr : LBA 131071"))
            #expect(unrecoverable.stdout.contains("LBA 1 (512 bytes)"))
        }
    }

    @Test func garbageHeaderFieldsDoNotCrash() throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/garbage.img"
            try makeT3Image(at: path)
            // Signature intact, everything else 0xFF: header CRC fails and every field is huge.
            try patchFile(path, at: 512 + 8, [UInt8](repeating: 0xFF, count: 84))
            let result = try Self.runUnchanged(path, ["--hex", path])
            #expect(result.status == 1)
            #expect(result.stdout.contains("primaryHeaderInvalid(headerCRC)"))
            #expect(result.stdout.contains("(overflow)"))
        }
    }

    @Test func noTableAndMBR() throws {
        try withTemporaryDirectory { directory in
            let blank = directory + "/blank.img"
            _ = try SDDiskImage.create(.file(blank), desiredSize: .megabytes(1))
            let none = try Self.runUnchanged(blank, [blank])
            #expect(none.status == 0)
            #expect(none.stdout.contains("scheme      : NONE"))

            let mbr = directory + "/mbr.img"
            try DamageTests.classicMBRDevice().export(toFile: mbr)
            let result = try Self.runUnchanged(mbr, [mbr])
            #expect(result.status == 0)
            #expect(result.stdout.contains("scheme      : MBR"))
            #expect(result.stdout.contains("0x0C"))
        }
    }

    @Test func fourKnIsDetected() throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/4kn.img"
            do {
                let disk = try SDDiskImage.create(.file(path), desiredSize: .megabytes(64), sectorSize: 4096)
                try disk.withTransaction { txn in
                    txn.clear()
                    try txn.addPartition(.megabytes(16), type: .efiSystem, label: "EFI")
                    try txn.commit()
                }
            }
            let detected = try Self.runUnchanged(path, [path])
            #expect(detected.status == 0)
            #expect(detected.stdout.contains("sector size : 4096"))
            #expect(detected.stdout.contains("usable      : LBA 6 .. 16378"))

            let forced = try Self.runUnchanged(path, ["--sector-size", "512", path])
            #expect(forced.stdout.contains("sector size : 512"))
            #expect(forced.status == 2, "a 4Kn table read with 512-byte sectors is GPT evidence without a usable copy")
        }
    }

    @Test(.enabled(if: Tools.hasHdiutil, "requires /usr/bin/hdiutil"))
    func hdiutilFixture() throws {
        try withTemporaryDirectory { directory in
            let path = try ToolCrossCheckTests.makeHdiutilFixture(in: directory)
            let result = try Self.runUnchanged(path, [path])
            #expect(result.status == 0)
            #expect(result.stdout.contains("GPT (healthy)"))
            #expect(result.stdout.contains("disk image"))
            #expect(result.stdout.contains(" 0  40     16343"))
        }
    }

    /// The target keeps to read-only APIs. A regression guard in addition to the `.readOnly` open.
    @Test func sourceUsesNoWritePath() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/sdinspect")
        let files = try FileManager.default.contentsOfDirectory(atPath: sources.path).filter { $0.hasSuffix(".swift") }
        #expect(!files.isEmpty)
        let forbidden = ["withTransaction", "repair(", "commit(", ".readWrite", "SDDisk(", "SDDiskImage.open", "SDDiskImage.create", ".write(lba", "writeSectors", "export("]
        for file in files {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            for token in forbidden {
                #expect(!text.contains(token), "\(file) uses \(token)")
            }
        }
    }

    /// Runs sdinspect and checks that the image bytes are the same before and after.
    private static func runUnchanged(_ image: String, _ arguments: [String]) throws -> ProcessResult {
        let before = try fileBytes(image)
        let result = try SDInspectBinary.run(arguments)
        #expect(try fileBytes(image) == before, "sdinspect modified \(image)")
        return result
    }
}
