// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// Conversion between `Date` and NTFS time: 100 ns intervals since 1601-01-01 00:00:00 UTC.
enum NTFSTime {
    static let ticksPerSecond: Int64 = 10_000_000

    /// Seconds from 1601-01-01 to 2001-01-01, `Date`'s reference date: the 11644473600 seconds
    /// from 1601 to the Unix epoch plus the 978307200 seconds from 1970 to 2001.
    static let secondsFrom1601ToReferenceDate: Int64 = 12_622_780_800

    /// The NTFS time for `date`, rounded to 100 ns, or `nil` if it is before 1601-01-01 or does
    /// not fit in 64 bits.
    ///
    /// The conversion goes through `timeIntervalSinceReferenceDate`, which is how `Date` stores
    /// its value, so dates near 2001 round-trip exactly. For dates in the 2020s a `Double` no
    /// longer resolves every 100 ns step, and a round trip may be off by one tick.
    static func ticks(from date: Date) -> UInt64? {
        let interval = date.timeIntervalSinceReferenceDate
        guard interval.isFinite else {
            return nil
        }
        let whole = interval.rounded(.down)
        guard let seconds = Int64(exactly: whole) else {
            return nil
        }
        // In 0...ticksPerSecond; the upper end carries into the next second below.
        let fractionTicks = Int64(((interval - whole) * Double(ticksPerSecond)).rounded())

        let (secondsSince1601, overflow1) = seconds.addingReportingOverflow(secondsFrom1601ToReferenceDate)
        guard !overflow1, secondsSince1601 >= 0 else {
            return nil
        }
        let (wholeTicks, overflow2) = UInt64(secondsSince1601).multipliedReportingOverflow(by: UInt64(ticksPerSecond))
        let (ticks, overflow3) = wholeTicks.addingReportingOverflow(UInt64(fractionTicks))
        guard !overflow2, !overflow3 else {
            return nil
        }
        return ticks
    }

    static func date(fromTicks ticks: UInt64) -> Date {
        let perSecond = UInt64(ticksPerSecond)
        let seconds = Int64(ticks / perSecond) - secondsFrom1601ToReferenceDate
        let fraction = Double(ticks % perSecond) / Double(ticksPerSecond)
        return Date(timeIntervalSinceReferenceDate: Double(seconds) + fraction)
    }

    /// Seconds from 1601-01-01 to the Unix epoch.
    static let secondsFrom1601ToUnixEpoch: Int64 = 11_644_473_600

    /// The NTFS time for a `timespec` from `stat(2)`, truncated to 100 ns, or `nil` if it is out
    /// of range. Computed in integers, so it does not lose precision the way a `Date` would.
    static func ticks(from time: timespec) -> UInt64? {
        let (secondsSince1601, overflow1) = Int64(time.tv_sec).addingReportingOverflow(secondsFrom1601ToUnixEpoch)
        guard !overflow1, secondsSince1601 >= 0, (0..<1_000_000_000).contains(time.tv_nsec) else {
            return nil
        }
        let (wholeTicks, overflow2) = UInt64(secondsSince1601).multipliedReportingOverflow(by: UInt64(ticksPerSecond))
        let (ticks, overflow3) = wholeTicks.addingReportingOverflow(UInt64(time.tv_nsec / 100))
        guard !overflow2, !overflow3 else {
            return nil
        }
        return ticks
    }
}
