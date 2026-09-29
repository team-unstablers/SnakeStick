//
//  Bytes.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

extension Array where Element == UInt8 {
    /// `withUnsafeBytes` that keeps the `SDError` type. The standard library version is `rethrows`,
    /// which erases a typed error to `any Error`.
    func withBytes<R>(_ body: (UnsafeRawBufferPointer) throws(SDError) -> R) throws(SDError) -> R {
        let result: Result<R, SDError> = withUnsafeBytes { buffer in
            do throws(SDError) {
                return .success(try body(buffer))
            } catch {
                return .failure(error)
            }
        }
        return try result.get()
    }

    /// `withUnsafeMutableBytes` that keeps the `SDError` type.
    mutating func withMutableBytes<R>(_ body: (UnsafeMutableRawBufferPointer) throws(SDError) -> R) throws(SDError) -> R {
        let result: Result<R, SDError> = withUnsafeMutableBytes { buffer in
            do throws(SDError) {
                return .success(try body(buffer))
            } catch {
                return .failure(error)
            }
        }
        return try result.get()
    }

    /// Little-endian load. The caller guarantees `offset + size <= count`.
    func loadLE<T: FixedWidthInteger & UnsignedInteger>(_: T.Type, at offset: Int) -> T {
        var value: T = 0
        for i in 0 ..< MemoryLayout<T>.size {
            value |= T(self[offset + i]) << (8 * i)
        }
        return value
    }

    /// Little-endian store. The caller guarantees `offset + size <= count`.
    mutating func storeLE<T: FixedWidthInteger & UnsignedInteger>(_ value: T, at offset: Int) {
        for i in 0 ..< MemoryLayout<T>.size {
            self[offset + i] = UInt8(truncatingIfNeeded: value >> (8 * i))
        }
    }

    /// `true` if every byte in `range` is zero.
    func isZero(_ range: Range<Int>) -> Bool {
        self[range].allSatisfy { $0 == 0 }
    }
}
