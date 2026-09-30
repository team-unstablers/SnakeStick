// SPDX-License-Identifier: GPL-2.0-or-later

internal import CNTFS3G
import Foundation

extension NTFSVolume {
    /// Copies the contents of the host directory `source` into the existing directory
    /// `destination`, like `cp -R source/. destination`.
    ///
    /// The whole source tree is scanned first (with lstat(2), never following symbolic links)
    /// to find the total size, then copied in name order. A symbolic link, FIFO, socket or
    /// device anywhere in the tree, or a name that Windows cannot use, is reported before
    /// anything is written. Other errors stop the copy and leave what was already copied in
    /// place. Names are stored in Unicode NFC, like every name this type writes.
    ///
    /// Each file and directory gets the host item's times: creation from the birth time,
    /// modification and access from the modification time (the host access time is not used,
    /// since reading the source changes it). A directory's times are set after its contents
    /// are copied. The times of `destination` itself are left alone.
    ///
    /// `progress` is called after each chunk of file data, and once for each empty file.
    public func copyTree(
        from source: URL,
        to destination: String = "/",
        progress: ((NTFSCopyProgress) throws -> Void)? = nil
    ) throws -> NTFSCopySummary {
        let volume = try requireWritableVolume()
        let destinationPath = try NTFSPath(destination)
        let items = try SourceTree.scan(source)

        var totalBytes: Int64 = 0
        try Self.validate(items, under: destinationPath, in: volume, totalBytes: &totalBytes)

        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: Self.copyChunkSize, alignment: 16)
        defer { buffer.deallocate() }
        var copier = TreeCopier(totalBytes: totalBytes, buffer: buffer, progress: progress)
        try withDirectory(destinationPath, in: volume) { directory in
            try copy(items, into: directory, at: destinationPath, copier: &copier)
        }
        return copier.summary
    }

    /// Checks names and times before anything is written, and adds up the file sizes.
    private static func validate(
        _ items: [SourceItem],
        under parent: NTFSPath,
        in volume: UnsafeMutablePointer<ntfs_volume>,
        totalBytes: inout Int64
    ) throws {
        for item in items {
            let path = parent.appending(item.name)
            let name = try NTFSName(path.name!)
            guard !ntfs_forbidden_names(volume, name.characters, Int32(name.length), .true).isTrue else {
                throw NTFS3GError.invalidName(path.name!)
            }
            _ = try item.ticks(path: path)
            switch item.kind {
            case .file(let size):
                totalBytes += size
            case .directory(let children):
                try validate(children, under: path, in: volume, totalBytes: &totalBytes)
            }
        }
    }

    private func copy(_ items: [SourceItem], into directory: Inode, at directoryPath: NTFSPath, copier: inout TreeCopier) throws {
        for item in items {
            let path = directoryPath.appending(item.name)
            let ticks = try item.ticks(path: path)
            switch item.kind {
            case .file:
                let file = try HostFile(path: item.path, followSymlinks: false)
                defer { file.close() }
                try createItem(path, kind: .file, in: directory, times: ticks) { inode in
                    let base = copier.summary.bytes
                    let written = try writeData(to: inode, path: path, from: file, buffer: copier.buffer) { written in
                        try copier.progress?(NTFSCopyProgress(
                            completedBytes: base + written,
                            totalBytes: copier.totalBytes,
                            currentPath: path.string
                        ))
                    }
                    copier.summary.bytes += written
                }
                copier.summary.files += 1
            case .directory(let children):
                try createItem(path, kind: .directory, in: directory, times: ticks) { inode in
                    try copy(children, into: inode, at: path, copier: &copier)
                }
                copier.summary.directories += 1
            }
        }
    }
}

private struct TreeCopier {
    let totalBytes: Int64
    let buffer: UnsafeMutableRawBufferPointer
    let progress: ((NTFSCopyProgress) throws -> Void)?
    var summary = NTFSCopySummary(files: 0, directories: 0, bytes: 0)

    init(totalBytes: Int64, buffer: UnsafeMutableRawBufferPointer, progress: ((NTFSCopyProgress) throws -> Void)?) {
        self.totalBytes = totalBytes
        self.buffer = buffer
        self.progress = progress
    }
}

extension SourceItem {
    /// The host times mapped to NTFS: creation ← birth time, modification and access ←
    /// modification time.
    func ticks(path: NTFSPath) throws(NTFS3GError) -> NTFSTicks {
        guard let creation = NTFSTime.ticks(from: birthTime),
              let modification = NTFSTime.ticks(from: modificationTime)
        else {
            throw .posix(operation: "setTimes", path: path.string, errno: EINVAL)
        }
        return NTFSTicks(creation: creation, modification: modification, access: modification)
    }
}
