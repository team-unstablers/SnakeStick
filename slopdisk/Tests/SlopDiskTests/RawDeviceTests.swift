//
//  RawDeviceTests.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//
//  SDRawDevice.
//  - RawDeviceTests never opens a device. It covers the rejection paths with regular files and directories only.
//  - RawDeviceAttachTests (RT1–RT7 of Prompts/20-raw-device.xml) runs only with SLOPDISK_TEST_HDIUTIL_ATTACH=1.
//
//  Safety: the only device paths used here are derived from the output of the `hdiutil attach` that the same test
//  ran on its own temporary image, and they are validated against ^/dev/r?disk[0-9]+(s[0-9]+)?$ before use.
//  Images are always attached with -nomount, and detached in a defer.
//

import Foundation
import Testing
@testable import SlopDisk

@Suite struct RawDeviceTests {
    @Test func regularFileIsRejected() throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/disk.img"
            try makeT3Image(at: path)
            let before = try fileBytes(path)
            expectInvalidArgument { try SDRawDevice(readOnlyPath: path) }
            expectInvalidArgument { try SDRawDevice(path: path, acknowledging: .dataLossRisk) }
            #expect(try fileBytes(path) == before)
            // Nothing was left open or locked.
            _ = try SDFileBlockDevice(path: path, mode: .readWrite, sectorSize: 512)
        }
    }

    @Test func directoryIsRejected() throws {
        try withTemporaryDirectory { directory in
            expectInvalidArgument { try SDRawDevice(readOnlyPath: directory) }
        }
    }

    @Test func missingPathIsIOError() throws {
        try withTemporaryDirectory { directory in
            expectError(.io(operation: "open", errno: ENOENT)) {
                try SDRawDevice(readOnlyPath: directory + "/missing")
            }
        }
    }

    @Test(arguments: [false, true])
    func injectedRegularFileIsRejectedAndLeftOpen(closeOnDeinit: Bool) throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/disk.img"
            try makeT3Image(at: path)
            let fd = open(path, O_RDWR | O_CLOEXEC)
            try #require(fd >= 0)
            defer { close(fd) }
            expectInvalidArgument {
                try SDRawDevice(fileDescriptor: fd, closeOnDeinit: closeOnDeinit, acknowledging: .dataLossRisk)
            }
            #expect(fcntl(fd, F_GETFD) != -1, "a failed init leaves the descriptor open")
            _ = try SDFileBlockDevice(path: path, mode: .readWrite, sectorSize: 512)
        }
    }

    @Test func writeOnlyDescriptorIsRejected() throws {
        try withTemporaryDirectory { directory in
            let path = directory + "/disk.img"
            try makeT3Image(at: path)
            let fd = open(path, O_WRONLY | O_CLOEXEC)
            try #require(fd >= 0)
            defer { close(fd) }
            expectInvalidArgument {
                try SDRawDevice(fileDescriptor: fd, closeOnDeinit: false, acknowledging: .dataLossRisk)
            }
        }
    }

    @Test func invalidDescriptorIsIOError() {
        expectError(.io(operation: "fcntl(F_GETFL)", errno: EBADF)) {
            try SDRawDevice(fileDescriptor: -1, closeOnDeinit: false, acknowledging: .dataLossRisk)
        }
    }
}

@Suite(.serialized, .enabled(if: Tools.attachEnabled, "set SLOPDISK_TEST_HDIUTIL_ATTACH=1 to attach temporary images"))
struct RawDeviceAttachTests {
    /// A 64 MiB image of this test, attached with -nomount.
    struct AttachedImage {
        var image: String
        var attachment: HdiutilAttachTests.Attachment
        /// `/dev/rdiskN`, validated.
        var rawDisk: String

        /// Waits until the kernel has published slice `index` of this image and returns it as `/dev/rdiskNsK`.
        /// Slices appear asynchronously after a device that was opened for writing is closed.
        func rawSlice(_ index: Int, timeout: TimeInterval = 10) throws -> String {
            let slice = attachment.wholeDisk + "s\(index)"
            try #require(isSliceDevicePath(slice), "unexpected slice path '\(slice)'")
            let deadline = Date().addingTimeInterval(timeout)
            while !HdiutilAttachTests.deviceEntries(backedBy: image).contains(slice) {
                try #require(Date() < deadline, "\(slice) did not appear within \(timeout) s")
                Thread.sleep(forTimeInterval: 0.1)
            }
            let raw = attachment.raw(slice)
            try #require(raw.wholeMatch(of: /\/dev\/rdisk[0-9]+s[0-9]+/) != nil && raw.hasPrefix(rawDisk + "s"))
            return raw
        }

