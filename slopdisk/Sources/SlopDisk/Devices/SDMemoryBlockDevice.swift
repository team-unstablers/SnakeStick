//
//  SDMemoryBlockDevice.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A sparse in-memory block device.
///
/// Storage is kept in 64 KiB chunks that are allocated on first write. Regions that were never written read as zeros,
/// so an 8 TiB device costs nothing until it is written to.
public final class SDMemoryBlockDevice: SDBlockDevice {
    static let chunkSize = 64 * 1024

    public let sectorSize: Int
    public let sectorCount: UInt64
    public var isReadOnly: Bool { false }

    /// Allocated chunks keyed by chunk index (byte offset / 64 KiB).
    private(set) var chunks: [UInt64: [UInt8]] = [:]

    public init(sectorSize: Int, sectorCount: UInt64) {
        precondition(SDBlockRequest.isSupported(sectorSize: sectorSize), "sector size must be a power of two >= 512")
        precondition(sectorSize <= Self.chunkSize, "sector size must not exceed the chunk size")
        let (_, overflow) = sectorCount.multipliedReportingOverflow(by: UInt64(sectorSize))
        precondition(!overflow, "device size overflows UInt64")
        self.sectorSize = sectorSize
        self.sectorCount = sectorCount
    }

    /// Bytes currently backed by allocated chunks.
    public var allocatedByteCount: Int {
        chunks.count * Self.chunkSize
    }

    private var byteCount: UInt64 {
        sectorCount * UInt64(sectorSize)
    }

    /// Returns `count` bytes starting at `offset`. The range must lie within the device.
    public func bytes(atByteOffset offset: UInt64, count: Int) -> [UInt8] {
        precondition(count >= 0 && offset <= byteCount && UInt64(count) <= byteCount - offset, "range exceeds the device")
        var result = [UInt8](repeating: 0, count: count)
        result.withUnsafeMutableBytes { buffer in
            copyOut(from: offset, into: buffer)
        }
        return result
    }

    public func read(lba: UInt64, into buffer: UnsafeMutableRawBufferPointer) throws(SDError) {
        try validateRequest(lba: lba, byteCount: buffer.count)
        copyOut(from: lba * UInt64(sectorSize), into: buffer)
    }

    public func write(lba: UInt64, from buffer: UnsafeRawBufferPointer) throws(SDError) {
        try validateRequest(lba: lba, byteCount: buffer.count)
        var offset = lba * UInt64(sectorSize)
        var done = 0
        while done < buffer.count {
            let chunkIndex = offset / UInt64(Self.chunkSize)
            let inChunk = Int(offset % UInt64(Self.chunkSize))
            let length = min(Self.chunkSize - inChunk, buffer.count - done)
            let source = UnsafeRawBufferPointer(rebasing: buffer[done ..< done + length])
            chunks[chunkIndex, default: [UInt8](repeating: 0, count: Self.chunkSize)].withUnsafeMutableBytes { chunk in
                chunk.baseAddress!.advanced(by: inChunk).copyMemory(from: source.baseAddress!, byteCount: length)
            }
            done += length
            offset += UInt64(length)
        }
    }

    public func synchronize() throws(SDError) {}

    /// Writes the device contents to a new sparse file at `path`.
    ///
    /// Only allocated chunks are written; the file is then sized with `ftruncate`.
    /// Throws `.fileExists` if `path` already exists.
    public func export(toFile path: String) throws(SDError) {
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
        guard fd >= 0 else {
            let code = errno
            if code == EEXIST {
                throw .fileExists(path: path)
            }
            throw .io(operation: "open", errno: code)
        }
        defer { close(fd) }
        guard ftruncate(fd, off_t(byteCount)) == 0 else {
            throw .io(operation: "ftruncate", errno: errno)
        }
        for chunkIndex in chunks.keys.sorted() {
            let start = chunkIndex * UInt64(Self.chunkSize)
            let length = Int(min(UInt64(Self.chunkSize), byteCount - start))
            try chunks[chunkIndex]!.withBytes { (chunk) throws(SDError) in
                try POSIXIO.writeAll(
                    fd: fd, from: UnsafeRawBufferPointer(rebasing: chunk[0 ..< length]), offset: start
                )
            }
        }
    }

    private func copyOut(from offset: UInt64, into buffer: UnsafeMutableRawBufferPointer) {
        var offset = offset
        var done = 0
        while done < buffer.count {
            let chunkIndex = offset / UInt64(Self.chunkSize)
            let inChunk = Int(offset % UInt64(Self.chunkSize))
            let length = min(Self.chunkSize - inChunk, buffer.count - done)
            let destination = buffer.baseAddress!.advanced(by: done)
            if let chunk = chunks[chunkIndex] {
                chunk.withUnsafeBytes { source in
                    destination.copyMemory(from: source.baseAddress!.advanced(by: inChunk), byteCount: length)
                }
            } else {
                destination.initializeMemory(as: UInt8.self, repeating: 0, count: length)
            }
            done += length
            offset += UInt64(length)
        }
    }
}
