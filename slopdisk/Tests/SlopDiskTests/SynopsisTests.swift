//
//  SynopsisTests.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//
//  T2. This file imports SlopDisk without @testable, so the SYNOPSIS is checked against the public API only.
//

import Foundation
import SlopDisk
import Testing

@Suite struct SynopsisTests {
    @Test func synopsisRuns() throws {
        // BEGIN SYNOPSIS (README.md, verbatim)
        let disk = try SDDiskImage.create(.inMemory, desiredSize: .gigabytes(16))
        // let disk = try SDDiskImage.open(.file("/tmp/disk-image.img"))
        // try disk.refresh()

        if disk.partitions.isEmpty {
            print("== NO PARTITIONS ==")
        } else {
            for partition in disk.partitions {
                print("Partition #\(partition.index): \(partition.begin) ~ \(partition.end) (\(partition.size))")
            }
        }

        try disk.withTransaction { txn in
            txn.clear()

            try txn.addPartition(.megabytes(400), type: .efiSystem, label: "EFI")
            try txn.addPartition(.megabytes(8192), type: .microsoftBasicData, label: "WIN11ISO")
            // writes partition table and sync()
            try txn.commit()
        }
        // END SYNOPSIS

        let summary = disk.partitions.map { ($0.index, $0.begin, $0.end, $0.label, $0.type) }
        #expect(summary.count == 2)
        #expect(summary[0] == (0, 2048, 821_247, "EFI", .efiSystem))
        #expect(summary[1] == (1, 821_248, 17_598_463, "WIN11ISO", .microsoftBasicData))
        #expect(disk.scheme == .gpt(.healthy))
        let device = try #require(disk.device as? SDMemoryBlockDevice)
        #expect(device.allocatedByteCount < 1 << 20)
    }

    /// The README SYNOPSIS and the block above must stay identical.
    @Test func readmeMatchesTest() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let readme = try String(contentsOf: packageRoot.appendingPathComponent("README.md"), encoding: .utf8)
        let source = try String(contentsOf: testFile, encoding: .utf8)

        let readmeLines = readme.components(separatedBy: "\n")
        let heading = try #require(readmeLines.firstIndex(of: "# SYNOPSIS"))
        let open = try #require(readmeLines[heading...].firstIndex(of: "```swift"))
        let close = try #require(readmeLines[(open + 1)...].firstIndex(of: "```"))
        let readmeBody = readmeLines[(open + 1) ..< close]
            .filter { $0 != "import Foundation" && $0 != "import SlopDisk" }
            .joined(separator: "\n")
            .trimmingCharacters(in: .newlines)

        let sourceLines = source.components(separatedBy: "\n")
        let begin = try #require(sourceLines.firstIndex { $0.contains("// BEGIN SYNOPSIS") })
        let end = try #require(sourceLines.firstIndex { $0.contains("// END SYNOPSIS") })
        let indent = String(repeating: " ", count: 8)
        let testBody = sourceLines[(begin + 1) ..< end]
            .map { $0.hasPrefix(indent) ? String($0.dropFirst(indent.count)) : $0 }
            .joined(separator: "\n")

        #expect(readmeBody == testBody)
    }
}