        /// Detaches the image. Every descriptor on it must be closed first.
        func detach() throws {
            let result = try Tools.run(Tools.hdiutil, ["detach", attachment.wholeDisk])
            #expect(result.status == 0, "hdiutil detach failed: \(result.stderr)")
        }
    }

    static func makeBlankImage(at path: String) throws {
        _ = try SDDiskImage.create(.file(path), desiredSize: .megabytes(64))
    }

    /// Creates an image with `prepare` in a fresh directory, attaches it, and detaches whatever is left at the end.
    static func withAttachedImage<R>(
        prepare: (String) throws -> Void = makeBlankImage, _ body: (AttachedImage) throws -> R
    ) throws -> R {
        try withTemporaryDirectory { directory in
            let image = directory + "/disk.img"
            try prepare(image)
            defer { HdiutilAttachTests.detachAll(backedBy: image) }
            let attachment = try HdiutilAttachTests.attach(image)
            let rawDisk = attachment.raw(attachment.wholeDisk)
            try #require(rawDisk.wholeMatch(of: /\/dev\/rdisk[0-9]+/) != nil, "unexpected raw device path '\(rawDisk)'")
            return try body(AttachedImage(image: image, attachment: attachment, rawDisk: rawDisk))
        }
    }

    /// The image file holds the T3 layout as SlopDisk and gpt(8) read it.
    static func expectT3Image(_ image: String, partitions: [SDPartition]) throws {
        let disk = try SDDiskImage.open(.file(image), mode: .readOnly)
        #expect(disk.scheme == .gpt(.healthy))
        #expect(disk.partitions == partitions)
        #expect(disk.partitions.map(\.label) == ["EFI", "WIN11ISO"])
        try #require(Tools.hasGPT, "requires /usr/sbin/gpt")
        #expect(try ToolCrossCheckTests.gptShow(image) == ToolCrossCheckTests.t3Rows)
    }

    // MARK: RT1

    @Test func readOnlyOpen() throws {
        try Self.withAttachedImage { attached in
            do {
                let device = try SDRawDevice(readOnlyPath: attached.rawDisk)
                #expect(device.path == attached.rawDisk)
                #expect(device.sectorSize == 512)
                #expect(device.sectorCount == 131_072)
                #expect(device.isReadOnly)
                let before = try device.readSectors(lba: 0, count: 64)
                expectError(.readOnly) {
                    try device.writeSectors(lba: 0, [UInt8](repeating: 0xA5, count: 512))
                }
                #expect(try device.readSectors(lba: 0, count: 64) == before)
                #expect(try SDDisk(device: device).scheme == .none)
            }
            try attached.detach()
            #expect(try fileBytes(attached.image) == [UInt8](repeating: 0, count: 64 << 20), "the image is still blank")
        }
    }

    // MARK: RT2

    @Test func writeRoundTripByPath() throws {
        try Self.withAttachedImage { attached in
            let partitions: [SDPartition]
            do {
                let device = try SDRawDevice(path: attached.rawDisk, acknowledging: .dataLossRisk)
                #expect(device.path == attached.rawDisk)
                #expect(!device.isReadOnly)
                #expect(device.sectorSize == 512)
                #expect(device.sectorCount == 131_072)
                let disk = try SDDisk(device: device)
                #expect(disk.scheme == .none)
                try writeT3Layout(disk)
                #expect(disk.scheme == .gpt(.healthy))
                partitions = disk.partitions
            }
            try attached.detach()
            try Self.expectT3Image(attached.image, partitions: partitions)
        }
    }

    // MARK: RT3

