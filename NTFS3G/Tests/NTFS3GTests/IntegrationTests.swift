// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import NTFS3G
import Testing

/// Tests that attach disk images with hdiutil and write several GiB. Run with
/// NTFS3G_INTEGRATION=1.
@Suite(
    .enabled(if: ProcessInfo.processInfo.environment["NTFS3G_INTEGRATION"] == "1", "set NTFS3G_INTEGRATION=1"),
    .serialized
)
struct IntegrationTests {
    /// Reads an image written by copyTree through macOS's own NTFS driver (FSKit) and compares
    /// the tree with the source.
    @Test func fskitReadsCopiedTree() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let source = scratch.url.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try Fixtures.makeStandardTree(at: source)
        let image = try scratch.makeVolume(options: .init(label: "FSKITTEST"))
        do {
            let volume = try NTFSVolume(path: image, mode: .readWrite)
            _ = try volume.copyTree(from: source)
            try volume.close()
        }

        try withFSKitMount(image: image, scratch: scratch) { mountPoint in
            // FSKit returns every name decomposed (NFD) from readdir, whatever is stored, so
            // names are compared in NFC. hostTree opens every item through the mount, which
            // fails for names stored in NFD; copyTree stores NFC.
            let expected = try hostTree(source.path).withNFCPaths
            let actual = try hostTree(mountPoint).withNFCPaths
            #expect(actual.map(\.description) == expected.map(\.description))
            #expect(actual == expected)
        }
    }

    /// Writes a file larger than 4 GiB, the FAT32 limit that this package exists to avoid, and
    /// checks its size and the bytes on both sides of the 4 GiB boundary.
    @Test func fileLargerThan4GiB() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let sourceDirectory = scratch.url.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: false)
        let size: Int64 = (4 << 30) + (1 << 20)
        let source = try scratch.makeSparseFile("source/install.wim", size: size)
        let markers: [(offset: Int64, byte: UInt8)] = [
            (0, 0x11), ((4 << 30) - 2, 0x22), ((4 << 30) - 1, 0x33), (4 << 30, 0x44), ((4 << 30) + 1, 0x55), (size - 1, 0x66),
        ]
        do {
            let fd = open(source, O_WRONLY)
            try #require(fd >= 0)
            defer { close(fd) }
            for marker in markers {
                var byte = marker.byte
                try #require(pwrite(fd, &byte, 1, off_t(marker.offset)) == 1)
            }
        }

        let estimate = try NTFSVolume.estimatedVolumeSize(forTreeAt: sourceDirectory)
        let image = try scratch.makeVolume(size: estimate)
        do {
            let volume = try NTFSVolume(path: image, mode: .readWrite)
            try volume.createDirectory("/sources")
            var last: Int64 = 0
            try volume.writeFile("/sources/install.wim", from: URL(fileURLWithPath: source)) { last = $0 }
            #expect(last == size)
            try volume.close()
        }
        // The sparse source is no longer needed; free the space before mounting.
        unlink(source)

        do {
            let volume = try NTFSVolume(path: image, mode: .readOnly)
            defer { try? volume.close() }
            #expect(try volume.attributesOfItem("/sources/install.wim").size == size)
            var byte: UInt8 = 0
            for marker in markers {
                let count = try withUnsafeMutableBytes(of: &byte) {
                    try volume.readFile("/sources/install.wim", into: $0, at: marker.offset)
                }
                #expect(count == 1)
                #expect(byte == marker.byte, "offset \(marker.offset)")
            }
            // Zeros between the markers, including across the boundary.
            var window = [UInt8](repeating: 0xFF, count: 4096)
            let count = try window.withUnsafeMutableBytes {
                try volume.readFile("/sources/install.wim", into: $0, at: (4 << 30) - 2048)
            }
            #expect(count == 4096)
            let expected = (0..<4096).map { index -> UInt8 in
                markers.first { $0.offset == (4 << 30) - 2048 + Int64(index) }?.byte ?? 0
            }
            #expect(window == expected)
        }

        try withFSKitMount(image: image, scratch: scratch) { mountPoint in
            let path = mountPoint + "/sources/install.wim"
            var info = stat()
            try #require(stat(path, &info) == 0)
            #expect(Int64(info.st_size) == size)
            let handle = try #require(FileHandle(forReadingAtPath: path))
            defer { try? handle.close() }
            for marker in markers {
                try handle.seek(toOffset: UInt64(marker.offset))
                #expect(try handle.read(upToCount: 1) == Data([marker.byte]), "offset \(marker.offset)")
            }
        }
    }

    /// Removes a file larger than 4 GiB and checks that its clusters are free again, also after
    /// remounting. The name contains "Remove" so that `swift test --filter Remove`, which is
    /// case-sensitive, picks it up together with RemoveTests.
    @Test func fileLargerThan4GiBRemoveFreesSpace() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let sourceDirectory = scratch.url.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: false)
        let size: Int64 = (4 << 30) + (1 << 20)
        let source = try scratch.makeSparseFile("source/install.wim", size: size)
        let image = try scratch.makeVolume(size: try NTFSVolume.estimatedVolumeSize(forTreeAt: sourceDirectory))

        let freeBeforeWrite: Int64
        let freeAfterRemove: Int64
        do {
            let volume = try NTFSVolume(path: image, mode: .readWrite)
            try volume.createDirectory("/sources")
            freeBeforeWrite = volume.freeBytes
            try volume.writeFile("/sources/install.wim", from: URL(fileURLWithPath: source))
            let freeAfterWrite = volume.freeBytes
            let allocated = (size + Int64(volume.clusterSize) - 1) / Int64(volume.clusterSize) * Int64(volume.clusterSize)
            #expect(freeBeforeWrite - freeAfterWrite == allocated)
            try volume.removeItem("/sources/install.wim")
            freeAfterRemove = volume.freeBytes
            #expect(freeAfterRemove - freeAfterWrite == allocated)
            try volume.close()
        }
        unlink(source)

        let volume = try NTFSVolume(path: image, mode: .readOnly)
        defer { try? volume.close() }
        #expect(try volume.contentsOfDirectory("/sources").isEmpty)
        #expect(volume.freeBytes == freeAfterRemove)
        #expect(freeAfterRemove == freeBeforeWrite)
    }
}

