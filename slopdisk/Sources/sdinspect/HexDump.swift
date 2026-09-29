//
//  HexDump.swift
//  sdinspect
//
//  Created by Gyuhwan Park on 9/30/26.
//

/// `hexdump -C` style output: 16 bytes per line, repeated lines collapsed to `*`.
enum HexDump {
    static func lines(_ bytes: [UInt8]) -> [String] {
        var output: [String] = []
        var previous: ArraySlice<UInt8>?
        var collapsing = false
        var offset = 0
        while offset < bytes.count {
            let row = bytes[offset ..< min(offset + 16, bytes.count)]
            if let previous, previous.elementsEqual(row), row.count == 16 {
                if !collapsing {
                    output.append("*")
                    collapsing = true
                }
            } else {
                collapsing = false
                output.append(line(offset: offset, row: row))
            }
            previous = row
            offset += 16
        }
        output.append(hexDigits(UInt64(bytes.count), width: 8).lowercased())
        return output
    }

    private static func line(offset: Int, row: ArraySlice<UInt8>) -> String {
        var hex = ""
        for (i, byte) in row.enumerated() {
            hex += hexDigits(UInt64(byte), width: 2).lowercased() + " "
            if i == 7 {
                hex += " "
            }
        }
        let ascii = row.map { (0x20 ..< 0x7F).contains($0) ? Character(Unicode.Scalar($0)) : "." }
        return hexDigits(UInt64(offset), width: 8).lowercased() + "  " + hex.padding(50) + "|" + String(ascii) + "|"
    }
}