    @Test func writeRoundTripByInjectedDescriptor() throws {
        try Self.withAttachedImage { attached in
            let fd = open(attached.rawDisk, O_RDWR | O_CLOEXEC)
            try #require(fd >= 0, "open failed: errno \(errno)")
            var isOpen = true
            defer {
                if isOpen {
                    close(fd)
                }
            }

            let partitions: [SDPartition]
            do {
                let device = try SDRawDevice(fileDescriptor: fd, closeOnDeinit: false, acknowledging: .dataLossRisk)
                #expect(device.path == nil)
                #expect(!device.isReadOnly)
                #expect(device.sectorSize == 512)
                #expect(device.sectorCount == 131_072)
                // A borrowed descriptor is not locked, so an exclusive open by path still succeeds.
                _ = try SDRawDevice(path: attached.rawDisk, acknowledging: .dataLossRisk)
                let disk = try SDDisk(device: device)
                try writeT3Layout(disk)
                #expect(disk.scheme == .gpt(.healthy))
                partitions = disk.partitions
            }
            #expect(fcntl(fd, F_GETFD) != -1, "the borrowed descriptor must stay open")
            // No lock was left behind on the caller's open file description.
            _ = try SDRawDevice(path: attached.rawDisk, acknowledging: .dataLossRisk)
            #expect(close(fd) == 0)
            isOpen = false

            try attached.detach()
            try Self.expectT3Image(attached.image, partitions: partitions)
        }
    }

    // MARK: RT4

    @Test func locking() throws {
        try Self.withAttachedImage { attached in
            let raw = attached.rawDisk
            do {
                let writer = try SDRawDevice(path: raw, acknowledging: .dataLossRisk)
                expectError(.locked(path: raw)) { try SDRawDevice(path: raw, acknowledging: .dataLossRisk) }
                expectError(.locked(path: raw)) { try SDRawDevice(readOnlyPath: raw) }
                withExtendedLifetime(writer) {}
            }
            do {
                // Read-only opens share the lock and keep a read-write open out.
                let reader1 = try SDRawDevice(readOnlyPath: raw)
                let reader2 = try SDRawDevice(readOnlyPath: raw)
                expectError(.locked(path: raw)) { try SDRawDevice(path: raw, acknowledging: .dataLossRisk) }
                withExtendedLifetime((reader1, reader2)) {}
            }
            do {
                // An owned descriptor is locked while the device lives, and closed (which unlocks it) on deinit.
                let fd = open(raw, O_RDWR | O_CLOEXEC)
                try #require(fd >= 0, "open failed: errno \(errno)")
                var owner: SDRawDevice? = try SDRawDevice(fileDescriptor: fd, closeOnDeinit: true, acknowledging: .dataLossRisk)
                #expect(owner?.path == nil)
                expectError(.locked(path: raw)) { try SDRawDevice(path: raw, acknowledging: .dataLossRisk) }
                owner = nil
                _ = try SDRawDevice(path: raw, acknowledging: .dataLossRisk)
            }
        }
    }

    // MARK: RT5

    @Test func regularFileIsRejected() throws {
        try Self.withAttachedImage { attached in
            expectInvalidArgument { try SDRawDevice(readOnlyPath: attached.image) }
            expectInvalidArgument { try SDRawDevice(path: attached.image, acknowledging: .dataLossRisk) }
        }
    }

    // MARK: RT6

    @Test func sdinspectReadsDevice() throws {
        try Self.withAttachedImage(prepare: { try makeT3Image(at: $0) }) { attached in
            let before = try fileBytes(attached.image)

            let result = try SDInspectBinary.run([attached.rawDisk])
            #expect(result.status == 0, "sdinspect failed: \(result.stderr)")
            #expect(result.stdout.contains("scheme      : GPT (healthy)"))
            #expect(result.stdout.contains("sector size : 512   sectors: 131072"))
            #expect(result.stdout.contains("WIN11ISO"))

            let hex = try SDInspectBinary.run(["--hex", attached.rawDisk])
            #expect(hex.status == 0)
            #expect(hex.stdout.contains("|EFI PART"))

            let usage = try SDInspectBinary.run(["--sector-size", "512", attached.rawDisk])
            #expect(usage.status == 64)
            #expect(usage.stderr.contains("usage: sdinspect"))

            do {
                // sdinspect takes a shared lock, so it cannot read while a writer holds the device.
                let writer = try SDRawDevice(path: attached.rawDisk, acknowledging: .dataLossRisk)
                let locked = try SDInspectBinary.run([attached.rawDisk])
                #expect(locked.status == 74)
                #expect(locked.stderr.contains("locked by another process"))
                withExtendedLifetime(writer) {}
            }

            try attached.detach()
            #expect(try fileBytes(attached.image) == before, "sdinspect modified the device")
        }
    }

