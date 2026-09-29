//
//  SDFileBlockDevice.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A block device backed by a regular image file.
///
/// The file is `flock`ed for as long as the device is alive: `LOCK_EX` for read-write, `LOCK_SH` for read-only.
/// Paths that are not regular files (for example `/dev/disk4`) are rejected with `.invalidArgument`,
/// so a real disk cannot be opened through this type by accident.
public final class SDFileBlockDevice: SDBlockDevice {
    public let path: String
    public let sectorSize: Int
    public let sectorCount: UInt64
    public let isReadOnly: Bool
    private let fd: Int32

    /// Creates a new sparse image file of `byteCount` bytes and opens it read-write.
    ///
    /// Throws `.fileExists` if `path` already exists; the existing file is left untouched.
    public static func create(path: String, byteCount: UInt64, sectorSize: Int) throws(SDError) -> SDFileBlockDevice {
        try validate(sectorSize: sectorSize)
        guard byteCount <= UInt64(Int64.max) else {
            throw .invalidArgument("image size \(byteCount) exceeds off_t")
        }
        let fd = open(path, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
        guard fd >= 0 else {
            let code = errno
            if code == EEXIST {
                throw .fileExists(path: path)
            }
            throw .io(operation: "open", errno: code)
        }
        do throws(SDError) {
            try lock(fd: fd, mode: .readWrite, path: path)
            guard ftruncate(fd, off_t(byteCount)) == 0 else {
                throw .io(operation: "ftruncate", errno: errno)
            }
        } catch {
            // The file was created by this call (O_EXCL), so removing it cannot touch anyone else's data.
            close(fd)
            unlink(path)
            throw error
        }
        return SDFileBlockDevice(
            path: path, fd: fd, sectorSize: sectorSize,
            sectorCount: byteCount / UInt64(sectorSize), isReadOnly: false
        )
    }

    /// Opens an existing image file. `sectorCount` is the file size divided by `sectorSize`; trailing bytes are ignored.
    public init(path: String, mode: SDOpenMode, sectorSize: Int) throws(SDError) {
        try Self.validate(sectorSize: sectorSize)
        let flags = (mode == .readOnly ? O_RDONLY : O_RDWR) | O_CLOEXEC
        let fd = open(path, flags)
        guard fd >= 0 else {
            throw .io(operation: "open", errno: errno)
        }
        let size: UInt64
        do throws(SDError) {
            var info = stat()
            guard fstat(fd, &info) == 0 else {
                throw .io(operation: "fstat", errno: errno)
            }
            guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
                throw .invalidArgument("\(path) is not a regular file; SDFileBlockDevice only opens image files")
            }
            try Self.lock(fd: fd, mode: mode, path: path)
            size = UInt64(info.st_size)
        } catch {
            close(fd)
            throw error
        }
        self.path = path
        self.fd = fd
        self.sectorSize = sectorSize
        self.sectorCount = size / UInt64(sectorSize)
        self.isReadOnly = mode == .readOnly
    }

    private init(path: String, fd: Int32, sectorSize: Int, sectorCount: UInt64, isReadOnly: Bool) {
        self.path = path
        self.fd = fd
        self.sectorSize = sectorSize
        self.sectorCount = sectorCount
        self.isReadOnly = isReadOnly
    }

    deinit {
        // Closing the descriptor also releases the flock.
        close(fd)
    }

    public func read(lba: UInt64, into buffer: UnsafeMutableRawBufferPointer) throws(SDError) {
        try validateRequest(lba: lba, byteCount: buffer.count)
        try POSIXIO.readAll(fd: fd, into: buffer, offset: lba * UInt64(sectorSize))
    }

    public func write(lba: UInt64, from buffer: UnsafeRawBufferPointer) throws(SDError) {
        guard !isReadOnly else {
            throw .readOnly
        }
        try validateRequest(lba: lba, byteCount: buffer.count)
        try POSIXIO.writeAll(fd: fd, from: buffer, offset: lba * UInt64(sectorSize))
    }

    public func synchronize() throws(SDError) {
        #if canImport(Darwin)
        // F_FULLFSYNC asks the drive to flush its cache as well. Some file systems do not support it.
        if fcntl(fd, F_FULLFSYNC) == 0 {
            return
        }
        #endif
        guard fsync(fd) == 0 else {
            throw .io(operation: "fsync", errno: errno)
        }
    }

    private static func validate(sectorSize: Int) throws(SDError) {
        guard SDBlockRequest.isSupported(sectorSize: sectorSize) else {
            throw .invalidArgument("unsupported sector size \(sectorSize)")
        }
    }

    /// `flock` works per open file description, so two opens in the same process conflict as well.
    private static func lock(fd: Int32, mode: SDOpenMode, path: String) throws(SDError) {
        let operation = (mode == .readOnly ? LOCK_SH : LOCK_EX) | LOCK_NB
        while flock(fd, operation) != 0 {
            let code = errno
            if code == EINTR {
                continue
            }
            if code == EWOULDBLOCK || code == EAGAIN {
                throw .locked(path: path)
            }
            throw .io(operation: "flock", errno: code)
        }
    }
}
