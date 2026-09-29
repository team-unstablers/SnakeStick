//
//  CodecTests.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

import Foundation
import Testing
@testable import SlopDisk

@Suite struct CRC32Tests {
    @Test func checkValue() {
        #expect(CRC32.checksum(Array("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.checksum([]) == 0)
    }

    @Test func incrementalMatchesOneShot() {
        let bytes = (0 ..< 5000).map { UInt8(truncatingIfNeeded: $0 &* 31) }
        var crc = CRC32()
        crc.update(Array(bytes[0 ..< 1234]))
        crc.update(Array(bytes[1234...]))
        #expect(crc.value == CRC32.checksum(bytes))
    }
}

/// T1: golden bytes from a real hdiutil image.
@Suite struct GoldenBytesTests {
    @Test func primaryHeaderFields() {
        var sector = [UInt8](repeating: 0, count: 512)
        sector.replaceSubrange(0 ..< 92, with: Golden.primaryHeader)
        #expect(GPTHeader.hasSignature(sector))
        let header = GPTHeader(decoding: sector)
        #expect(header.revision == 0x0001_0000)
        #expect(header.headerSize == 92)
        #expect(header.headerCRC32 == Golden.headerCRC)
        #expect(header.myLBA == 1)
        #expect(header.alternateLBA == 16383)
        #expect(header.firstUsableLBA == 34)
        #expect(header.lastUsableLBA == 16350)
        #expect(header.diskGUID == Golden.diskGUID)
        #expect(header.partitionEntryLBA == 2)
        #expect(header.numberOfPartitionEntries == 128)
        #expect(header.sizeOfPartitionEntry == 128)
        #expect(header.partitionEntryArrayCRC32 == Golden.entriesCRC)
    }

    @Test func headerCRCRecomputes() {
        #expect(GPTHeader.computeCRC(of: Golden.primaryHeader, headerSize: 92) == Golden.headerCRC)
        // The CRC covers HeaderSize bytes only; computing it over the whole sector gives a different value.
        var sector = [UInt8](repeating: 0, count: 512)
        sector.replaceSubrange(0 ..< 92, with: Golden.primaryHeader)
        #expect(GPTHeader.computeCRC(of: sector, headerSize: 512) != Golden.headerCRC)
    }

    @Test func headerReencodesToSameBytes() {
        var sector = [UInt8](repeating: 0, count: 512)
        sector.replaceSubrange(0 ..< 92, with: Golden.primaryHeader)
        let encoded = GPTHeader(decoding: sector).encode(sectorSize: 512)
        #expect(encoded == sector)
    }

    @Test func entryFields() {
        let entry = GPTEntry(decoding: Golden.entry0, at: 0)
        #expect(entry.typeGUID == Golden.entryType)
        #expect(entry.uniqueGUID == Golden.entryUnique)
        #expect(entry.firstLBA == 40)
        #expect(entry.lastLBA == 16343)
        #expect(entry.attributes == 0)
        #expect(entry.label == "disk image")
        #expect(SDPartitionType(guid: entry.typeGUID) == .appleHFSPlus)
    }

    @Test func entryReencodesToSameBytes() throws {
        let decoded = GPTEntry(decoding: Golden.entry0, at: 0)
        var bytes = [UInt8](repeating: 0xAA, count: 128)
        decoded.encode(into: &bytes, at: 0)
        #expect(bytes == Golden.entry0)

        // Built from the model (label re-encoded from the string), not from raw bytes.
        let rebuilt = try GPTEntry(
            typeGUID: Golden.entryType, uniqueGUID: Golden.entryUnique,
            firstLBA: 40, lastLBA: 16343, attributes: 0, label: "disk image"
        )
        var rebuiltBytes = [UInt8](repeating: 0, count: 128)
        rebuilt.encode(into: &rebuiltBytes, at: 0)
        #expect(rebuiltBytes == Golden.entry0)
    }

    @Test func entryArrayCRC() throws {
        var array = [UInt8](repeating: 0, count: 128 * 128)
        array.replaceSubrange(0 ..< 128, with: Golden.entry0)
        #expect(CRC32.checksum(array) == Golden.entriesCRC)

        let table = GPTTable(diskID: Golden.diskGUID, entries: [0: GPTEntry(decoding: Golden.entry0, at: 0)])
        #expect(try table.encodeEntryArray(sectorSize: 512) == array)
        #expect(try table.encodeEntryArray(sectorSize: 4096) == array)
    }

