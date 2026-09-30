// SPDX-License-Identifier: GPL-2.0-or-later

import CNTFS3G
import Darwin
import Testing

/// Smoke test for the vendored libntfs-3g build: format a scratch image with mkntfs, write a file
/// through libntfs-3g, then remount the image read-only and read the file back.
@Test func formatWriteAndReadBack() throws {
    let image = try ScratchImage(size: 64 << 20)
    defer { image.remove() }

    #expect(mkntfs(["-F", "-Q", "-q", "-L", "SNAKESTICK", image.path]) == 0)

    // Large enough to be stored non-resident, so cluster allocation is exercised.
    let payload = (0..<(3 << 20)).map { UInt8(truncatingIfNeeded: $0 &* 131 &+ 7) }

    do {
        let volume = try #require(ntfs_mount(image.path, ntfs_mount_flags(NTFS_MNT_NONE)))
        defer { #expect(ntfs_umount(volume, BOOL(0)) == 0) }
        let root = try #require(ntfs_pathname_to_inode(volume, nil, "/"))
        defer { ntfs_inode_close(root) }

        var name: UnsafeMutablePointer<ntfschar>?
        let nameLength = ntfs_mbstoucs("payload.bin", &name)
        defer { ntfs_ucsfree(name) }
        try #require(nameLength > 0)

        let file = try #require(ntfs_create(root, 0, name, UInt8(nameLength), S_IFREG))
        defer { ntfs_inode_close(file) }
        let data = try #require(ntfs_attr_open(file, AT_DATA, nil, 0))
        defer { ntfs_attr_close(data) }

        let written = payload.withUnsafeBytes {
            ntfs_attr_pwrite(data, 0, s64($0.count), $0.baseAddress)
        }
        #expect(written == s64(payload.count))
    }

    do {
        let volume = try #require(ntfs_mount(image.path, ntfs_mount_flags(NTFS_MNT_RDONLY)))
        defer { ntfs_umount(volume, BOOL(0)) }
        #expect(String(cString: volume.pointee.vol_name) == "SNAKESTICK")

        let file = try #require(ntfs_pathname_to_inode(volume, nil, "/payload.bin"))
        defer { ntfs_inode_close(file) }
        let data = try #require(ntfs_attr_open(file, AT_DATA, nil, 0))
        defer { ntfs_attr_close(data) }
        #expect(data.pointee.data_size == s64(payload.count))

        var readBack = [UInt8](repeating: 0, count: payload.count)
        let read = readBack.withUnsafeMutableBytes {
            ntfs_attr_pread(data, 0, s64($0.count), $0.baseAddress)
        }
        #expect(read == s64(payload.count))
        let matches = readBack == payload
        #expect(matches)
    }
}

/// Runs mkntfs in-process.
private func mkntfs(_ arguments: [String]) -> Int32 {
    let argv = (["mkntfs"] + arguments).map { strdup($0) }
    defer { argv.forEach { free($0) } }
    var terminatedArgv = argv + [nil]
    return ntfs3g_mkntfs(Int32(argv.count), &terminatedArgv)
}

/// A sparse scratch file under the temporary directory.
private struct ScratchImage {
    let path: String

    init(size: off_t) throws {
        var directory = getenv("TMPDIR").map { String(cString: $0) } ?? "/tmp"
        if !directory.hasSuffix("/") {
            directory += "/"
        }
        var template = Array((directory + "CNTFS3GTests-XXXXXX").utf8CString)
        let fd = mkstemp(&template)
        try #require(fd >= 0)
        defer { close(fd) }
        try #require(ftruncate(fd, size) == 0)
        path = template.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    func remove() {
        unlink(path)
    }
}
