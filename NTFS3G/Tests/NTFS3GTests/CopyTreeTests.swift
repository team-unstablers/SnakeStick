// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import NTFS3G
import Testing

@Suite struct CopyTreeTests {
    @Test func copyTreeRoundTrip() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let source = scratch.url.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try Fixtures.makeStandardTree(at: source)
        let image = try scratch.makeVolume()

        let summary: NTFSCopySummary
        do {
            let volume = try NTFSVolume(path: image, mode: .readWrite)
            summary = try volume.copyTree(from: source)
            try volume.close()
        }

        let volume = try NTFSVolume(path: image, mode: .readOnly)
        defer { try? volume.close() }
        // Names as stored on the volume, byte for byte: the host's NFD name is stored in NFC.
        let expected = try hostTree(source.path).withNFCPaths
        let actual = try volumeTree(volume)
        #expect(actual.map(\.description) == expected.map(\.description))
        #expect(actual == expected)
        #expect(summary == Fixtures.standardTreeSummary)
        #expect(try volume.contentsOfDirectory("/한글 폴더").contains { sameBytes($0.name, "분해된 이름.txt") })
    }

    @Test func copyTreeSummaryMatchesSource() throws {
        try withScratchVolume { volume, scratch throws in
            let source = scratch.url.appendingPathComponent("source", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
            try Fixtures.makeStandardTree(at: source)

            let summary = try volume.copyTree(from: source)
            let host = try hostTree(source.path)
            #expect(summary.files == host.filter { $0.kind == .file }.count)
            #expect(summary.directories == host.filter { $0.kind == .directory }.count)
            #expect(summary.bytes == host.reduce(0) { $0 + $1.size })
        }
    }

    @Test func copyTreeMapsHostTimes() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let source = scratch.url.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try Fixtures.makeStandardTree(at: source)
        let image = try scratch.makeVolume()
        do {
            let volume = try NTFSVolume(path: image, mode: .readWrite)
            _ = try volume.copyTree(from: source)
            try volume.close()
        }

        let volume = try NTFSVolume(path: image, mode: .readOnly)
        defer { try? volume.close() }
        for path in ["/한글 폴더/nested/deep.txt", "/한글 폴더", "/Z", "/Big.bin"] {
            var info = stat()
            try #require(lstat(source.path + path, &info) == 0)
            let times = try volume.attributesOfItem(path).times
            // creation ← birth time; modification and access ← modification time (P9).
            #expect(ticks(times.creation) == ticks(info.st_birthtimespec))
            #expect(ticks(times.modification) == ticks(info.st_mtimespec))
            #expect(ticks(times.access) == ticks(info.st_mtimespec))
            // The fixture's times, not the time of the copy.
            #expect(times.modification < Date(timeIntervalSinceReferenceDate: 86_400 * 365))
        }
    }

    @Test func copyTreeIntoSubdirectory() throws {
        try withScratchVolume { volume, scratch throws in
            let source = scratch.url.appendingPathComponent("source", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
            try Data([1]).write(to: source.appendingPathComponent("one"))
            try volume.createDirectory("/sources")

            #expect(try volume.copyTree(from: source, to: "/sources") == NTFSCopySummary(files: 1, directories: 0, bytes: 1))
            #expect(try volume.contentsOfDirectory("/sources") == [.init(name: "one", kind: .file)])
            #expect(throws: NTFS3GError.notFound("/missing")) {
                _ = try volume.copyTree(from: source, to: "/missing")
            }
            #expect(throws: NTFS3GError.notADirectory("/sources/one")) {
                _ = try volume.copyTree(from: source, to: "/sources/one")
            }
            #expect(throws: NTFS3GError.alreadyExists("/sources/one")) {
                _ = try volume.copyTree(from: source, to: "/sources")
            }
        }
    }

    @Test func copyTreeProgress() throws {
        try withScratchVolume { volume, scratch throws in
            let source = scratch.url.appendingPathComponent("source", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
            try Fixtures.makeStandardTree(at: source)

            var reports: [NTFSCopyProgress] = []
            let summary = try volume.copyTree(from: source) { reports.append($0) }
            #expect(reports.allSatisfy { $0.totalBytes == Fixtures.standardTreeSummary.bytes })
            #expect(reports.last?.completedBytes == summary.bytes)
            #expect(zip(reports, reports.dropFirst()).allSatisfy { $0.completedBytes <= $1.completedBytes })
            // Every file is reported, including the empty one, in the order copyTree uses:
            // String's < within each directory, depth first. Paths are NTFS paths, in NFC.
            var paths: [String] = []
            for report in reports where paths.last != report.currentPath {
                paths.append(report.currentPath)
            }
            let expected = [
                "/Big.bin", "/Z/x", "/a.txt", "/empty.bin",
                "/한글 폴더/nested/deep.txt", "/한글 폴더/분해된 이름.txt", "/한글 폴더/한글 파일.txt",
            ]
            #expect(paths.map { Array($0.utf8) } == expected.map { Array($0.utf8) })
            // The large file is reported chunk by chunk.
            #expect(reports.filter { $0.currentPath == "/Big.bin" }.count == 2)
        }
    }

    @Test func copyTreeProgressCancellation() throws {
        try withScratchVolume { volume, scratch throws in
            let source = scratch.url.appendingPathComponent("source", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
            try Fixtures.makeStandardTree(at: source)

            #expect(throws: CancellationError.self) {
                _ = try volume.copyTree(from: source) { _ in throw CancellationError() }
            }
            // What was copied so far stays; the volume is still usable.
            #expect(try volume.contentsOfDirectory("/") == [.init(name: "Big.bin", kind: .file)])
            try volume.writeFile("/after", contents: [1])
        }
    }

    @Test func copyTreeRejectsSymlink() throws {
        try withScratchVolume { volume, scratch throws in
            let source = scratch.url.appendingPathComponent("source", isDirectory: true)
            try FileManager.default.createDirectory(at: source.appendingPathComponent("dir"), withIntermediateDirectories: true)
            try Data([1]).write(to: source.appendingPathComponent("a-first"))
            try Data([1]).write(to: source.appendingPathComponent("dir/target"))
            let link = source.appendingPathComponent("dir/link")
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "target")

            #expect(throws: NTFS3GError.unsupportedFileType(link)) {
                _ = try volume.copyTree(from: source)
            }
            // Detected while scanning, before anything is written.
            #expect(try volume.contentsOfDirectory("/").isEmpty)
        }
    }

    @Test func copyTreeRejectsSymlinkedSource() throws {
        try withScratchVolume { volume, scratch throws in
            let source = scratch.url.appendingPathComponent("source", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
            let link = scratch.url.appendingPathComponent("link")
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: source.path)

            #expect(throws: NTFS3GError.unsupportedFileType(link)) {
                _ = try volume.copyTree(from: link)
            }
        }
    }

    @Test func copyTreeRejectsFIFO() throws {
        try withScratchVolume { volume, scratch throws in
            let source = scratch.url.appendingPathComponent("source", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
            try Data([1]).write(to: source.appendingPathComponent("a-first"))
            let fifo = source.appendingPathComponent("fifo")
            try #require(mkfifo(fifo.path, 0o644) == 0)

            #expect(throws: NTFS3GError.unsupportedFileType(fifo)) {
                _ = try volume.copyTree(from: source)
            }
            #expect(try volume.contentsOfDirectory("/").isEmpty)
        }
    }

    @Test func copyTreeRejectsWindowsNamesBeforeWriting() throws {
        try withScratchVolume { volume, scratch throws in
            let source = scratch.url.appendingPathComponent("source", isDirectory: true)
            try FileManager.default.createDirectory(at: source.appendingPathComponent("sub"), withIntermediateDirectories: true)
            try Data([1]).write(to: source.appendingPathComponent("a-first"))
            // ':' is allowed by APFS but not by Windows.
            try Data([1]).write(to: source.appendingPathComponent("sub/a:b"))

            #expect(throws: NTFS3GError.invalidName("a:b")) {
                _ = try volume.copyTree(from: source)
            }
            #expect(try volume.contentsOfDirectory("/").isEmpty)
        }
    }

    @Test func copyTreeFromFileThrows() throws {
        try withScratchVolume { volume, scratch throws in
            let file = try scratch.makeSparseFile("file", size: 1)
            #expect(throws: NTFS3GError.posix(operation: "opendir", path: file, errno: ENOTDIR)) {
                _ = try volume.copyTree(from: URL(fileURLWithPath: file))
            }
        }
    }
}

