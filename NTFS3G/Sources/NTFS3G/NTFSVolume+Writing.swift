// SPDX-License-Identifier: GPL-2.0-or-later

internal import CNTFS3G
import Foundation

extension NTFSVolume {
    /// File data is copied through a buffer of this size.
    static let copyChunkSize = 8 << 20

    /// Creates the directory `path`. Its parent must exist; intermediate directories are not
    /// created.
    ///
    /// Throws ``NTFS3GError/alreadyExists(_:)`` if the parent already has an item with the
    /// same name, compared ignoring case.
    public func createDirectory(_ path: String, times: NTFSFileTimes? = nil) throws {
        let volume = try requireWritableVolume()
        let target = try NTFSPath(path)
        guard !target.isRoot else {
            throw NTFS3GError.alreadyExists(path)
        }
        let ticks = try times.map { times throws(NTFS3GError) in try NTFSTicks(times, path: target.string) }

        try withDirectory(target.parent, in: volume) { parent in
            try createItem(target, kind: .directory, in: parent, times: ticks) { _ in }
        }
    }

    /// Creates the file `path` with the contents of the host file `source`, read in 8 MiB
    /// chunks. The parent must exist; intermediate directories are not created.
    ///
    /// `progress` receives the number of bytes written so far after each chunk, and once with 0
    /// for an empty file. If it throws, writing stops and the error is rethrown; the partly
    /// written file stays on the volume.
    ///
    /// Throws ``NTFS3GError/alreadyExists(_:)`` if the parent already has an item with the
    /// same name, compared ignoring case.
    public func writeFile(
        _ path: String,
        from source: URL,
        times: NTFSFileTimes? = nil,
        progress: ((Int64) throws -> Void)? = nil
    ) throws {
        let volume = try requireWritableVolume()
        let target = try NTFSPath(path)
        guard !target.isRoot else {
            throw NTFS3GError.alreadyExists(path)
        }
        let ticks = try times.map { times throws(NTFS3GError) in try NTFSTicks(times, path: target.string) }

        let file = try HostFile(opening: source)
        defer { file.close() }
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: Self.copyChunkSize, alignment: 16)
        defer { buffer.deallocate() }

        try withDirectory(target.parent, in: volume) { parent in
            try createItem(target, kind: .file, in: parent, times: ticks) { inode in
                try writeData(to: inode, path: target, from: file, buffer: buffer) { written in
                    try progress?(written)
                }
            }
        }
    }

    /// Creates the file `path` with `contents`. An empty array creates an empty file. Otherwise
    /// the same as ``writeFile(_:from:times:progress:)``.
    public func writeFile(_ path: String, contents: [UInt8], times: NTFSFileTimes? = nil) throws {
        let volume = try requireWritableVolume()
        let target = try NTFSPath(path)
        guard !target.isRoot else {
            throw NTFS3GError.alreadyExists(path)
        }
        let ticks = try times.map { times throws(NTFS3GError) in try NTFSTicks(times, path: target.string) }

        try withDirectory(target.parent, in: volume) { parent in
            try createItem(target, kind: .file, in: parent, times: ticks) { inode in
                guard !contents.isEmpty else {
                    return
                }
                try withDataAttribute(of: inode, path: target) { attribute in
                    try contents.withUnsafeBytes { bytes in
                        try Self.write(bytes, to: attribute, at: 0, path: target)
                    }
                }
            }
        }
    }

    /// Copies `file` into the unnamed data stream of `inode`, calling `progress` with the running
    /// total after each chunk (once with 0 for an empty file). Returns the number of bytes.
    @discardableResult
    func writeData(
        to inode: Inode,
        path: NTFSPath,
        from file: HostFile,
        buffer: UnsafeMutableRawBufferPointer,
        progress: (Int64) throws -> Void
    ) throws -> Int64 {
        try withDataAttribute(of: inode, path: path) { attribute in
            var offset: Int64 = 0
            while true {
                let count = try file.read(into: buffer)
                if count == 0 {
                    break
                }
                try Self.write(UnsafeRawBufferPointer(rebasing: buffer[..<count]), to: attribute, at: offset, path: path)
                offset += Int64(count)
                try progress(offset)
            }
            if offset == 0 {
                try progress(0)
            }
            return offset
        }
    }

    func withDataAttribute<Result>(of inode: Inode, path: NTFSPath, _ body: (UnsafeMutablePointer<ntfs_attr>) throws -> Result) throws -> Result {
        guard let attribute = ntfs_attr_open(inode, AT_DATA, nil, 0) else {
            throw NTFS3GError.posix(operation: "open data", path: path.string, errno: errno)
        }
        defer { ntfs_attr_close(attribute) }
        return try body(attribute)
    }

    /// Writes all of `bytes` at `offset`. ntfs_attr_pwrite may write less than asked.
    static func write(_ bytes: UnsafeRawBufferPointer, to attribute: UnsafeMutablePointer<ntfs_attr>, at offset: Int64, path: NTFSPath) throws {
        var done = 0
        while done < bytes.count {
            let written = ntfs_attr_pwrite(attribute, offset + Int64(done), s64(bytes.count - done), bytes.baseAddress! + done)
            guard written > 0 else {
                throw NTFS3GError.posix(operation: "write", path: path.string, errno: written < 0 ? errno : EIO)
            }
            done += Int(written)
        }
    }
}