/// Attaches `image` without mounting it, mounts it read-only with the FSKit NTFS driver, runs
/// `body` with the mount point, then unmounts and detaches, also when `body` or the mount
/// fails.
func withFSKitMount(image: String, scratch: ScratchDirectory, _ body: (String) throws -> Void) throws {
    let attach = try runTool("/usr/bin/hdiutil", [
        "attach", "-plist", "-nomount", "-noverify", "-imagekey", "diskimage-class=CRawDiskImage", image,
    ])
    try #require(attach.status == 0, "hdiutil attach: \(attach.error)")
    let plist = try PropertyListSerialization.propertyList(from: Data(attach.output.utf8), format: nil) as? [String: Any]
    let entities = try #require(plist?["system-entities"] as? [[String: Any]])
    let device = try #require(entities.compactMap { $0["dev-entry"] as? String }.first)
    defer {
        let detach = try? runTool("/usr/bin/hdiutil", ["detach", device])
        if detach?.status != 0 {
            _ = try? runTool("/usr/bin/hdiutil", ["detach", "-force", device])
        }
        let info = try? runTool("/usr/bin/hdiutil", ["info"])
        #expect(info?.output.contains(image) == false, "\(image) is still attached")
    }

    let mountPoint = scratch.path("mnt")
    try FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: false)
    let mount = try runTool("/usr/sbin/diskutil", ["mount", "readOnly", "-mountPoint", mountPoint, device])
    try #require(mount.status == 0, "diskutil mount: \(mount.output) \(mount.error)")
    defer {
        let unmount = try? runTool("/usr/sbin/diskutil", ["unmount", mountPoint])
        if unmount?.status != 0 {
            _ = try? runTool("/usr/sbin/diskutil", ["unmount", "force", mountPoint])
        }
    }

    // The mount must really be the read-only NTFS driver.
    let mounts = try runTool("/sbin/mount", [])
    let line = mounts.output.split(separator: "\n").first { $0.contains(" on \(mountPoint) ") || $0.contains(" on /private\(mountPoint) ") }
    let mountLine = try #require(line, "\(mountPoint) is not in mount(8) output")
    #expect(mountLine.contains("ntfs"))
    #expect(mountLine.contains("read-only"))

    try body(mountPoint)
}

struct ToolResult {
    var status: Int32
    var output: String
    var error: String
}

func runTool(_ path: String, _ arguments: [String]) throws -> ToolResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    // Read before waiting, so that a full pipe cannot block the tool.
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return ToolResult(
        status: process.terminationStatus,
        output: String(decoding: outputData, as: UTF8.self),
        error: String(decoding: errorData, as: UTF8.self)
    )
}