@Suite struct EstimateTests {
    @Test(arguments: Fixtures.estimateFixtures)
    func estimatedSizeIsSufficientAndTight(fixture: Fixtures.EstimateFixture) throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let source = scratch.url.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try fixture.build(source.path)

        let estimate = try NTFSVolume.estimatedVolumeSize(forTreeAt: source)
        let content = try contentBytes(source.path)
        #expect(estimate % (1 << 20) == 0)
        #expect(estimate - content <= content / 33 + 96 * (1 << 20), "not wastefully large")

        let image = try scratch.makeVolume(size: estimate)
        let volume = try NTFSVolume(path: image, mode: .readWrite)
        let summary = try volume.copyTree(from: source)
        #expect(summary.bytes == content)
        try volume.close()
    }

    /// The estimate does not know the sector size, so it must also hold for 4096-byte sectors
    /// (4 KiB MFT records), and for other cluster sizes.
    @Test(arguments: [(512, 4096), (4096, 4096), (512, 512), (512, 65536), (4096, 65536)])
    func estimatedSizeHoldsForOtherGeometries(sectorSize: Int, clusterSize: Int) throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let source = scratch.url.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try Fixtures.estimateFixtures[1].build(source.path)  // many small files: the most metadata

        let estimate = try NTFSVolume.estimatedVolumeSize(forTreeAt: source, clusterSize: clusterSize)
        #expect(estimate % (1 << 20) == 0)
        let image = try scratch.makeVolume(size: estimate, options: .init(clusterSize: clusterSize, sectorSize: sectorSize))
        let volume = try NTFSVolume(path: image, mode: .readWrite)
        _ = try volume.copyTree(from: source)
        try volume.close()
    }

    @Test func estimateRejectsSymlinkAndFIFO() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let source = scratch.url.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        let link = source.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/")
        #expect(throws: NTFS3GError.unsupportedFileType(link)) {
            _ = try NTFSVolume.estimatedVolumeSize(forTreeAt: source)
        }
        try FileManager.default.removeItem(at: link)
        let fifo = source.appendingPathComponent("fifo")
        try #require(mkfifo(fifo.path, 0o644) == 0)
        #expect(throws: NTFS3GError.unsupportedFileType(fifo)) {
            _ = try NTFSVolume.estimatedVolumeSize(forTreeAt: source)
        }
    }
}