    // MARK: RT7

    /// SlopDisk writes the table only; the file system comes from the system tools (D4).
    @Test func fat32OnSliceAfterRawWrite() throws {
        try Self.withAttachedImage { attached in
            let partitions: [SDPartition]
            do {
                let disk = try SDDisk(device: SDRawDevice(path: attached.rawDisk, acknowledging: .dataLossRisk))
                try writeT3Layout(disk)
                partitions = disk.partitions
            }
            // Closing the device makes the kernel re-read the table and publish the slices.
            let slice = try attached.rawSlice(2)

            let newfs = try Tools.run(Tools.newfsMSDOS, ["-F", "32", "-v", "WIN11ISO", slice])
            #expect(newfs.status == 0, "newfs_msdos failed: \(newfs.stderr)")
            let fsck = try Tools.run(Tools.fsckMSDOS, ["-n", slice])
            #expect(fsck.status == 0, "fsck_msdos failed: \(fsck.stdout) \(fsck.stderr)")

            try attached.detach()
            // Formatting a partition leaves the table alone.
            let disk = try SDDiskImage.open(.file(attached.image), mode: .readOnly)
            #expect(disk.scheme == .gpt(.healthy))
            #expect(disk.partitions == partitions)
        }
    }

    // MARK: Additional checks

    /// Transfers larger than the 1 MiB bounce buffer, from and into buffers that are deliberately misaligned.
    @Test func largeMisalignedTransfers() throws {
        try Self.withAttachedImage { attached in
            let lba: UInt64 = 1000
            let byteCount = (5 << 19) + 3 * 512  // 2.5 MiB + 3 sectors: three chunks, the last one partial
            let pattern = (0 ..< byteCount).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ $0 >> 9) }
            do {
                let device = try SDRawDevice(path: attached.rawDisk, acknowledging: .dataLossRisk)
                var source = [UInt8](repeating: 0, count: byteCount + 1)
                source.replaceSubrange(1..., with: pattern)
                try source.withUnsafeBytes { raw in
                    try device.write(lba: lba, from: UnsafeRawBufferPointer(rebasing: raw[1...]))
                }
                try device.synchronize()
                var destination = [UInt8](repeating: 0, count: byteCount + 1)
                try destination.withUnsafeMutableBytes { raw in
                    try device.read(lba: lba, into: UnsafeMutableRawBufferPointer(rebasing: raw[1...]))
                }
                #expect(Array(destination[1...]) == pattern)

                // The SDBlockDevice contract is checked before anything reaches the device.
                expectInvalidArgument { try device.readSectors(lba: device.sectorCount, count: 1) }
                expectInvalidArgument { try device.writeSectors(lba: 0, [UInt8](repeating: 0, count: 100)) }
            }
            try attached.detach()
            let offset = Int(lba) * 512
            #expect(Array(try fileBytes(attached.image)[offset ..< offset + byteCount]) == pattern)
        }
    }

    /// `/dev/diskN` (the buffered block device) is accepted as well; its `synchronize()` runs fsync first.
    @Test func bufferedBlockDeviceRoundTrip() throws {
        try Self.withAttachedImage { attached in
            let blockDisk = attached.attachment.wholeDisk
            try #require(blockDisk.wholeMatch(of: /\/dev\/disk[0-9]+/) != nil, "unexpected device path '\(blockDisk)'")
            let partitions: [SDPartition]
            do {
                let device = try SDRawDevice(path: blockDisk, acknowledging: .dataLossRisk)
                #expect(device.sectorSize == 512)
                #expect(device.sectorCount == 131_072)
                let disk = try SDDisk(device: device)
                try writeT3Layout(disk)
                #expect(disk.scheme == .gpt(.healthy))
                partitions = disk.partitions
            }
            try attached.detach()
            try Self.expectT3Image(attached.image, partitions: partitions)
        }
    }
}
