//
//  POSIXIO.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// `pread` / `pwrite` loops that handle short transfers and `EINTR`.
enum POSIXIO {
    static func readAll(fd: Int32, into buffer: UnsafeMutableRawBufferPointer, offset: UInt64) throws(SDError) {
        var done = 0
        while done < buffer.count {
            let result = pread(fd, buffer.baseAddress! + done, buffer.count - done, off_t(offset + UInt64(done)))
            if result < 0 {
                let code = errno
                if code == EINTR {
                    continue
                }
                throw .io(operation: "pread", errno: code)
            }
            if result == 0 {
                // The file ended before the requested range; it was truncated while open.
                throw .io(operation: "pread", errno: EIO)
            }
            done += result
        }
    }

    static func writeAll(fd: Int32, from buffer: UnsafeRawBufferPointer, offset: UInt64) throws(SDError) {
        var done = 0
        while done < buffer.count {
            let result = pwrite(fd, buffer.baseAddress! + done, buffer.count - done, off_t(offset + UInt64(done)))
            if result < 0 {
                let code = errno
                if code == EINTR {
                    continue
                }
                throw .io(operation: "pwrite", errno: code)
            }
            if result == 0 {
                throw .io(operation: "pwrite", errno: EIO)
            }
            done += result
        }
    }
}
