//
//  CRC32.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

/// CRC-32 (IEEE 802.3): reflected polynomial 0xEDB88320, initial value and final XOR 0xFFFFFFFF.
/// Produces the same values as zlib's `crc32`.
struct CRC32 {
    private static let table: [UInt32] = (0 ..< 256).map { index in
        var value = UInt32(index)
        for _ in 0 ..< 8 {
            value = (value & 1) != 0 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1
        }
        return value
    }

    /// Running register, kept pre-inverted so that `update` can be called repeatedly.
    private var state: UInt32 = 0xFFFF_FFFF

    init() {}

    mutating func update(_ bytes: UnsafeRawBufferPointer) {
        var crc = state
        Self.table.withUnsafeBufferPointer { table in
            for byte in bytes {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        state = crc
    }

    mutating func update(_ bytes: [UInt8]) {
        bytes.withUnsafeBytes { update($0) }
    }

    var value: UInt32 {
        state ^ 0xFFFF_FFFF
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc = CRC32()
        crc.update(bytes)
        return crc.value
    }

    static func checksum(_ bytes: UnsafeRawBufferPointer) -> UInt32 {
        var crc = CRC32()
        crc.update(bytes)
        return crc.value
    }
}
