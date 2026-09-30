// SPDX-License-Identifier: LGPL-2.1-or-later

import CWIMLib
import Foundation
import Testing
import WIMLib

@Suite struct ExtractTests {
    /// A file is placed directly in the target, without the directories above it.
    @Test(arguments: Fixture.files.map(\.name))
    func extractFile(name: String) throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let file = try WIMFile(path: try Fixture.makeWIM(in: scratch))
        defer { file.close() }

        let target = try scratch.makeDirectory("out")
        try file.extract(paths: ["/dir/\(name)"], fromImage: 1, to: target)
        #expect(try listing(of: target) == [name])
        #expect(try contents(of: target.appendingPathComponent(name)) == Fixture.bytes(of: name))
    }

    /// A directory is placed in the target as a whole tree, as Rufus expects for
    /// `Windows\Boot\EFI_EX`.
    @Test func extractDirectory() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let file = try WIMFile(path: try Fixture.makeWIM(in: scratch))
        defer { file.close() }

        let target = try scratch.makeDirectory("out")
        try file.extract(paths: ["/dir"], fromImage: 1, to: target)
        #expect(try listing(of: target) == ["dir"])
        let dir = target.appendingPathComponent("dir")
        #expect(try listing(of: dir) == Fixture.files.map(\.name).sorted())
        for (name, bytes) in Fixture.files {
            #expect(try contents(of: dir.appendingPathComponent(name)) == bytes, "\(name)")
        }
    }

    @Test func extractSeveralPaths() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let file = try WIMFile(path: try Fixture.makeWIM(in: scratch))
        defer { file.close() }

        let target = try scratch.makeDirectory("out")
        try file.extract(paths: ["/dir/a.bin", "/dir/b.bin"], fromImage: 1, to: target)
        #expect(try listing(of: target) == ["a.bin", "b.bin"])
    }

    /// Paths are matched ignoring case and may use backslashes or omit the leading separator,
    /// as in Rufus's `Windows\Boot\EFI_EX`. Extracted names keep the case stored in the WIM.
    @Test(arguments: ["/DIR/A.BIN", "\\dir\\a.bin", "Dir\\A.bin", "dir/a.bin"])
    func pathSpellings(path: String) throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let file = try WIMFile(path: try Fixture.makeWIM(in: scratch))
        defer { file.close() }

        let target = try scratch.makeDirectory("out")
        try file.extract(paths: [path], fromImage: 1, to: target)
        #expect(try listing(of: target) == ["a.bin"])
        #expect(try contents(of: target.appendingPathComponent("a.bin")) == Fixture.bytes(of: "a.bin"))
    }

    /// Extracting again over the same files replaces them.
    @Test func extractReplacesExistingFiles() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let file = try WIMFile(path: try Fixture.makeWIM(in: scratch))
        defer { file.close() }

        let target = try scratch.makeDirectory("out")
        try Data("stale".utf8).write(to: target.appendingPathComponent("a.bin"))
        try file.extract(paths: ["/dir/a.bin"], fromImage: 1, to: target)
        try file.extract(paths: ["/dir/a.bin"], fromImage: 1, to: target)
        #expect(try contents(of: target.appendingPathComponent("a.bin")) == Fixture.bytes(of: "a.bin"))
    }

    @Test func missingPathThrowsAndExtractsNothing() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let file = try WIMFile(path: try Fixture.makeWIM(in: scratch))
        defer { file.close() }

        let target = try scratch.makeDirectory("out")
        let error = #expect(throws: WIMLibError.self) {
            try file.extract(paths: ["/dir/a.bin", "/dir/missing.bin"], fromImage: 1, to: target)
        }
        #expect(error?.wimlibCode == code(WIMLIB_ERR_PATH_DOES_NOT_EXIST))
        #expect(try listing(of: target) == [])
    }

    @Test(arguments: [2, 0, -1, Int.max])
    func missingImageThrows(index: Int) throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let file = try WIMFile(path: try Fixture.makeWIM(in: scratch))
        defer { file.close() }

        let target = try scratch.makeDirectory("out")
        let error = #expect(throws: WIMLibError.self) {
            try file.extract(paths: ["/dir/a.bin"], fromImage: index, to: target)
        }
        #expect(error?.wimlibCode == code(WIMLIB_ERR_INVALID_IMAGE))
    }

    /// wimlib would create a missing target directory; WIMFile requires it to exist.
    @Test func missingTargetDirectoryThrowsENOENT() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let file = try WIMFile(path: try Fixture.makeWIM(in: scratch))
        defer { file.close() }

        let target = scratch.url("missing")
        #expect(throws: WIMLibError.posix(operation: "stat", path: target.path, errno: ENOENT)) {
            try file.extract(paths: ["/dir/a.bin"], fromImage: 1, to: target)
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test func fileAsTargetThrowsENOTDIR() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let path = try Fixture.makeWIM(in: scratch)
        let file = try WIMFile(path: path)
        defer { file.close() }

        #expect(throws: WIMLibError.posix(operation: "extract", path: path, errno: ENOTDIR)) {
            try file.extract(paths: ["/dir/a.bin"], fromImage: 1, to: URL(fileURLWithPath: path))
        }
    }

    @Test func nonFileURLThrowsEINVAL() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let file = try WIMFile(path: try Fixture.makeWIM(in: scratch))
        defer { file.close() }

        let url = try #require(URL(string: "https://example.com/out"))
        #expect(throws: WIMLibError.posix(operation: "extract", path: url.absoluteString, errno: EINVAL)) {
            try file.extract(paths: ["/dir/a.bin"], fromImage: 1, to: url)
        }
    }

    /// C would cut the path at the NUL and extract `/dir` instead.
    @Test func pathWithNULThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let file = try WIMFile(path: try Fixture.makeWIM(in: scratch))
        defer { file.close() }

        let target = try scratch.makeDirectory("out")
        let error = #expect(throws: WIMLibError.self) {
            try file.extract(paths: ["/dir\0/a.bin"], fromImage: 1, to: target)
        }
        #expect(error?.wimlibCode == code(WIMLIB_ERR_INVALID_PARAM))
        #expect(try listing(of: target) == [])
    }
}
