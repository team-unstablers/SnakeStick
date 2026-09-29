//
//  SDSize.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

/// A byte count.
///
/// All unit constructors are binary: `.kilobytes(1)` is 1024 bytes, `.megabytes(1)` is 1024² bytes, and so on.
/// SI (1000-based) units are intentionally not provided.
public struct SDSize: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var bytes: UInt64

    public init(bytes: UInt64) {
        self.bytes = bytes
    }

    public static func bytes(_ n: some BinaryInteger) -> SDSize {
        scaled(n, by: 1)
    }

    /// `n` × 1024 bytes.
    public static func kilobytes(_ n: some BinaryInteger) -> SDSize {
        scaled(n, by: 1 << 10)
    }

    /// `n` × 1024² bytes.
    public static func megabytes(_ n: some BinaryInteger) -> SDSize {
        scaled(n, by: 1 << 20)
    }

    /// `n` × 1024³ bytes.
    public static func gigabytes(_ n: some BinaryInteger) -> SDSize {
        scaled(n, by: 1 << 30)
    }

    /// `n` × 1024⁴ bytes.
    public static func terabytes(_ n: some BinaryInteger) -> SDSize {
        scaled(n, by: 1 << 40)
    }

    public static func < (lhs: SDSize, rhs: SDSize) -> Bool {
        lhs.bytes < rhs.bytes
    }

    /// The value in the largest binary unit in which it is at least 1, with at most two decimal places.
    ///
    /// Examples: `512 B`, `1.5 KiB`, `400 MiB`, `8 GiB`.
    public var description: String {
        let units: [(suffix: String, shift: UInt64)] = [
            ("TiB", 40), ("GiB", 30), ("MiB", 20), ("KiB", 10),
        ]
        for unit in units {
            let divisor: UInt64 = 1 << unit.shift
            if bytes >= divisor {
                return Self.format(bytes, divisor: divisor, suffix: unit.suffix)
            }
        }
        return "\(bytes) B"
    }

    private static func scaled(_ n: some BinaryInteger, by factor: UInt64) -> SDSize {
        precondition(n >= 0, "SDSize cannot be negative")
        guard let value = UInt64(exactly: n) else {
            preconditionFailure("SDSize overflows UInt64")
        }
        let (product, overflow) = value.multipliedReportingOverflow(by: factor)
        precondition(!overflow, "SDSize overflows UInt64")
        return SDSize(bytes: product)
    }

    /// Formats `value / divisor` rounded to two decimal places, dropping trailing zeros.
    /// Integer arithmetic only, so the output does not depend on locale or floating-point rounding.
    private static func format(_ value: UInt64, divisor: UInt64, suffix: String) -> String {
        var whole = value / divisor
        let remainder = value % divisor
        // remainder < divisor <= 2^40, so remainder * 100 cannot overflow.
        var hundredths = (remainder * 100 + divisor / 2) / divisor
        if hundredths == 100 {
            whole += 1
            hundredths = 0
        }
        if hundredths == 0 {
            return "\(whole) \(suffix)"
        }
        if hundredths % 10 == 0 {
            return "\(whole).\(hundredths / 10) \(suffix)"
        }
        let padded = hundredths < 10 ? "0\(hundredths)" : "\(hundredths)"
        return "\(whole).\(padded) \(suffix)"
    }
}

/// How much space a partition should occupy.
public enum SDPartitionExtent: Hashable, Sendable {
    /// A fixed size, rounded up to whole sectors.
    case size(SDSize)
    /// Everything up to the end of the free region the partition starts in.
    case remaining

    public static func bytes(_ n: some BinaryInteger) -> SDPartitionExtent {
        .size(.bytes(n))
    }

    public static func kilobytes(_ n: some BinaryInteger) -> SDPartitionExtent {
        .size(.kilobytes(n))
    }

    public static func megabytes(_ n: some BinaryInteger) -> SDPartitionExtent {
        .size(.megabytes(n))
    }

    public static func gigabytes(_ n: some BinaryInteger) -> SDPartitionExtent {
        .size(.gigabytes(n))
    }

    public static func terabytes(_ n: some BinaryInteger) -> SDPartitionExtent {
        .size(.terabytes(n))
    }
}