    @Test func mixedEndianGUID() {
        let bytes = Array(Golden.primaryHeader[56 ..< 72])
        #expect(GUIDCodec.decode(bytes, at: 0) == Golden.diskGUID)
        var encoded = [UInt8](repeating: 0, count: 16)
        GUIDCodec.encode(Golden.diskGUID, into: &encoded, at: 0)
        #expect(encoded == bytes)
        #expect(encoded[0 ..< 4] == [0x3b, 0xd7, 0x4a, 0xfb], "first field is little-endian")
        #expect(encoded[8 ..< 10] == [0xbd, 0x0a], "fourth field keeps RFC order")

        let typeBytes = Array(Golden.entry0[0 ..< 16])
        #expect(GUIDCodec.decode(typeBytes, at: 0) == SDPartitionType.appleHFSPlus.guid)
    }

    @Test func protectiveRecordWithAppleCHS() {
        var lba0 = [UInt8](repeating: 0, count: 512)
        lba0.replaceSubrange(446 ..< 462, with: Golden.mbrRecord0)
        lba0[510] = 0x55
        lba0[511] = 0xAA
        let block = MBRBlock(sector: lba0)
        #expect(block.hasSignature)
        #expect(block.hasProtectiveRecord)
        #expect(!block.hasOtherRecords)
        #expect(block.records[0].firstLBA == 1)
        #expect(block.records[0].sectorCount == 16383)
    }

    @Test func fixtureDeviceReadsAsHealthy() throws {
        let inspection = try SDInspection.read(from: Golden.fixtureDevice())
        #expect(try inspection.scheme.get() == .gpt(.healthy))
        #expect(inspection.primary?.computedHeaderCRC == Golden.headerCRC)
        #expect(inspection.primary?.computedEntriesCRC == Golden.entriesCRC)
        #expect(inspection.mbr.kind == .protective)
    }
}

@Suite struct ProtectiveMBRTests {
    @Test func layout() {
        let sector = MBRBlock.protectiveSector(sectorSize: 512, sectorCount: 16384)
        #expect(sector.count == 512)
        #expect(sector[0 ..< 446].allSatisfy { $0 == 0 })
        #expect(Array(sector[446 ..< 462]) == [
            0x00, 0x00, 0x02, 0x00, 0xee, 0xff, 0xff, 0xff, 0x01, 0x00, 0x00, 0x00, 0xff, 0x3f, 0x00, 0x00,
        ])
        #expect(sector[462 ..< 510].allSatisfy { $0 == 0 })
        #expect(sector[510] == 0x55 && sector[511] == 0xAA)
    }

    @Test func sizeClampsAbove2TiB() {
        let sectorCount: UInt64 = 8 << 40 / 512
        let sector = MBRBlock.protectiveSector(sectorSize: 512, sectorCount: sectorCount)
        #expect(sector.loadLE(UInt32.self, at: 446 + 12) == 0xFFFF_FFFF)
        let exact = MBRBlock.protectiveSector(sectorSize: 512, sectorCount: 0x1_0000_0000)
        #expect(exact.loadLE(UInt32.self, at: 446 + 12) == 0xFFFF_FFFF)
    }

    @Test func fourKnSectorHoldsMBRInFirst512Bytes() {
        let sector = MBRBlock.protectiveSector(sectorSize: 4096, sectorCount: 16384)
        #expect(sector.count == 4096)
        #expect(sector[510] == 0x55 && sector[511] == 0xAA)
        #expect(sector[512...].allSatisfy { $0 == 0 })
        #expect(sector.loadLE(UInt32.self, at: 446 + 12) == 16383)
    }

    @Test func fatBootSectorIsNotAnMBR() {
        // A FAT32 VBR: jump, OEM name, BPB, boot code, 55 AA. The partition-record area holds boot code.
        var vbr = [UInt8](repeating: 0, count: 512)
        vbr.replaceSubrange(0 ..< 11, with: [0xEB, 0x58, 0x90] + Array("BSD  4.4".utf8))
        for i in 90 ..< 510 {
            vbr[i] = UInt8(truncatingIfNeeded: i &* 7 &+ 3)
        }
        vbr[510] = 0x55
        vbr[511] = 0xAA
        let block = MBRBlock(sector: vbr)
        #expect(block.hasSignature)
        #expect(!block.isClassicMBR(diskSectorCount: 131072))
    }
}

