// SPDX-License-Identifier: LGPL-2.1-or-later

import CWIMLib
import Foundation
import Testing
import WIMLib

/// A scratch directory under the temporary directory, removed by `remove()`.
struct ScratchDirectory {
    static let prefix = "WIMLibTests-"

    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.prefix)\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    func url(_ name: String) -> URL {
        url.appendingPathComponent(name)
    }

    func path(_ name: String) -> String {
        url(name).path
    }

    /// Creates an empty directory and returns its URL.
    func makeDirectory(_ name: String) throws -> URL {
        let directory = url(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

/// SplitMix64, so that "random" fixture bytes are the same on every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func randomBytes(count: Int, seed: UInt64) -> [UInt8] {
    var generator = SeededGenerator(seed: seed)
    return (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
}

/// The source tree captured into test WIMs: three files in `/dir`.
enum Fixture {
    static let imageName = "Fixture Image"

    /// File names in `/dir` and their contents.
    static let files: [(name: String, bytes: [UInt8])] = [
        ("a.bin", randomBytes(count: (1 << 20) + 17, seed: 1)),
        ("b.bin", randomBytes(count: 100, seed: 2)),
        ("empty.bin", []),
    ]

    static func bytes(of name: String) -> [UInt8] {
        files.first { $0.name == name }!.bytes
    }

    /// Writes the tree below `root` (which must not exist yet).
    static func makeTree(at root: URL) throws {
        let dir = root.appendingPathComponent("dir", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for file in files {
            try Data(file.bytes).write(to: dir.appendingPathComponent(file.name))
        }
    }

    /// Writes the tree into `scratch` and captures it into `name`. Returns the WIM's path.
    @discardableResult
    static func makeWIM(
        in scratch: ScratchDirectory,
        name: String = "fixture.wim",
        compression: WIMCompression = .lzx,
        properties: [String: String] = [:]
    ) throws -> String {
        let source = scratch.url("source-\(name)")
        if !FileManager.default.fileExists(atPath: source.path) {
            try makeTree(at: source)
        }
        let path = scratch.path(name)
        try WIMFile.create(
            from: source, to: path, compression: compression, imageName: imageName,
            properties: properties)
        return path
    }
}

func contents(of url: URL) throws -> [UInt8] {
    [UInt8](try Data(contentsOf: url))
}

func listing(of url: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
}

extension WIMLibError {
    /// The wimlib error code, if this is a `.wimlib` error.
    var wimlibCode: Int32? {
        if case .wimlib(let code, _) = self {
            return code
        }
        return nil
    }
}

/// `WIMLIB_ERR_*` as the `Int32` that ``WIMLibError/wimlib(code:message:)`` carries.
func code(_ code: wimlib_error_code) -> Int32 {
    Int32(truncatingIfNeeded: code.rawValue)
}
