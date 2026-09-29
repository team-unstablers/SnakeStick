//
//  UTF16Label.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

/// The 72-byte PartitionName field: up to 36 UTF-16LE code units, zero-padded.
enum UTF16Label {
    static let maxUnits = 36
    static let byteCount = maxUnits * 2

    /// Throws `.labelTooLong` if `label` needs more than 36 UTF-16 code units.
    /// Length is measured in code units, not characters: an emoji outside the BMP counts as 2.
    static func validate(_ label: String) throws(SDError) {
        let count = label.utf16.count
        guard count <= maxUnits else {
            throw .labelTooLong(utf16Count: count)
        }
    }

    /// Returns the 72-byte field for `label`.
    static func encode(_ label: String) throws(SDError) -> [UInt8] {
        try validate(label)
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for (i, unit) in label.utf16.enumerated() {
            bytes.storeLE(unit, at: i * 2)
        }
        return bytes
    }

    /// Decodes up to the first U+0000. Unpaired surrogates become U+FFFD.
    static func decode(_ field: [UInt8]) -> String {
        var units: [UInt16] = []
        units.reserveCapacity(maxUnits)
        for i in 0 ..< field.count / 2 {
            let unit = field.loadLE(UInt16.self, at: i * 2)
            if unit == 0 {
                break
            }
            units.append(unit)
        }
        return String(decoding: units, as: UTF16.self)
    }
}
