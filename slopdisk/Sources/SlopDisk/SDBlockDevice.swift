//
//  SDBlockDevice.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

/// A sector-addressed storage backend.
///
/// Contract for implementations:
/// - `buffer.count` passed to `read` / `write` must be a non-zero multiple of `sectorSize`,
///   and `lba + buffer.count / sectorSize` must not exceed `sectorCount`. Violations throw `.invalidArgument`.
/// - `write` on a device whose `isReadOnly` is `true` throws `.readOnly`.
/// - Failures specific to a third-party backend are reported as `.device(description:)`.
public protocol SDBlockDevice: AnyObject {
    /// Bytes per logical sector. The GPT engine supports 512 and 4096.
    var sectorSize: Int { get }
    var sectorCount: UInt64 { get }
    var isReadOnly: Bool { get }
    func read(lba: UInt64, into buffer: UnsafeMutableRawBufferPointer) throws(SDError)
    func write(lba: UInt64, from buffer: UnsafeRawBufferPointer) throws(SDError)
    /// Flushes written data to stable storage.
    func synchronize() throws(SDError)
}

public enum SDOpenMode: Sendable {
    case readOnly
    case readWrite
}

extension SDBlockDevice {
    /// Validates an I/O request against the `SDBlockDevice` contract.
    func validateRequest(lba: UInt64, byteCount: Int) throws(SDError) {
        try SDBlockRequest.validate(
            lba: lba, byteCount: byteCount, sectorSize: sectorSize, sectorCount: sectorCount
        )
    }

    /// Reads `count` sectors starting at `lba` into a new array.
    func readSectors(lba: UInt64, count: Int) throws(SDError) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count * sectorSize)
        try bytes.withMutableBytes { (buffer) throws(SDError) in
            try read(lba: lba, into: buffer)
        }
        return bytes
    }

    /// Writes `bytes` (a whole number of sectors) starting at `lba`.
    func writeSectors(lba: UInt64, _ bytes: [UInt8]) throws(SDError) {
        try bytes.withBytes { (buffer) throws(SDError) in
            try write(lba: lba, from: buffer)
        }
    }
}

/// Request validation shared by the built-in `SDBlockDevice` implementations.
enum SDBlockRequest {
    static func validate(lba: UInt64, byteCount: Int, sectorSize: Int, sectorCount: UInt64) throws(SDError) {
        guard byteCount > 0, byteCount % sectorSize == 0 else {
            throw .invalidArgument("I/O length \(byteCount) is not a positive multiple of the sector size \(sectorSize)")
        }
        let sectors = UInt64(byteCount / sectorSize)
        guard lba <= sectorCount, sectors <= sectorCount - lba else {
            throw .invalidArgument("I/O at LBA \(lba) for \(sectors) sectors exceeds the device (\(sectorCount) sectors)")
        }
    }

    static func isSupported(sectorSize: Int) -> Bool {
        sectorSize >= 512 && sectorSize.nonzeroBitCount == 1
    }
}
