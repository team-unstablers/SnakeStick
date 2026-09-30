// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import NTFS3G
import Testing

/// A scratch directory under the temporary directory, removed by `remove()`.
struct ScratchDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NTFS3GTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    func path(_ name: String) -> String {
        url.appendingPathComponent(name).path
    }

    /// Creates a sparse file of `size` bytes.
    @discardableResult
    func makeSparseFile(_ name: String, size: Int64) throws -> String {
        let path = path(name)
        let fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0o644)
        try #require(fd >= 0)
        defer { close(fd) }
        try #require(ftruncate(fd, off_t(size)) == 0)
        return path
    }

    /// Creates a sparse file of `size` bytes and formats it.
    @discardableResult
    func makeVolume(_ name: String = "volume.img", size: Int64 = 64 << 20, options: NTFSFormatOptions = .init()) throws -> String {
        let path = try makeSparseFile(name, size: size)
        try NTFSVolume.format(path: path, options: options)
        return path
    }
}

/// Runs `body` with a fresh 64 MiB volume mounted read-write, then closes it. Returns the image
/// path so that the test can remount it.
func withScratchVolume(
    size: Int64 = 64 << 20,
    _ body: (NTFSVolume, ScratchDirectory) throws -> Void
) throws {
    let scratch = try ScratchDirectory()
    defer { scratch.remove() }
    let image = try scratch.makeVolume(size: size)
    let volume = try NTFSVolume(path: image, mode: .readWrite)
    try body(volume, scratch)
    try volume.close()
}

/// A deterministic byte pattern.
func pattern(count: Int, seed: UInt8 = 0) -> [UInt8] {
    (0..<count).map { UInt8(truncatingIfNeeded: $0 &* 131 &+ Int(seed) &+ ($0 >> 16)) }
}

extension NTFSVolume {
    /// Reads a whole file through readFile in 1 MiB steps.
    func readAll(_ path: String) throws -> [UInt8] {
        let size = try attributesOfItem(path).size
        var result = [UInt8](repeating: 0, count: Int(size))
        var offset: Int64 = 0
        try result.withUnsafeMutableBytes { bytes in
            while offset < size {
                let chunk = UnsafeMutableRawBufferPointer(rebasing: bytes[Int(offset)..<min(Int(offset) + (1 << 20), Int(size))])
                let count = try readFile(path, into: chunk, at: offset)
                try #require(count > 0)
                offset += Int64(count)
            }
        }
        return result
    }
}

/// A fixed time in the past, so that a time that was not set (and is therefore "now") can
/// never compare equal. The fractional part is a multiple of 100 ns.
let fixedTimes = NTFSFileTimes(
    creation: Date(timeIntervalSinceReferenceDate: 2_937_600.123_456_7),      // 2001-02-04
    modification: Date(timeIntervalSinceReferenceDate: 2_851_200.765_432_1),  // 2001-02-03
    access: Date(timeIntervalSinceReferenceDate: 2_764_800.5)                 // 2001-02-02
)

/// `date` in NTFS's 100 ns units, for comparing times at NTFS precision.
func ticks(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSinceReferenceDate * 1e7).rounded())
}

func ticks(_ times: NTFSFileTimes) -> [Int64] {
    [ticks(times.creation), ticks(times.modification), ticks(times.access)]
}

/// Whether two strings have exactly the same UTF-8 bytes. `==` on `String` ignores differences
/// in Unicode normalization.
func sameBytes(_ a: String, _ b: String) -> Bool {
    Array(a.utf8) == Array(b.utf8)
}
