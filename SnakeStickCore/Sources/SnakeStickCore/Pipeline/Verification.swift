// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import NTFS3G
import SlopDisk

/// Step 8 (P12, §10).
enum Verification {
    /// Reads the table back through a read-only open: a healthy GPT whose two partitions are
    /// the ones step 3 wrote.
    static func checkPartitionTable(device: String, expected: PartitionTable) throws {
        let actual: [SDPartition]
        do {
            let disk = try SDDisk(device: try SDRawDevice(readOnlyPath: device))
            guard disk.scheme == .gpt(.healthy) else {
                throw failure("The partition table on \(device) is not a healthy GPT (\(disk.scheme)).", path: device)
            }
            actual = disk.partitions
        }
        let wanted = [expected.ntfs, expected.fat]
        guard actual.count == wanted.count,
              zip(actual.sorted { $0.index < $1.index }, wanted).allSatisfy({ $0.type == $1.type && $0.begin == $1.begin && $0.end == $1.end && $0.index == $1.index })
        else {
            let found = actual.map { "#\($0.index) \($0.type) \($0.begin)-\($0.end)" }.joined(separator: ", ")
            throw failure("The partition table on \(device) differs from what was written: \(found).", path: device)
        }
    }

    /// Compares the NTFS volume with the ISO tree: the same names in every directory, the same
    /// kinds and sizes, and the same bytes. `overrides` maps NTFS paths to the files whose
    /// content they must have instead (the CA 2023 boot loaders); the ones not on the ISO are
    /// expected as additional files.
    static func compareTree(
        volume: NTFSVolume,
        isoRoot: URL,
        overrides: [String: URL],
        cancellation: CancellationFlag,
        progress: (_ done: Int64, _ total: Int64, _ path: String) -> Void
    ) throws {
        try withoutActuallyEscaping(progress) { progress in
            let comparer = TreeComparer(volume: volume, overrides: overrides, cancellation: cancellation, progress: progress)
            comparer.total = try comparer.expectedBytes(host: isoRoot, path: "")
            try comparer.compareDirectory(host: isoRoot, path: "")
        }
    }

    static func failure(_ message: String, path: String? = nil) -> InstallerError {
        InstallerError(phase: .verify, kind: .verificationFailed, message: message, targetModified: true, path: path)
    }
}

private final class TreeComparer {
    let volume: NTFSVolume
    let overrides: [String: URL]
    let cancellation: CancellationFlag
    let progress: (Int64, Int64, String) -> Void
    var total: Int64 = 0
    var done: Int64 = 0
    static let chunk = 8 << 20
    let volumeBuffer = UnsafeMutableRawBufferPointer.allocate(byteCount: TreeComparer.chunk, alignment: 16)

    init(volume: NTFSVolume, overrides: [String: URL], cancellation: CancellationFlag, progress: @escaping (Int64, Int64, String) -> Void) {
        self.volume = volume
        self.overrides = overrides
        self.cancellation = cancellation
        self.progress = progress
    }

    deinit {
        volumeBuffer.deallocate()
    }

    /// Host entries of `host` by NFC name, plus the added override files that belong to `path`.
    func expectedEntries(host: URL, path: String) throws -> [String: (url: URL, isDirectory: Bool)] {
        var entries: [String: (URL, Bool)] = [:]
        let urls = try FileManager.default.contentsOfDirectory(at: host, includingPropertiesForKeys: [.isDirectoryKey])
        for url in urls {
            let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
            entries[url.lastPathComponent.precomposedStringWithCanonicalMapping] = (url, isDirectory)
        }
        for (overridePath, source) in overrides {
            let parent = (overridePath as NSString).deletingLastPathComponent
            let name = (overridePath as NSString).lastPathComponent
            if parent == (path.isEmpty ? "/" : path), entries[name] == nil {
                entries[name] = (source, false)
            }
        }
        return entries
    }

    func expectedBytes(host: URL, path: String) throws -> Int64 {
        var bytes: Int64 = 0
        for (name, entry) in try expectedEntries(host: host, path: path) {
            let childPath = path + "/" + name
            if entry.isDirectory {
                bytes += try expectedBytes(host: entry.url, path: childPath)
            } else {
                let file = overrides[childPath] ?? entry.url
                bytes += Int64((try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0)
            }
        }
        return bytes
    }

    func compareDirectory(host: URL, path: String) throws {
        try cancellation.check()
        let expected = try expectedEntries(host: host, path: path)
        let actual = try volume.contentsOfDirectory(path.isEmpty ? "/" : path)
        let actualNames = Dictionary(actual.map { ($0.name, $0.kind) }, uniquingKeysWith: { first, _ in first })
        if let missing = expected.keys.sorted().first(where: { actualNames[$0] == nil }) {
            throw Verification.failure("\(path)/\(missing) is missing on the NTFS volume.", path: "\(path)/\(missing)")
        }
        if let extra = actualNames.keys.sorted().first(where: { expected[$0] == nil }) {
            throw Verification.failure("\(path)/\(extra) is on the NTFS volume but not on the ISO.", path: "\(path)/\(extra)")
        }
        for name in expected.keys.sorted() {
            let entry = expected[name]!
            let childPath = path + "/" + name
            let kind = actualNames[name]!
            guard (kind == .directory) == entry.isDirectory else {
                throw Verification.failure("\(childPath) is a \(kind == .directory ? "directory" : "file") on the NTFS volume but not on the ISO.", path: childPath)
            }
            if entry.isDirectory {
                try compareDirectory(host: entry.url, path: childPath)
            } else {
                try compareFile(host: overrides[childPath] ?? entry.url, path: childPath)
            }
        }
    }

    func compareFile(host: URL, path: String) throws {
        let hostSize = (try FileManager.default.attributesOfItem(atPath: host.path)[.size] as? NSNumber)?.int64Value ?? -1
        let volumeSize = try volume.attributesOfItem(path).size
        guard hostSize == volumeSize else {
            throw Verification.failure("\(path) has \(volumeSize) bytes on the NTFS volume, \(hostSize) on the ISO.", path: path)
        }
        let handle = try FileHandle(forReadingFrom: host)
        defer { try? handle.close() }
        var offset: Int64 = 0
        progress(done, total, path)
        while offset < hostSize {
            try cancellation.check()
            let wanted = Int(min(Int64(TreeComparer.chunk), hostSize - offset))
            let hostData = try handle.read(upToCount: wanted) ?? Data()
            let count = try volume.readFile(path, into: UnsafeMutableRawBufferPointer(rebasing: volumeBuffer[0 ..< wanted]), at: offset)
            guard hostData.count == wanted, count == wanted else {
                throw Verification.failure("\(path) could not be read completely.", path: path)
            }
            let same = hostData.withUnsafeBytes { memcmp($0.baseAddress!, volumeBuffer.baseAddress!, wanted) == 0 }
            guard same else {
                throw Verification.failure("\(path) differs between the NTFS volume and the ISO near byte \(offset).", path: path)
            }
            offset += Int64(wanted)
            done += Int64(wanted)
            progress(done, total, path)
        }
    }
}
