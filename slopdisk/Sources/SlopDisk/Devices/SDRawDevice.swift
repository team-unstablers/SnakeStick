//
//  SDRawDevice.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
internal import CSlopDiskShim

/// A block device backed by a disk device node, such as `/dev/rdisk4` on macOS or `/dev/sdb` on Linux.
///
/// **Writing through this type destroys data on a real disk.** `SDRawDevice` does not check which disk it is
/// given, does not unmount anything, and does not acquire privileges; all of that is the caller's job.
/// Every read-write open requires the explicit `acknowledging: .dataLossRisk` token.
///
/// - Only character and block devices are accepted. Regular files throw `.invalidArgument`; use `SDFileBlockDevice`.
/// - The sector size and count are read once, at open, with ioctls: `DKIOCGETBLOCKSIZE` / `DKIOCGETBLOCKCOUNT` on
///   macOS, `BLKSSZGET` / `BLKGETSIZE64` on Linux. Only 512 and 4096 byte sectors are accepted.
/// - Devices this type opens itself (by path, or an injected descriptor with `closeOnDeinit: true`) are `flock`ed
///   like image files: exclusive for read-write, shared for read-only. The lock only coordinates SlopDisk opens of
///   the same device node; on macOS, `/dev/diskN` and `/dev/rdiskN` are separate nodes and do not share it.
/// - On macOS, prefer `/dev/rdiskN` (raw, unbuffered) over `/dev/diskN` (buffered). Both are accepted.
/// - I/O goes through an internal buffer aligned to the sector size and the page size, at most 1 MiB at a time,
///   because raw devices reject misaligned transfers.
public final class SDRawDevice: SDBlockDevice {
    /// The token every read-write open requires. It has a single value, so all call sites can be found with grep.
    public enum Acknowledgement: Sendable {
        /// Writing to the device destroys whatever it currently holds.
        case dataLossRisk
    }

    /// The path the device was opened from, or `nil` for an injected file descriptor.
    public let path: String?
    public let sectorSize: Int
    public let sectorCount: UInt64
    public let isReadOnly: Bool

    private let fd: Int32
    private let ownsDescriptor: Bool
    private let isBlockDevice: Bool
    private let bounce: UnsafeMutableRawBufferPointer

    private static let bounceByteCount = 1 << 20

    /// Opens a device node read-write.
    ///
    /// The caller is responsible for choosing the right device, for the privileges needed to open it, and for
    /// unmounting every file system on it first. Writing to a disk with mounted partitions corrupts them silently.
    public convenience init(path: String, acknowledging _: Acknowledgement) throws(SDError) {
        try self.init(setup: Self.openDevice(path: path, mode: .readWrite))
    }

    /// Opens a device node read-only. No acknowledgement is needed, since nothing can be written.
    public convenience init(readOnlyPath path: String) throws(SDError) {
        try self.init(setup: Self.openDevice(path: path, mode: .readOnly))
    }

    /// Wraps a descriptor that is already open, for example one received from a privileged helper.
    ///
    /// The access mode of the descriptor (`O_RDONLY` or `O_RDWR`) decides `isReadOnly`; write-only descriptors are
    /// rejected because SlopDisk reads back what it writes.
    ///
    /// - `closeOnDeinit: true`: the device takes ownership. It `flock`s the descriptor and closes it on deinit.
    /// - `closeOnDeinit: false`: the descriptor is borrowed. It is neither locked nor closed; `flock` belongs to the
    ///   open file description, so a lock taken here would outlive this object on the caller's descriptor.
    ///   Locking is then the caller's job.
    ///
    /// If the initializer throws, the descriptor is left open and unlocked whatever `closeOnDeinit` says, and the
    /// caller still owns it. (Closing it here as well would turn a caller's cleanup into a double close.)
    public convenience init(fileDescriptor fd: Int32, closeOnDeinit: Bool, acknowledging _: Acknowledgement) throws(SDError) {
        try self.init(setup: Self.adopt(fd: fd, ownsDescriptor: closeOnDeinit))
    }

    private init(setup: Setup) {
        self.path = setup.path
        self.fd = setup.fd
        self.ownsDescriptor = setup.ownsDescriptor
        self.isBlockDevice = setup.isBlockDevice
        self.sectorSize = setup.sectorSize
        self.sectorCount = setup.sectorCount
        self.isReadOnly = setup.isReadOnly
        self.bounce = setup.bounce
    }

