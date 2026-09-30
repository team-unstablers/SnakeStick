// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Byte counts written with SI suffixes, as `--imgsize` takes them.
public enum SISize {
    /// Parses `"8G"` as 8,000,000,000 and `"7.5G"` as 7,500,000,000. Suffixes are `K`, `M`, `G`
    /// and `T` (powers of 1000, optionally followed by `B`, any case); no suffix means bytes.
    /// Returns `nil` for anything else, for zero, for fractions of a byte and on overflow.
    public static func parse(_ text: String) -> UInt64? {
        var body = Substring(text.trimmingCharacters(in: .whitespaces).uppercased())
        if body.hasSuffix("B"), body.count > 1, let unit = body.dropLast().last, "KMGT".contains(unit) {
            body = body.dropLast()
        }
        var multiplier: UInt64 = 1
        var scale = 0
        if let unit = body.last, let power = ["K": 3, "M": 6, "G": 9, "T": 12][unit] {
            scale = power
            multiplier = (0 ..< power).reduce(1) { value, _ in value * 10 }
            body = body.dropLast()
        }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard (1 ... 2).contains(parts.count),
              let integerPart = parts.first, !integerPart.isEmpty, integerPart.allSatisfy(\.isASCIIDigit)
        else {
            return nil
        }
        let fractionPart = parts.count == 2 ? parts[1] : ""
        guard fractionPart.allSatisfy(\.isASCIIDigit), parts.count == 1 || !fractionPart.isEmpty else {
            return nil
        }
        // The fraction must end within the unit: "1.5K" is 1500 bytes, "1.0005K" is not a
        // whole number of bytes. Trailing zeros are fine.
        let significant = fractionPart.reversed().drop { $0 == "0" }.reversed()
        guard significant.count <= scale else {
            return nil
        }
        guard let integer = UInt64(integerPart) else {
            return nil
        }
        let (whole, overflow1) = integer.multipliedReportingOverflow(by: multiplier)
        var fraction: UInt64 = 0
        if !significant.isEmpty {
            let digits = UInt64(String(significant))!
            let remaining = (0 ..< (scale - significant.count)).reduce(UInt64(1)) { value, _ in value * 10 }
            fraction = digits * remaining
        }
        let (total, overflow2) = whole.addingReportingOverflow(fraction)
        guard !overflow1, !overflow2, total > 0 else {
            return nil
        }
        return total
    }

    /// `bytes` in the largest SI unit that keeps two decimals meaningful, e.g. `"7.21 GB"`.
    public static func format(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