/// A regular host file opened for reading.
struct HostFile {
    let descriptor: Int32
    let path: String

    /// Opens `url`, following a symbolic link at the last component.
    init(opening url: URL) throws {
        try self.init(path: try fileSystemPath(url), followSymlinks: true)
    }

    /// Opens `path` as given, byte for byte. (A URL's file system representation is decomposed
    /// Unicode, which differs from the bytes readdir(3) returned on file systems that do not
    /// ignore normalization.)
    ///
    /// Throws `.unsupportedFileType` unless it is a regular file, and `.posix(errno: EISDIR)`
    /// for a directory. With `followSymlinks` false, a symbolic link is unsupported too.
    init(path: String, followSymlinks: Bool) throws {
        // O_NONBLOCK keeps open(2) from waiting for a writer if the path is a FIFO.
        var flags = O_RDONLY | O_NONBLOCK | O_CLOEXEC
        if !followSymlinks {
            flags |= O_NOFOLLOW
        }
        let descriptor = open(path, flags)
        guard descriptor >= 0 else {
            let code = errno
            if code == ELOOP && !followSymlinks {
                throw NTFS3GError.unsupportedFileType(URL(fileURLWithPath: path))
            }
            throw NTFS3GError.posix(operation: "open", path: path, errno: code)
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw NTFS3GError.posix(operation: "stat", path: path, errno: code)
        }
        switch info.st_mode & S_IFMT {
        case S_IFREG:
            break
        case S_IFDIR:
            Darwin.close(descriptor)
            throw NTFS3GError.posix(operation: "open", path: path, errno: EISDIR)
        default:
            Darwin.close(descriptor)
            throw NTFS3GError.unsupportedFileType(URL(fileURLWithPath: path))
        }
        _ = fcntl(descriptor, F_SETFL, O_RDONLY)
        self.descriptor = descriptor
        self.path = path
    }

    /// Reads up to `buffer.count` bytes. Returns 0 at end of file.
    func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        while true {
            let count = Darwin.read(descriptor, buffer.baseAddress, buffer.count)
            if count >= 0 {
                return count
            }
            if errno != EINTR {
                throw NTFS3GError.posix(operation: "read", path: path, errno: errno)
            }
        }
    }

    func close() {
        Darwin.close(descriptor)
    }
}

/// The path of a file URL. Throws `.posix(errno: EINVAL)` for other URLs, whose file system
/// representation would otherwise be their path component (`/a` for `https://host/a`).
func fileSystemPath(_ url: URL) throws(NTFS3GError) -> String {
    guard url.isFileURL, let path = url.withUnsafeFileSystemRepresentation({ $0.map { String(cString: $0) } }) else {
        throw .posix(operation: "open", path: url.absoluteString, errno: EINVAL)
    }
    return path
}
