//
//  SizeTests.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

import Testing
@testable import SlopDisk

@Suite struct SizeTests {
    @Test func binaryUnits() {
        #expect(SDSize.megabytes(400).bytes == 419_430_400)
        #expect(SDSize.kilobytes(1).bytes == 1024)
        #expect(SDSize.gigabytes(1).bytes == 1 << 30)
        #expect(SDSize.terabytes(8).bytes == 8 << 40)
        #expect(SDSize.bytes(UInt8(7)).bytes == 7)
    }

    @Test func descriptions() {
        #expect(SDSize.megabytes(400).description == "400 MiB")
        #expect(SDSize.megabytes(8192).description == "8 GiB")
        #expect(SDSize.bytes(512).description == "512 B")
        #expect(SDSize.bytes(1536).description == "1.5 KiB")
        #expect(SDSize.bytes(0).description == "0 B")
        #expect(SDSize.bytes(1023).description == "1023 B")
        #expect(SDSize.kilobytes(1).description == "1 KiB")
        #expect(SDSize.bytes(1024 + 51).description == "1.05 KiB")
        #expect(SDSize.bytes(2047).description == "2 KiB", "1.999 rounds to 2")
        #expect(SDSize.terabytes(8).description == "8 TiB")
        #expect(SDSize.gigabytes(16).description == "16 GiB")
        #expect(SDSize(bytes: .max).description == "16777216 TiB")
    }

    @Test func ordering() {
        #expect(SDSize.kilobytes(1) < SDSize.megabytes(1))
        #expect(SDSize.bytes(1024) == SDSize.kilobytes(1))
    }

    @Test func extentFactoriesMatchSizeFactories() {
        #expect(SDPartitionExtent.bytes(10) == .size(.bytes(10)))
        #expect(SDPartitionExtent.kilobytes(10) == .size(.kilobytes(10)))
        #expect(SDPartitionExtent.megabytes(400) == .size(.megabytes(400)))
        #expect(SDPartitionExtent.gigabytes(2) == .size(.gigabytes(2)))
        #expect(SDPartitionExtent.terabytes(1) == .size(.terabytes(1)))
        #expect(SDPartitionExtent.remaining != .size(.bytes(0)))
    }
}