    deinit {
        // Allocated with posix_memalign.
        free(bounce.baseAddress)
        if ownsDescriptor {
            // Closing the descriptor also releases the flock.
            close(fd)
        }
    }

    public func read(lba: UInt64, into buffer: UnsafeMutableRawBufferPointer) throws(SDError) {
        try validateRequest(lba: lba, byteCount: buffer.count)
        let offset = lba * UInt64(sectorSize)
        var done = 0
        while done < buffer.count {
            // bounce.count is a multiple of 4096 and buffer.count of sectorSize, so every chunk is whole sectors.
            let count = min(bounce.count, buffer.count - done)
            try POSIXIO.readAll(fd: fd, into: UnsafeMutableRawBufferPointer(rebasing: bounce[0 ..< count]), offset: offset + UInt64(done))
            UnsafeMutableRawBufferPointer(rebasing: buffer[done ..< done + count])
                .copyMemory(from: UnsafeRawBufferPointer(rebasing: bounce[0 ..< count]))
            done += count
        }
    }

    public func write(lba: UInt64, from buffer: UnsafeRawBufferPointer) throws(SDError) {
        guard !isReadOnly else {
            throw .readOnly
        }
        try validateRequest(lba: lba, byteCount: buffer.count)
        let offset = lba * UInt64(sectorSize)
        var done = 0
        while done < buffer.count {
            let count = min(bounce.count, buffer.count - done)
            UnsafeMutableRawBufferPointer(rebasing: bounce[0 ..< count])
                .copyMemory(from: UnsafeRawBufferPointer(rebasing: buffer[done ..< done + count]))
            try POSIXIO.writeAll(fd: fd, from: UnsafeRawBufferPointer(rebasing: bounce[0 ..< count]), offset: offset + UInt64(done))
            done += count
        }
    }

    /// Flushes the device's write cache. Falls back to `fsync` where the cache ioctl is not supported.
    public func synchronize() throws(SDError) {
        #if canImport(Darwin)
        if isBlockDevice {
            // /dev/diskN goes through the buffer cache, and DKIOCSYNCHRONIZECACHE only flushes the drive's cache.
            // fsync writes the dirty buffers first. (On /dev/rdiskN there is no buffer cache.)
            guard fsync(fd) == 0 else {
                throw .io(operation: "fsync", errno: errno)
            }
        }
        #endif
        let code = sd_synchronize_cache(fd)
        if code == 0 {
            return
        }
        guard code == ENOTTY || code == ENOTSUP || code == EOPNOTSUPP else {
            throw .io(operation: Operation.synchronizeCache, errno: code)
        }
        guard fsync(fd) == 0 else {
            throw .io(operation: "fsync", errno: errno)
        }
    }

    // MARK: - Opening

    private struct Setup {
        var fd: Int32
        var path: String?
        var ownsDescriptor: Bool
        var isReadOnly: Bool
        var isBlockDevice: Bool
        var sectorSize: Int
        var sectorCount: UInt64
        var bounce: UnsafeMutableRawBufferPointer
    }

    /// Names used in `.io(operation:errno:)` for the shim calls.
    private enum Operation {
        #if canImport(Darwin)
        static let blockSize = "ioctl(DKIOCGETBLOCKSIZE)"
        static let blockCount = "ioctl(DKIOCGETBLOCKCOUNT)"
        static let synchronizeCache = "ioctl(DKIOCSYNCHRONIZECACHE)"
        #else
        static let blockSize = "ioctl(BLKSSZGET)"
        static let blockCount = "ioctl(BLKGETSIZE64)"
        static let synchronizeCache = "fsync"
        #endif
    }

    private static func openDevice(path: String, mode: SDOpenMode) throws(SDError) -> Setup {
        let fd = open(path, (mode == .readOnly ? O_RDONLY : O_RDWR) | O_CLOEXEC)
        guard fd >= 0 else {
            throw .io(operation: "open", errno: errno)
        }
        do throws(SDError) {
            return try setUp(fd: fd, path: path, mode: mode, ownsDescriptor: true)
        } catch {
            close(fd)
            throw error
        }
    }

