//
//  GPTEntry.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

import Foundation

/// One partition entry (the first 128 bytes of an entry slot).
///
/// ```
/// off size
/// 0   16  PartitionTypeGUID (mixed-endian; all zero = unused slot)
/// 16  16  UniquePartitionGUID
/// 32  8   StartingLBA
/// 40  8   EndingLBA (inclusive)
/// 48  8   Attributes
/// 56  72  PartitionName (UTF-16LE, 36 units, zero-padded)
/// ```
///
/// The name is kept as raw bytes so that a table read from disk is rewritten byte-for-byte by `repair()`,
/// even if the name holds bytes after the terminator or unpaired surrogates.
struct GPTEntry: Hashable, Sendable {
    static let byteCount = 128
    static let nameOffset = 56

    var typeGUID: UUID
    var uniqueGUID: UUID
    var firstLBA: UInt64
    var lastLBA: UInt64
    var attributes: UInt64
    var rawName: [UInt8]

    init(typeGUID: UUID, uniqueGUID: UUID, firstLBA: UInt64, lastLBA: UInt64, attributes: UInt64, label: String) throws(SDError) {
        self.typeGUID = typeGUID
        self.uniqueGUID = uniqueGUID
        self.firstLBA = firstLBA
        self.lastLBA = lastLBA
        self.attributes = attributes
        self.rawName = try UTF16Label.encode(label)
    }

    init(decoding bytes: [UInt8], at offset: Int) {
        typeGUID = GUIDCodec.decode(bytes, at: offset)
        uniqueGUID = GUIDCodec.decode(bytes, at: offset + 16)
        firstLBA = bytes.loadLE(UInt64.self, at: offset + 32)
        lastLBA = bytes.loadLE(UInt64.self, at: offset + 40)
        attributes = bytes.loadLE(UInt64.self, at: offset + 48)
        rawName = Array(bytes[offset + Self.nameOffset ..< offset + Self.nameOffset + UTF16Label.byteCount])
    }

    var isUnused: Bool {
        typeGUID == GUIDCodec.zero
    }

    var label: String {
        UTF16Label.decode(rawName)
    }

    mutating func setLabel(_ label: String) throws(SDError) {
        rawName = try UTF16Label.encode(label)
    }

    func encode(into bytes: inout [UInt8], at offset: Int) {
        GUIDCodec.encode(typeGUID, into: &bytes, at: offset)
        GUIDCodec.encode(uniqueGUID, into: &bytes, at: offset + 16)
        bytes.storeLE(firstLBA, at: offset + 32)
        bytes.storeLE(lastLBA, at: offset + 40)
        bytes.storeLE(attributes, at: offset + 48)
        bytes.replaceSubrange(offset + Self.nameOffset ..< offset + Self.nameOffset + UTF16Label.byteCount, with: rawName)
    }

    func partition(index: Int, sectorSize: Int) -> SDPartition {
        SDPartition(
            index: index,
            type: SDPartitionType(guid: typeGUID),
            uniqueID: uniqueGUID,
            begin: firstLBA,
            end: lastLBA,
            attributes: SDPartitionAttributes(rawValue: attributes),
            label: label,
            sectorSize: sectorSize
        )
    }
}

/// A GPT as SlopDisk stages and writes it: the disk GUID plus the used entry slots.
struct GPTTable: Hashable, Sendable {
    var diskID: UUID
    /// Used slots only, keyed by slot index.
    var entries: [Int: GPTEntry]

    func partitions(sectorSize: Int) -> [SDPartition] {
        entries.keys.sorted().map { entries[$0]!.partition(index: $0, sectorSize: sectorSize) }
    }

    /// Encodes the 128 × 128-byte entry array padded to whole sectors.
    /// Throws `.tooManyPartitions` if a used slot does not fit in 128 entries.
    func encodeEntryArray(sectorSize: Int) throws(SDError) -> [UInt8] {
        let sectors = Int(GPTGeometry.entryArraySectors(sectorSize: sectorSize))
        var bytes = [UInt8](repeating: 0, count: sectors * sectorSize)
        for (index, entry) in entries {
            guard index >= 0, index < GPTGeometry.entryCount else {
                throw .tooManyPartitions
            }
            entry.encode(into: &bytes, at: index * GPTGeometry.entrySize)
        }
        return bytes
    }
}