@Suite struct LabelTests {
    @Test func hangulAndEmojiLimits() throws {
        #expect(try UTF16Label.encode("윈도우설치").count == 72)
        try UTF16Label.validate(String(repeating: "💾", count: 18))
        expectError(.labelTooLong(utf16Count: 38)) {
            try UTF16Label.validate(String(repeating: "💾", count: 19))
        }
        try UTF16Label.validate(String(repeating: "a", count: 36))
        expectError(.labelTooLong(utf16Count: 37)) {
            try UTF16Label.validate(String(repeating: "a", count: 37))
        }
    }

    @Test func roundTripsNonASCII() throws {
        for label in ["윈도우설치", String(repeating: "💾", count: 18), "EFI", "", "ÅÄÖ-Ελληνικά"] {
            #expect(UTF16Label.decode(try UTF16Label.encode(label)) == label)
        }
    }

    @Test func decodeStopsAtFirstNUL() throws {
        var field = try UTF16Label.encode("EFI")
        field.storeLE(UInt16(0x0041), at: 10)  // garbage after the terminator
        #expect(UTF16Label.decode(field) == "EFI")
    }

    @Test func unpairedSurrogateBecomesReplacementCharacter() {
        var field = [UInt8](repeating: 0, count: 72)
        field.storeLE(UInt16(0xD83D), at: 0)
        field.storeLE(UInt16(0x0041), at: 2)
        #expect(UTF16Label.decode(field) == "\u{FFFD}A")
    }
}

@Suite struct GeometryTests {
    @Test func sector512() throws {
        let geometry = try GPTGeometry(sectorSize: 512, sectorCount: 131072)
        #expect(geometry.entryArraySectors == 32)
        #expect(geometry.firstUsableLBA == 34)
        #expect(geometry.lastUsableLBA == 131038)
        #expect(geometry.backupEntriesLBA == 131039)
        #expect(geometry.backupHeaderLBA == 131071)
        #expect(geometry.alignment == 2048)
        #expect(GPTGeometry.minimumSectorCount(sectorSize: 512) == 68)
    }

    @Test func sector4096() throws {
        let geometry = try GPTGeometry(sectorSize: 4096, sectorCount: 16384)
        #expect(geometry.entryArraySectors == 4)
        #expect(geometry.firstUsableLBA == 6)
        #expect(geometry.lastUsableLBA == 16378)
        #expect(geometry.alignment == 256)
        #expect(GPTGeometry.minimumSectorCount(sectorSize: 4096) == 12)
    }

    @Test func tooSmall() throws {
        expectError(.diskTooSmall(minimum: .bytes(68 * 512))) {
            try GPTGeometry(sectorSize: 512, sectorCount: 67)
        }
        let minimal = try GPTGeometry(sectorSize: 512, sectorCount: 68)
        #expect(minimal.firstUsableLBA == minimal.lastUsableLBA)
    }
}

@Suite struct HeaderValidationTests {
    private func header(myLBA: UInt64 = 1) -> GPTHeader {
        GPTHeader(
            myLBA: myLBA, alternateLBA: 16383, firstUsableLBA: 34, lastUsableLBA: 16350, diskGUID: Golden.diskGUID,
            partitionEntryLBA: 2, numberOfPartitionEntries: 128, sizeOfPartitionEntry: 128, partitionEntryArrayCRC32: 0
        )
    }

    @Test func consistentHeaderPasses() {
        #expect(header().hasConsistentFields(readAt: 1, sectorSize: 512, sectorCount: 16384))
    }

    @Test func contradictions() {
        #expect(!header(myLBA: 2).hasConsistentFields(readAt: 1, sectorSize: 512, sectorCount: 16384))

        var reversed = header()
        reversed.firstUsableLBA = 100
        reversed.lastUsableLBA = 50
        #expect(!reversed.hasConsistentFields(readAt: 1, sectorSize: 512, sectorCount: 16384))

        var badSize = header()
        badSize.sizeOfPartitionEntry = 192
        #expect(!badSize.hasConsistentFields(readAt: 1, sectorSize: 512, sectorCount: 16384))

        var bigger = header()
        bigger.sizeOfPartitionEntry = 256
        #expect(bigger.hasValidEntrySize)

        var overlapsEntries = header()
        overlapsEntries.firstUsableLBA = 20
        #expect(!overlapsEntries.hasConsistentFields(readAt: 1, sectorSize: 512, sectorCount: 16384))

        var outside = header()
        outside.partitionEntryLBA = 16370
        #expect(!outside.hasConsistentFields(readAt: 1, sectorSize: 512, sectorCount: 16384))

        var coversAlternate = header()
        coversAlternate.lastUsableLBA = 16383
        #expect(!coversAlternate.hasConsistentFields(readAt: 1, sectorSize: 512, sectorCount: 16384))
    }
}
