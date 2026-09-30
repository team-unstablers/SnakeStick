// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import NTFS3G
import Testing

/// Host directory trees used as copyTree sources.
///
/// Items are created with mkdir(2) and open(2) on paths spelled exactly as written here.
/// Foundation would convert names to decomposed Unicode (a URL's file system representation),
/// and APFS stores whichever form it is given.
enum Fixtures {
    static func makeDirectory(_ path: String) throws {
        try #require(mkdir(path, 0o755) == 0, "mkdir \(path): \(String(cString: strerror(errno)))")
    }

    static func makeFile(_ path: String, _ contents: [UInt8]) throws {
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        try #require(fd >= 0, "open \(path): \(String(cString: strerror(errno)))")
        defer { close(fd) }
        try contents.withUnsafeBytes { bytes in
            var done = 0
            while done < bytes.count {
                let count = write(fd, bytes.baseAddress! + done, bytes.count - done)
                try #require(count > 0)
                done += count
            }
        }
    }

    /// The NFD spelling of a name in the standard tree.
    static let decomposedName = "분해된 이름.txt".decomposedStringWithCanonicalMapping

    /// A small tree with every kind of item: empty and non-empty files and directories, a file
    /// larger than one copy chunk, Korean names in NFC and in NFD, mixed-case names, and fixed
    /// past times on everything (set after the contents, so that they stick).
    static func makeStandardTree(at root: URL) throws {
        let base = root.path + "/"
        try makeFile(base + "a.txt", Array("hello\n".utf8))
        try makeFile(base + "empty.bin", [])
        try makeFile(base + "Big.bin", pattern(count: (9 << 20) + 123, seed: 1))
        try makeDirectory(base + "한글 폴더")
        try makeFile(base + "한글 폴더/한글 파일.txt", Array("안녕하세요".utf8))
        try makeFile(base + "한글 폴더/" + decomposedName, [1, 2, 3])
        try makeDirectory(base + "한글 폴더/nested")
        try makeFile(base + "한글 폴더/nested/deep.txt", pattern(count: 5000, seed: 2))
        try makeDirectory(base + "empty dir")
        try makeDirectory(base + "Z")
        try makeFile(base + "Z/x", [0x78])

        // Deepest first, so that setting a directory's times is the last change to it.
        let paths = [
            "a.txt", "empty.bin", "Big.bin",
            "한글 폴더/한글 파일.txt", "한글 폴더/" + decomposedName,
            "한글 폴더/nested/deep.txt", "한글 폴더/nested", "한글 폴더",
            "empty dir", "Z/x", "Z",
        ]
        for (index, path) in paths.enumerated() {
            try setTimes(base + path, index: index)
        }
    }

    /// Counts of the standard tree.
    static let standardTreeSummary = NTFSCopySummary(
        files: 7,
        directories: 4,
        bytes: 6 + 0 + Int64((9 << 20) + 123) + 15 + 3 + 5000 + 1
    )

    /// Distinct fixed times per item: creation on 2001-01-10 + index hours, modification a
    /// day later. Creation stays before modification, which APFS requires.
    static func setTimes(_ path: String, index: Int) throws {
        let creation = Date(timeIntervalSinceReferenceDate: 777_600 + Double(index) * 3600 + 0.123_456_7)
        let modification = creation.addingTimeInterval(86_400.5)
        try FileManager.default.setAttributes([.creationDate: creation, .modificationDate: modification], ofItemAtPath: path)
    }

    /// Fixtures for the size estimate (D13).
    struct EstimateFixture: CustomTestStringConvertible, Sendable {
        let name: String
        let build: @Sendable (String) throws -> Void

        var testDescription: String {
            name
        }
    }

    static let estimateFixtures: [EstimateFixture] = [
        EstimateFixture(name: "empty directory") { _ in },
        EstimateFixture(name: "5000 files under 4 KiB") { root in
            // Spread over a few directories, plus one large directory.
            for directory in 0..<5 {
                try makeDirectory(root + "/dir\(directory)")
            }
            for index in 0..<5000 {
                let directory = index < 3000 ? "dir0" : "dir\(index % 4 + 1)"
                let size = (index * 7919) % 4096
                try makeFile(root + "/\(directory)/file-\(index).dat", pattern(count: size, seed: UInt8(truncatingIfNeeded: index)))
            }
        },
        EstimateFixture(name: "files of 1 MiB to 64 MiB") { root in
            for (index, size) in [1 << 20, (7 << 20) + 5, (33 << 20) + 4097, 64 << 20].enumerated() {
                try makeFile(root + "/large-\(index).bin", pattern(count: size, seed: UInt8(index)))
            }
        },
        EstimateFixture(name: "directories 20 deep") { root in
            var path = root
            for depth in 0..<20 {
                path += "/level-\(depth)"
                try makeDirectory(path)
                try makeFile(path + "/file.txt", pattern(count: 100 * depth))
            }
        },
        EstimateFixture(name: "Korean names") { root in
            // 80 syllables: 240 UTF-8 bytes (APFS allows 255), 80 UTF-16 code units.
            let longName = String(repeating: "가나다라마바사아", count: 10)
            for directory in ["설치 파일", "문서", longName] {
                try makeDirectory(root + "/" + directory)
                for index in 0..<200 {
                    try makeFile(root + "/\(directory)/\(longName.prefix(78))-\(index)", pattern(count: index * 37))
                }
            }
        },
    ]
}

