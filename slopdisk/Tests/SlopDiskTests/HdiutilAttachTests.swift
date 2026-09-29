//
//  HdiutilAttachTests.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//
//  (c) Attaches images this test just created. Runs only with SLOPDISK_TEST_HDIUTIL_ATTACH=1.
//
//  Safety: the only device paths used here are parsed from the output of the `hdiutil attach` that the same
//  test ran on its own temporary image, and they are validated against ^/dev/r?disk[0-9]+(s[0-9]+)?$ first.
//  Images are always attached with -nomount, and detached in a defer.
//

import Foundation
import Testing
@testable import SlopDisk

@Suite(.serialized, .enabled(if: Tools.attachEnabled, "set SLOPDISK_TEST_HDIUTIL_ATTACH=1 to attach temporary images"))
struct HdiutilAttachTests {
    struct Attachment {
        /// `/dev/diskN`
        var wholeDisk: String
        var scheme: String
        /// `/dev/diskNsK`, in output order.
        var slices: [String]

        func raw(_ path: String) -> String {
            path.replacingOccurrences(of: "/dev/disk", with: "/dev/rdisk")
        }
    }

    static func attach(_ image: String) throws -> Attachment {
        let result = try Tools.run(Tools.hdiutil, [
            "attach", "-nomount", "-imagekey", "diskimage-class=CRawDiskImage", image,
        ])
        try #require(result.status == 0, "hdiutil attach failed: \(result.stderr)")
        let rows = result.stdout.split(separator: "\n").map { line in
            line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
        }.filter { !$0.isEmpty }
        let first = try #require(rows.first, "hdiutil attach printed nothing")
        let wholeDisk = first[0]
        try #require(isWholeDiskPath(wholeDisk), "unexpected device path '\(wholeDisk)' from hdiutil attach")
        let slices = rows.dropFirst().map { $0[0] }
        for slice in slices {
            try #require(isSliceDevicePath(slice) && slice.hasPrefix(wholeDisk + "s"), "unexpected slice path '\(slice)'")
        }
        return Attachment(wholeDisk: wholeDisk, scheme: first.dropFirst().joined(separator: " "), slices: slices)
    }

    /// Detaches every device whose backing image is `image`, found via `hdiutil info`, so that cleanup works even
    /// when parsing the attach output failed. Only devices backed by this test's own image are touched.
    static func detachAll(backedBy image: String) {
        guard let result = try? Tools.run(Tools.hdiutil, ["info", "-plist"]),
              let plist = try? PropertyListSerialization.propertyList(from: Data(result.stdout.utf8), format: nil),
              let images = (plist as? [String: Any])?["images"] as? [[String: Any]]
        else {
            return
        }
        let target = URL(fileURLWithPath: image).resolvingSymlinksInPath().path
        for entry in images {
            guard let imagePath = entry["image-path"] as? String,
                  URL(fileURLWithPath: imagePath).resolvingSymlinksInPath().path == target,
                  let entities = entry["system-entities"] as? [[String: Any]]
            else {
                continue
            }
            let devices = entities.compactMap { $0["dev-entry"] as? String }.filter(isWholeDiskPath)
            for device in devices {
                if (try? Tools.run(Tools.hdiutil, ["detach", device]))?.status != 0 {
                    _ = try? Tools.run(Tools.hdiutil, ["detach", "-force", device])
                }
            }
        }
    }

    // MARK: T14

    @Test func attachedTableFormatsAsFAT32() throws {
        try withTemporaryDirectory { directory in
            let image = directory + "/t3.img"
            try makeT3Image(at: image)
            defer { Self.detachAll(backedBy: image) }

            let attachment = try Self.attach(image)
            #expect(attachment.scheme == "GUID_partition_scheme")
            #expect(attachment.slices.count == 2)
            let data = try #require(attachment.slices.first { $0.hasSuffix("s2") })
            let rawData = attachment.raw(data)
            try #require(isSliceDevicePath(rawData))

            let newfs = try Tools.run(Tools.newfsMSDOS, ["-F", "32", "-v", "WIN11ISO", rawData])
            #expect(newfs.status == 0, "newfs_msdos failed: \(newfs.stderr)")
            let fsck = try Tools.run(Tools.fsckMSDOS, ["-n", rawData])
            #expect(fsck.status == 0, "fsck_msdos failed: \(fsck.stdout) \(fsck.stderr)")

            let detach = try Tools.run(Tools.hdiutil, ["detach", attachment.wholeDisk])
            #expect(detach.status == 0, "hdiutil detach failed: \(detach.stderr)")

            // The partition table itself is untouched by formatting a partition.
            let disk = try SDDiskImage.open(.file(image), mode: .readOnly)
            #expect(disk.scheme == .gpt(.healthy))
            #expect(disk.partitions.map(\.label) == ["EFI", "WIN11ISO"])
        }
    }
}
