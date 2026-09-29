//
//  ToolCrossCheckTests.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//
//  (b) Cross-checks against tools that ship with macOS. Skipped where they are missing (Linux).
//  These tests only read or create image files in their own temporary directory; nothing is attached.
//

import Foundation
import Testing
@testable import SlopDisk

@Suite(.enabled(if: Tools.hasMacOSTools, "requires /usr/bin/hdiutil and /usr/sbin/gpt"))
struct ToolCrossCheckTests {
    struct GPTShowRow: Equatable {
        var start: UInt64
        var size: UInt64
        var index: Int
        var contents: String
    }

    /// The "GPT part" rows of `gpt -r show`. `gpt` exits 0 even for blank images, so the output is what counts.
    static func gptShow(_ path: String, labels: Bool = false) throws -> [GPTShowRow] {
        let result = try Tools.run(Tools.gpt, ["-r", "show"] + (labels ? ["-l"] : []) + [path])
        #expect(result.status == 0, "gpt -r show failed: \(result.stderr)")
        return result.stdout.split(separator: "\n").compactMap { line in
            guard let marker = line.range(of: "GPT part - ") else {
                return nil
            }
            let fields = line[..<marker.lowerBound].split(separator: " ")
            guard fields.count == 3, let start = UInt64(fields[0]), let size = UInt64(fields[1]), let index = Int(fields[2]) else {
                return nil
            }
            return GPTShowRow(start: start, size: size, index: index, contents: String(line[marker.upperBound...]))
        }
    }

    static func imageInfo(_ path: String) throws -> [String: Any] {
        let result = try Tools.run(Tools.hdiutil, ["imageinfo", "-plist", path])
        #expect(result.status == 0, "hdiutil imageinfo failed: \(result.stderr)")
        let plist = try PropertyListSerialization.propertyList(from: Data(result.stdout.utf8), format: nil)
        return try #require(plist as? [String: Any])
    }

    /// `hdiutil create -layout GPTSPUD` without `-fs` (which fails in sandboxes) produces a raw GPT image.
    static func makeHdiutilFixture(in directory: String) throws -> String {
        let result = try Tools.run(Tools.hdiutil, ["create", "-size", "8m", "-layout", "GPTSPUD", "-type", "UDIF", directory + "/fx"])
        #expect(result.status == 0, "hdiutil create failed: \(result.stderr)")
        return directory + "/fx.dmg"
    }

    // MARK: T3

    @Test func gptShowSeesSlopDiskTable() throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/t3.img"
            try makeT3Image(at: path)
            #expect(try Self.gptShow(path) == [
                GPTShowRow(start: 2048, size: 32768, index: 1, contents: "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"),
                GPTShowRow(start: 34816, size: 96223, index: 2, contents: "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"),
            ])
            #expect(try Self.gptShow(path, labels: true).map(\.contents) == ["\"EFI\"", "\"WIN11ISO\""])
        }
    }

    @Test func gptShowSeesNonASCIILabels() throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/labels.img"
            do {
                let disk = try SDDiskImage.create(.file(path), desiredSize: .megabytes(8))
                try disk.withTransaction { txn in
                    txn.clear()
                    try txn.addPartition(.megabytes(1), type: .microsoftBasicData, label: "윈도우설치")
                    try txn.commit()
                }
            }
            #expect(try Self.gptShow(path, labels: true).map(\.contents) == ["\"윈도우설치\""])
        }
    }

    // MARK: T4

    @Test func imageInfoPartitionUUIDsMatch() throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/t3.img"
            let partitions = try makeT3Image(at: path)
            let info = try Self.imageInfo(path)
            let table = try #require(info["partitions"] as? [String: Any])
            #expect(table["partition-scheme"] as? String == "GUID")
            let entries = try #require(table["partitions"] as? [[String: Any]])
            let real = entries.filter { $0["partition-UUID"] != nil }
            #expect(real.count == 2)
            for (entry, partition) in zip(real, partitions) {
                #expect(entry["partition-UUID"] as? String == partition.uniqueID.uuidString)
                #expect((entry["partition-start"] as? NSNumber)?.uint64Value == partition.begin)
                #expect((entry["partition-length"] as? NSNumber)?.uint64Value == partition.end - partition.begin + 1)
                #expect(entry["partition-name"] as? String == partition.label)
            }
        }
    }

    // MARK: T5

    @Test func readsHdiutilFixture() throws {
        try withTemporaryDirectory { directory in
            let path = try Self.makeHdiutilFixture(in: directory)
            #expect((try FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.intValue == 8_388_608)

            let before = try fileBytes(path)
            let disk = try SDDiskImage.open(.file(path), mode: .readOnly)
            #expect(disk.scheme == .gpt(.healthy))
            #expect(disk.sectorSize == 512)
            #expect(disk.sectorCount == Golden.sectorCount)
            let partition = try #require(disk.partitions.first)
            #expect(disk.partitions.count == 1)
            #expect(partition.index == 0)
            #expect(partition.begin == 40)
            #expect(partition.end == 16343)
            #expect(partition.label == "disk image")
            #expect(partition.type == .appleHFSPlus)

            let inspection = try SDInspection.read(from: disk.device)
            #expect(inspection.primary?.firstUsableLBA == 34)
            #expect(inspection.primary?.lastUsableLBA == 16350)
            #expect(inspection.primary?.alternateLBA == 16383)
            #expect(inspection.backup?.partitionEntryLBA == 16351)
            #expect(inspection.mbr.kind == .protective)

            // hdiutil generates fresh GUIDs for every image, so compare them with its own report rather than F5.
            let info = try Self.imageInfo(path)
            let entries = try #require((info["partitions"] as? [String: Any])?["partitions"] as? [[String: Any]])
            let uuids = entries.compactMap { $0["partition-UUID"] as? String }
            #expect(uuids == [partition.uniqueID.uuidString])
            #expect(try fileBytes(path) == before)
        }
    }

    @Test func repairedHdiutilFixtureStillReadsInTools() throws {
        try withTemporaryDirectory { directory in
            let path = try Self.makeHdiutilFixture(in: directory)
            do {
                let disk = try SDDiskImage.open(.file(path))
                try disk.repair()
                #expect(disk.scheme == .gpt(.healthy))
            }
            let rows = try Self.gptShow(path, labels: true)
            #expect(rows == [GPTShowRow(start: 40, size: 16304, index: 1, contents: "\"disk image\"")])
            let info = try Self.imageInfo(path)
            #expect((info["partitions"] as? [String: Any])?["partition-scheme"] as? String == "GUID")
        }
    }
}