    private static func adopt(fd: Int32, ownsDescriptor: Bool) throws(SDError) -> Setup {
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0 else {
            throw .io(operation: "fcntl(F_GETFL)", errno: errno)
        }
        let mode: SDOpenMode
        switch flags & O_ACCMODE {
        case O_RDONLY:
            mode = .readOnly
        case O_RDWR:
            mode = .readWrite
        default:
            throw .invalidArgument("file descriptor \(fd) is write-only; SDRawDevice reads back what it writes")
        }
        return try setUp(fd: fd, path: nil, mode: mode, ownsDescriptor: ownsDescriptor)
    }

    /// Checks the file type, locks an owned descriptor, and reads the geometry.
    /// On failure the lock taken here is released again; closing is up to the caller.
    private static func setUp(fd: Int32, path: String?, mode: SDOpenMode, ownsDescriptor: Bool) throws(SDError) -> Setup {
        let name = path ?? "file descriptor \(fd)"
        var info = stat()
        guard fstat(fd, &info) == 0 else {
            throw .io(operation: "fstat", errno: errno)
        }
        let type = info.st_mode & mode_t(S_IFMT)
        if type == mode_t(S_IFREG) {
            throw .invalidArgument("\(name) is a regular file; use SDFileBlockDevice for image files")
        }
        guard type == mode_t(S_IFCHR) || type == mode_t(S_IFBLK) else {
            throw .invalidArgument("\(name) is not a character or block device")
        }

        if ownsDescriptor {
            try lock(fd: fd, mode: mode, name: name)
        }
        do throws(SDError) {
            let (sectorSize, sectorCount) = try geometry(fd: fd, name: name)
            return Setup(
                fd: fd, path: path, ownsDescriptor: ownsDescriptor, isReadOnly: mode == .readOnly,
                isBlockDevice: type == mode_t(S_IFBLK), sectorSize: sectorSize, sectorCount: sectorCount,
                bounce: try allocateBounceBuffer(sectorSize: sectorSize)
            )
        } catch {
            if ownsDescriptor {
                flock(fd, LOCK_UN)
            }
            throw error
        }
    }

    private static func geometry(fd: Int32, name: String) throws(SDError) -> (sectorSize: Int, sectorCount: UInt64) {
        var blockSize: UInt32 = 0
        var code = sd_get_logical_block_size(fd, &blockSize)
        guard code == 0 else {
            throw .io(operation: Operation.blockSize, errno: code)
        }
        // The GPT engine supports 512 and 4096 byte sectors only.
        guard blockSize == 512 || blockSize == 4096 else {
            throw .invalidArgument("\(name) has \(blockSize)-byte sectors; only 512 and 4096 are supported")
        }
        var blockCount: UInt64 = 0
        code = sd_get_block_count(fd, &blockCount)
        guard code == 0 else {
            throw .io(operation: Operation.blockCount, errno: code)
        }
        guard blockCount <= UInt64(Int64.max) / UInt64(blockSize) else {
            throw .invalidArgument("\(name) reports \(blockCount) sectors, which exceeds off_t")
        }
        return (Int(blockSize), blockCount)
    }

    private static func allocateBounceBuffer(sectorSize: Int) throws(SDError) -> UnsafeMutableRawBufferPointer {
        let alignment = max(sectorSize, Int(getpagesize()))
        var pointer: UnsafeMutableRawPointer?
        let code = posix_memalign(&pointer, alignment, bounceByteCount)
        guard code == 0, let pointer else {
            throw .io(operation: "posix_memalign", errno: code)
        }
        return UnsafeMutableRawBufferPointer(start: pointer, count: bounceByteCount)
    }

    /// `flock` works per open file description, so two opens in the same process conflict as well.
    private static func lock(fd: Int32, mode: SDOpenMode, name: String) throws(SDError) {
        let operation = (mode == .readOnly ? LOCK_SH : LOCK_EX) | LOCK_NB
        while flock(fd, operation) != 0 {
            let code = errno
            if code == EINTR {
                continue
            }
            if code == EWOULDBLOCK || code == EAGAIN {
                throw .locked(path: name)
            }
            // A lock that cannot be taken for another reason is an error, not something to skip silently.
            throw .io(operation: "flock", errno: code)
        }
    }
}
