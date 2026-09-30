// SPDX-License-Identifier: LGPL-2.1-or-later

import CWIMLib
import Foundation
import Testing
import WIMLib

@Suite struct LifecycleTests {
    @Test func closeTwiceDoesNothing() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let file = try WIMFile(path: try Fixture.makeWIM(in: scratch))
        file.close()
        file.close()
    }

    @Test func useAfterCloseThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let file = try WIMFile(path: try Fixture.makeWIM(in: scratch))
        let target = try scratch.makeDirectory("out")
        file.close()

        #expect(throws: WIMLibError.closed) { try file.images }
        #expect(throws: WIMLibError.closed) { try file.property("NAME", ofImage: 1) }
        #expect(throws: WIMLibError.closed) {
            try file.extract(paths: ["/dir/a.bin"], fromImage: 1, to: target)
        }
    }

    /// Images are copies and stay valid after the file is closed.
    @Test func imagesOutliveTheFile() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let file = try WIMFile(path: try Fixture.makeWIM(in: scratch, properties: ["WINDOWS/VERSION/BUILD": "26200"]))
        let images = try file.images
        file.close()
        #expect(images.first?.name == Fixture.imageName)
        #expect(images.first?.build == 26200)
    }

    @Test func openEmptyFileThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let path = scratch.path("empty.wim")
        try Data().write(to: URL(fileURLWithPath: path))
        let error = #expect(throws: WIMLibError.self) { try WIMFile(path: path) }
        #expect(error?.wimlibCode != nil)
    }

    @Test func openGarbageThrowsNotAWIMFile() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let path = scratch.path("garbage.wim")
        try Data(randomBytes(count: 4096, seed: 3)).write(to: URL(fileURLWithPath: path))
        let error = #expect(throws: WIMLibError.self) { try WIMFile(path: path) }
        #expect(error?.wimlibCode == code(WIMLIB_ERR_NOT_A_WIM_FILE))
    }

    @Test func openMissingFileThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let error = #expect(throws: WIMLibError.self) { try WIMFile(path: scratch.path("missing.wim")) }
        #expect(error?.wimlibCode == code(WIMLIB_ERR_OPEN))
    }

    @Test func createFromMissingDirectoryThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        #expect(throws: WIMLibError.self) {
            try WIMFile.create(from: scratch.url("missing"), to: scratch.path("out.wim"), imageName: "x")
        }
        #expect(!FileManager.default.fileExists(atPath: scratch.path("out.wim")))
    }

    @Test func errorsDescribeThemselves() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let error = #expect(throws: WIMLibError.self) { try WIMFile(path: scratch.path("missing.wim")) }
        guard case .wimlib(_, let message) = error else {
            Issue.record("expected a wimlib error")
            return
        }
        #expect(!message.isEmpty)
        #expect(error?.description.contains(message) == true)
    }

    /// Checks that nothing global in wimlib wears out: the same process creates, opens and
    /// extracts from a WIM twenty times.
    @Test func repeatedCreateOpenExtract() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let source = scratch.url("source")
        try Fixture.makeTree(at: source)

        for round in 0..<20 {
            let path = scratch.path("round-\(round).wim")
            try WIMFile.create(from: source, to: path, imageName: "Round \(round)")
            let file = try WIMFile(path: path)
            defer { file.close() }
            #expect(try file.images.map(\.name) == ["Round \(round)"])
            let target = try scratch.makeDirectory("out-\(round)")
            try file.extract(paths: ["/dir/a.bin"], fromImage: 1, to: target)
            #expect(try contents(of: target.appendingPathComponent("a.bin")) == Fixture.bytes(of: "a.bin"))
        }
    }
}