/// One item of a tree, for comparing a copy with its source.
struct TreeEntry: Equatable, CustomStringConvertible {
    /// The path relative to the tree's root, as UTF-8 bytes so that differences in Unicode
    /// normalization are not hidden by `String`'s `==`.
    var path: [UInt8]
    var kind: NTFSItemKind
    var size: Int64
    var contents: [UInt8]
    var modification: Int64

    var description: String {
        "\(String(decoding: path, as: UTF8.self)) \(kind) size=\(size) mtime=\(modification)"
    }
}

/// The tree under `root` on the host, sorted like NTFSVolume.contentsOfDirectory. Names are
/// read with readdir(3), exactly as the file system returns them.
func hostTree(_ root: String, relativePath: String = "") throws -> [TreeEntry] {
    var entries: [TreeEntry] = []
    for name in try hostDirectoryNames(root).sorted() {
        let path = root + "/" + name
        let relative = relativePath.isEmpty ? name : relativePath + "/" + name
        var info = stat()
        try #require(lstat(path, &info) == 0, "lstat \(path)")
        let modification = ticks(info.st_mtimespec)
        if info.st_mode & S_IFMT == S_IFDIR {
            entries.append(TreeEntry(path: Array(relative.utf8), kind: .directory, size: 0, contents: [], modification: modification))
            entries += try hostTree(path, relativePath: relative)
        } else {
            let contents = try [UInt8](FileHandle(forReadingAtPath: path).map { try $0.readToEnd() ?? Data() } ?? Data())
            entries.append(TreeEntry(path: Array(relative.utf8), kind: .file, size: Int64(info.st_size), contents: contents, modification: modification))
        }
    }
    return entries
}

func hostDirectoryNames(_ path: String) throws -> [String] {
    let directory = try #require(opendir(path), "opendir \(path)")
    defer { closedir(directory) }
    var names: [String] = []
    while let entry = readdir(directory) {
        let length = Int(entry.pointee.d_namlen)
        let name = withUnsafeBytes(of: &entry.pointee.d_name) { String(decoding: $0.prefix(length), as: UTF8.self) }
        if name != "." && name != ".." {
            names.append(name)
        }
    }
    return names
}

/// The tree under `path` on an NTFS volume.
func volumeTree(_ volume: NTFSVolume, _ path: String = "/", relativePath: String = "") throws -> [TreeEntry] {
    var entries: [TreeEntry] = []
    for entry in try volume.contentsOfDirectory(path) {
        let itemPath = path == "/" ? "/" + entry.name : path + "/" + entry.name
        let relative = relativePath.isEmpty ? entry.name : relativePath + "/" + entry.name
        let attributes = try volume.attributesOfItem(itemPath)
        let modification = ticks(attributes.times.modification)
        switch entry.kind {
        case .directory:
            entries.append(TreeEntry(path: Array(relative.utf8), kind: .directory, size: 0, contents: [], modification: modification))
            entries += try volumeTree(volume, itemPath, relativePath: relative)
        case .file:
            entries.append(TreeEntry(path: Array(relative.utf8), kind: .file, size: attributes.size, contents: try volume.readAll(itemPath), modification: modification))
        }
    }
    return entries
}

/// A `timespec` in NTFS's 100 ns units since 2001-01-01, like `ticks(_: Date)`.
func ticks(_ time: timespec) -> Int64 {
    (Int64(time.tv_sec) - 978_307_200) * 10_000_000 + Int64(time.tv_nsec) / 100
}

/// The total size of the regular files under `path`.
func contentBytes(_ path: String) throws -> Int64 {
    var total: Int64 = 0
    for name in try hostDirectoryNames(path) {
        var info = stat()
        try #require(lstat(path + "/" + name, &info) == 0)
        if info.st_mode & S_IFMT == S_IFDIR {
            total += try contentBytes(path + "/" + name)
        } else {
            total += Int64(info.st_size)
        }
    }
    return total
}
