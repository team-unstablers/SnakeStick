// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import NTFS3G
import Testing

@Suite struct FileTests {
    @Test func writeFileRoundTrip() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let image = try scratch.makeVolume()
        let payload = pattern(count: (20 << 20) + 12345, seed: 7)
        let source = scratch.url.appendingPathComponent("source.bin")
        try Data(payload).write(to: source)

        do {
            let volume = try NTFSVolume(path: image, mode: .readWrite)
            try volume.createDirectory("/dir")
            try volume.writeFile("/dir/payload.bin", from: source)
            try volume.close()
        }

        let volume = try NTFSVolume(path: image, mode: .readOnly)
        defer { try? volume.close() }
        let attributes = try volume.attributesOfItem("/dir/payload.bin")
        #expect(attributes.kind == .file)
        #expect(attributes.size == Int64(payload.count))
        let readBack = try volume.readAll("/dir/payload.bin")
        #expect(readBack == payload)
    }

    @Test func writeFileProgress() throws {
        try withScratchVolume { volume, scratch throws in
            let size = (20 << 20) + 12345
            let source = try scratch.makeSparseFile("source.bin", size: Int64(size))
            var reported: [Int64] = []
            try volume.writeFile("/payload.bin", from: URL(fileURLWithPath: source)) { reported.append($0) }
            #expect(reported.last == Int64(size))
            #expect(zip(reported, reported.dropFirst()).allSatisfy { $0 < $1 })
            // 8 MiB chunks.
            #expect(reported == [8 << 20, 16 << 20, Int64(size)])
        }
    }

    @Test func writeEmptyFileReportsProgressOnce() throws {
        try withScratchVolume { volume, scratch throws in
            let source = try scratch.makeSparseFile("empty.bin", size: 0)
            var reported: [Int64] = []
            try volume.writeFile("/empty.bin", from: URL(fileURLWithPath: source)) { reported.append($0) }
            #expect(reported == [0])
            #expect(try volume.attributesOfItem("/empty.bin").size == 0)
        }
    }

    @Test func writeFileProgressCancellation() throws {
        try withScratchVolume { volume, scratch throws in
            let source = try scratch.makeSparseFile("source.bin", size: 20 << 20)
            var calls = 0
            #expect(throws: CancellationError.self) {
                try volume.writeFile("/payload.bin", from: URL(fileURLWithPath: source)) { _ in
                    calls += 1
                    throw CancellationError()
                }
            }
            #expect(calls == 1)
            // The partly written file stays, and the volume is still usable.
            #expect(try volume.contentsOfDirectory("/") == [.init(name: "payload.bin", kind: .file)])
            #expect(try volume.attributesOfItem("/payload.bin").size == 8 << 20)
            try volume.writeFile("/after.bin", contents: [1])
        }
    }

    @Test func writeFileTimes() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let image = try scratch.makeVolume()
        let source = try scratch.makeSparseFile("source.bin", size: 3 << 20)

        do {
            let volume = try NTFSVolume(path: image, mode: .readWrite)
            try volume.writeFile("/from-url.bin", from: URL(fileURLWithPath: source), times: fixedTimes)
            try volume.writeFile("/from-bytes.bin", contents: pattern(count: 5000), times: fixedTimes)
            try volume.close()
        }

        let volume = try NTFSVolume(path: image, mode: .readOnly)
        defer { try? volume.close() }
        #expect(ticks(try volume.attributesOfItem("/from-url.bin").times) == ticks(fixedTimes))
        #expect(ticks(try volume.attributesOfItem("/from-bytes.bin").times) == ticks(fixedTimes))
    }

    @Test func writeFileWithoutTimesUsesCurrentTime() throws {
        try withScratchVolume { volume, _ throws in
            let start = Date()
            try volume.writeFile("/f", contents: [1])
            let times = try volume.attributesOfItem("/f").times
            #expect(abs(times.modification.timeIntervalSince(start)) < 60)
            #expect(abs(times.creation.timeIntervalSince(start)) < 60)
        }
    }

    @Test(arguments: [
        Date(timeIntervalSinceReferenceDate: -12_622_780_801),  // one second before 1601-01-01
        Date.distantPast,
        Date(timeIntervalSinceReferenceDate: .infinity),
    ])
    func writeFileRejectsUnrepresentableTimes(date: Date) throws {
        try withScratchVolume { volume, _ throws in
            let times = NTFSFileTimes(creation: fixedTimes.creation, modification: date, access: fixedTimes.access)
            #expect(throws: NTFS3GError.posix(operation: "setTimes", path: "/f", errno: EINVAL)) {
                try volume.writeFile("/f", contents: [1], times: times)
            }
            // Nothing is created.
            #expect(try volume.contentsOfDirectory("/").isEmpty)
        }
    }

    @Test func earliestNTFSTimeRoundTrips() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let image = try scratch.makeVolume()
        let epoch = Date(timeIntervalSinceReferenceDate: -12_622_780_800)  // 1601-01-01
        let times = NTFSFileTimes(creation: epoch, modification: epoch, access: epoch)
        do {
            let volume = try NTFSVolume(path: image, mode: .readWrite)
            try volume.writeFile("/f", contents: [], times: times)
            try volume.close()
        }
        let volume = try NTFSVolume(path: image, mode: .readOnly)
        defer { try? volume.close() }
        #expect(ticks(try volume.attributesOfItem("/f").times) == ticks(times))
    }

    @Test func writeFileTwiceThrows() throws {
        try withScratchVolume { volume, scratch throws in
            let source = try scratch.makeSparseFile("source.bin", size: 100)
            try volume.writeFile("/f", from: URL(fileURLWithPath: source))
            #expect(throws: NTFS3GError.alreadyExists("/f")) {
                try volume.writeFile("/f", from: URL(fileURLWithPath: source))
            }
            #expect(throws: NTFS3GError.alreadyExists("/f")) {
                try volume.writeFile("/f", contents: [])
            }
            #expect(throws: NTFS3GError.alreadyExists("/f")) {
                try volume.createDirectory("/f")
            }
        }
    }

    @Test func writeFileKoreanName() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let image = try scratch.makeVolume()
        let composed = "한글 파일.txt"
        let source = scratch.url.appendingPathComponent("source.txt")
        try Data("안녕".utf8).write(to: source)

        do {
            let volume = try NTFSVolume(path: image, mode: .readWrite)
            try volume.writeFile("/" + composed, from: source)
            try volume.createDirectory("/디렉터리")
            try volume.close()
        }

        let volume = try NTFSVolume(path: image, mode: .readOnly)
        defer { try? volume.close() }
        let root = try volume.contentsOfDirectory("/")
        #expect(root.count == 2)
        #expect(root.contains { sameBytes($0.name, composed) && $0.kind == .file })
        #expect(root.contains { sameBytes($0.name, "디렉터리") && $0.kind == .directory })
        #expect(try volume.readAll("/" + composed) == Array("안녕".utf8))
    }

    @Test func namesAreStoredInNFC() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let image = try scratch.makeVolume()
        let composed = "분해된 이름.txt"
        let decomposed = composed.decomposedStringWithCanonicalMapping
        let decomposedDirectory = "폴더".decomposedStringWithCanonicalMapping
        #expect(!sameBytes(composed, decomposed))

        do {
            let volume = try NTFSVolume(path: image, mode: .readWrite)
            try volume.createDirectory("/" + decomposedDirectory)
            try volume.writeFile("/" + decomposedDirectory + "/" + decomposed, contents: [1])
            // Both spellings name the same item.
            #expect(throws: NTFS3GError.alreadyExists("/폴더/" + composed)) {
                try volume.writeFile("/폴더/" + composed, contents: [2])
            }
            try volume.close()
        }

        let volume = try NTFSVolume(path: image, mode: .readOnly)
        defer { try? volume.close() }
        let root = try volume.contentsOfDirectory("/")
        #expect(root.count == 1)
        #expect(sameBytes(root[0].name, "폴더"))
        let nested = try volume.contentsOfDirectory("/" + decomposedDirectory)
        #expect(nested.count == 1)
        #expect(sameBytes(nested[0].name, composed))
        #expect(try volume.readAll("/폴더/" + composed) == [1])
        #expect(try volume.readAll("/" + decomposedDirectory + "/" + decomposed) == [1])
    }

    @Test func writeEmptyContents() throws {
        try withScratchVolume { volume, _ throws in
            try volume.writeFile("/empty", contents: [])
            #expect(try volume.attributesOfItem("/empty").size == 0)
            #expect(try volume.attributesOfItem("/empty").kind == .file)
        }
    }

    @Test(arguments: [1, 500, 4096, 100_000])
    func writeContentsRoundTrip(size: Int) throws {
        try withScratchVolume { volume, _ throws in
            let payload = pattern(count: size, seed: 3)
            try volume.writeFile("/f", contents: payload)
            #expect(try volume.readAll("/f") == payload)
        }
    }

    @Test func writeFileFromDirectoryOrFIFOThrows() throws {
        try withScratchVolume { volume, scratch throws in
            #expect(throws: NTFS3GError.posix(operation: "open", path: scratch.url.path, errno: EISDIR)) {
                try volume.writeFile("/f", from: scratch.url)
            }
            let fifo = scratch.path("fifo")
            try #require(mkfifo(fifo, 0o644) == 0)
            #expect(throws: NTFS3GError.unsupportedFileType(URL(fileURLWithPath: fifo))) {
                try volume.writeFile("/f", from: URL(fileURLWithPath: fifo))
            }
            #expect(try volume.contentsOfDirectory("/").isEmpty)
        }
    }

    @Test func nonFileURLsThrow() throws {
        try withScratchVolume { volume, _ throws in
            let url = try #require(URL(string: "https://example.com/install.wim"))
            #expect(throws: NTFS3GError.posix(operation: "open", path: url.absoluteString, errno: EINVAL)) {
                try volume.writeFile("/f", from: url)
            }
            #expect(throws: NTFS3GError.posix(operation: "open", path: url.absoluteString, errno: EINVAL)) {
                _ = try volume.copyTree(from: url)
            }
            #expect(throws: NTFS3GError.posix(operation: "open", path: url.absoluteString, errno: EINVAL)) {
                _ = try NTFSVolume.estimatedVolumeSize(forTreeAt: url)
            }
        }
    }

    @Test func readFileAtEndReturnsZero() throws {
        try withScratchVolume { volume, _ throws in
            let payload = pattern(count: 10_000)
            try volume.writeFile("/f", contents: payload)
            var buffer = [UInt8](repeating: 0, count: 4096)
            try buffer.withUnsafeMutableBytes { bytes throws in
                #expect(try volume.readFile("/f", into: bytes, at: 10_000) == 0)
                #expect(try volume.readFile("/f", into: bytes, at: 20_000) == 0)
                #expect(try volume.readFile("/f", into: bytes, at: 9_000) == 1000)
            }
            #expect(buffer[..<1000].elementsEqual(payload[9000...]))
        }
    }

    @Test func readFileOnDirectoryThrows() throws {
        try withScratchVolume { volume, _ throws in
            try volume.createDirectory("/d")
            var buffer = [UInt8](repeating: 0, count: 16)
            buffer.withUnsafeMutableBytes { bytes in
                #expect(throws: NTFS3GError.isADirectory("/d")) {
                    try volume.readFile("/d", into: bytes, at: 0)
                }
                #expect(throws: NTFS3GError.isADirectory("/")) {
                    try volume.readFile("/", into: bytes, at: 0)
                }
            }
        }
    }
}
