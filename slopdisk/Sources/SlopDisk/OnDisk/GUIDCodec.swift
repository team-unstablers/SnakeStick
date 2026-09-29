//
//  GUIDCodec.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

import Foundation

/// Mixed-endian GUID encoding used by GPT.
///
/// Text `AABBCCDD-EEFF-GGHH-IIJJ-KKLLMMNNOOPP` is stored as
/// `DD CC BB AA  FF EE  HH GG  II JJ  KK LL MM NN OO PP`.
/// `UUID.uuid` is in RFC (big-endian) order, so the first three fields are byte-swapped here.
/// A codec that skips the swap still round-trips, which is why the golden-byte tests exist.
enum GUIDCodec {
    static let byteCount = 16
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    /// Maps between RFC byte order and on-disk byte order. The permutation is its own inverse.
    private static let permutation = [3, 2, 1, 0, 5, 4, 7, 6, 8, 9, 10, 11, 12, 13, 14, 15]

    static func decode(_ bytes: [UInt8], at offset: Int) -> UUID {
        var rfc = [UInt8](repeating: 0, count: byteCount)
        for i in 0 ..< byteCount {
            rfc[i] = bytes[offset + permutation[i]]
        }
        return UUID(uuid: (
            rfc[0], rfc[1], rfc[2], rfc[3], rfc[4], rfc[5], rfc[6], rfc[7],
            rfc[8], rfc[9], rfc[10], rfc[11], rfc[12], rfc[13], rfc[14], rfc[15]
        ))
    }

    static func encode(_ uuid: UUID, into bytes: inout [UInt8], at offset: Int) {
        let rfc = withUnsafeBytes(of: uuid.uuid) { Array($0) }
        for i in 0 ..< byteCount {
            bytes[offset + permutation[i]] = rfc[i]
        }
    }
}
