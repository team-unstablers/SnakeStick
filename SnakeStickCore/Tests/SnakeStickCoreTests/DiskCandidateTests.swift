// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SnakeStickCore

/// DiskArbitration descriptions trimmed from `DADiskCopyDescription` on the development machine
/// (2026-09-30): the internal SSD, an APFS synthesized disk on it, a disk image, a USB stick.
enum DiskFixtures {
    nonisolated(unsafe) static let internalSSD: [String: Any] = [
        "DAMediaBSDName": "disk0", "DAMediaWhole": true, "DADeviceInternal": true, "DAMediaRemovable": false,
        "DAMediaWritable": true, "DADeviceProtocol": "Apple Fabric", "DADeviceModel": "APPLE SSD AP1024R",
        "DADeviceVendor": "", "DAMediaContent": "GUID_partition_scheme", "DAMediaSize": 1_000_555_581_440,
        "DADevicePath": "IOService:/AppleARMPE/arm-io/AppleT600xIO/ans@8F400000/AppleASCWrapV4/iop-ans-nub",
    ]
    nonisolated(unsafe) static let apfsSynthesized: [String: Any] = [
        "DAMediaBSDName": "disk3", "DAMediaWhole": true, "DADeviceInternal": true, "DAMediaRemovable": false,
        "DAMediaWritable": true, "DADeviceProtocol": "Apple Fabric", "DADeviceModel": "APPLE SSD AP1024R",
        "DAMediaContent": "EF57347C-0000-11AA-AA11-00306543ECAC",
    ]
    nonisolated(unsafe) static let diskImage: [String: Any] = [
        "DAMediaBSDName": "disk4", "DAMediaWhole": true, "DAMediaRemovable": true, "DAMediaEjectable": true,
        "DAMediaWritable": true, "DADeviceProtocol": "Virtual Interface", "DADeviceModel": "Disk Image",
        "DADevicePath": "IOService:/IOResources/AppleDiskImagesController/AppleDiskImageDevice@9",
        "DAMediaContent": "GUID_partition_scheme",
    ]
    nonisolated(unsafe) static let usbStick: [String: Any] = [
        "DAMediaBSDName": "disk7", "DAMediaWhole": true, "DADeviceInternal": false, "DAMediaRemovable": true,
        "DAMediaWritable": true, "DADeviceProtocol": "USB", "DADeviceModel": " Sandisk 3.2Gen1",
        "DADeviceVendor": " USB", "DAMediaContent": "GUID_partition_scheme", "DAMediaSize": 61_964_550_144,
    ]
    nonisolated(unsafe) static let usbPartition: [String: Any] = usbStick.merging(["DAMediaBSDName": "disk7s1", "DAMediaWhole": false]) { $1 }

    static func with(_ base: [String: Any], _ changes: [String: Any]) -> [String: Any] {
        base.merging(changes) { $1 }
    }
}

struct DiskClassificationTests {
    let boot: Set<String> = ["disk3", "disk0"]

    @Test func usbStickIsEligible() {
        let verdict = DiskCandidate.classify(description: DiskFixtures.usbStick, bootWholeDisks: boot)
        #expect(verdict.isEligible)
        #expect(verdict.ineligibleReason == nil)
        #expect(!verdict.isInternal && verdict.isRemovable && !verdict.isVirtual && !verdict.isBootDisk)
    }

    @Test func internalDiskIsExcluded() {
        let verdict = DiskCandidate.classify(description: DiskFixtures.internalSSD, bootWholeDisks: [])
        #expect(!verdict.isEligible)
        #expect(verdict.ineligibleReason == "internal disk")
    }

    @Test func bootDiskIsExcludedEvenWhenExternal() {
        let externalBoot = DiskFixtures.with(DiskFixtures.usbStick, ["DAMediaBSDName": "disk0"])
        let verdict = DiskCandidate.classify(description: externalBoot, bootWholeDisks: boot)
        #expect(verdict.isBootDisk)
        #expect(!verdict.isEligible)
        #expect(verdict.ineligibleReason == "startup disk")
    }

    @Test func diskImageIsExcludedAlthoughRemovable() {
        let verdict = DiskCandidate.classify(description: DiskFixtures.diskImage, bootWholeDisks: boot)
        #expect(verdict.isVirtual)
        #expect(!verdict.isEligible)
        // Each of the image markers suffices on its own.
        for key in ["DADeviceProtocol", "DADeviceModel", "DADevicePath"] {
            var description = DiskFixtures.usbStick
            description[key] = DiskFixtures.diskImage[key]
            #expect(!DiskCandidate.classify(description: description, bootWholeDisks: boot).isEligible, "\(key)")
        }
    }

    @Test func apfsSynthesizedDiskIsExcludedEvenOnAnExternalStore() {
        let externalSynthesized = DiskFixtures.with(DiskFixtures.usbStick, [
            "DAMediaBSDName": "disk8", "DAMediaContent": "EF57347C-0000-11AA-AA11-00306543ECAC",
        ])
        #expect(!DiskCandidate.classify(description: externalSynthesized, bootWholeDisks: boot).isEligible)
        #expect(!DiskCandidate.classify(description: DiskFixtures.usbStick, bootWholeDisks: boot, isSynthesized: true).isEligible)
    }

    @Test func externalNonRemovableDiskIsEligible() {
        let ssd = DiskFixtures.with(DiskFixtures.usbStick, ["DAMediaRemovable": false])
        #expect(DiskCandidate.classify(description: ssd, bootWholeDisks: boot).isEligible)
    }

    @Test func internalRemovableDiskIsEligible() {
        // Built-in SD card readers report internal, removable media.
        let sdCard = DiskFixtures.with(DiskFixtures.usbStick, ["DADeviceInternal": true, "DADeviceProtocol": "Secure Digital"])
        #expect(DiskCandidate.classify(description: sdCard, bootWholeDisks: boot).isEligible)
    }

    @Test func missingInternalKeyCountsAsInternal() {
        var description = DiskFixtures.usbStick
        description["DADeviceInternal"] = nil
        description["DAMediaRemovable"] = false
        #expect(!DiskCandidate.classify(description: description, bootWholeDisks: boot).isEligible)
    }

    @Test func partitionsAndReadOnlyMediaAreExcluded() {
        #expect(DiskCandidate.classify(description: DiskFixtures.usbPartition, bootWholeDisks: boot).ineligibleReason == "not a whole disk")
        let locked = DiskFixtures.with(DiskFixtures.usbStick, ["DAMediaWritable": false])
        #expect(DiskCandidate.classify(description: locked, bootWholeDisks: boot).ineligibleReason == "read-only media")
    }

    @Test func modelDropsGenericVendor() {
        #expect(DiskCandidate.displayModel(description: DiskFixtures.usbStick) == "Sandisk 3.2Gen1")
        let named = DiskFixtures.with(DiskFixtures.usbStick, ["DADeviceVendor": "SanDisk", "DADeviceModel": "Ultra USB 3.0"])
        #expect(DiskCandidate.displayModel(description: named) == "SanDisk Ultra USB 3.0")
        let repeated = DiskFixtures.with(DiskFixtures.usbStick, ["DADeviceVendor": "Samsung", "DADeviceModel": "Samsung T7"])
        #expect(DiskCandidate.displayModel(description: repeated) == "Samsung T7")
    }

    @Test(arguments: [("disk4", true), ("disk12", true), ("disk4s1", false), ("rdisk4", false), ("/dev/disk4", false), ("disk", false), ("disk-1", false)])
    func wholeDiskNames(name: String, valid: Bool) {
        #expect(DiskCandidate.isWholeDiskName(name) == valid)
    }
}

/// Runs against this machine's real disks, read-only.
struct LiveDiskTests {
    @Test func startupDiskIsFound() throws {
        let boot = startupWholeDisks()
        #expect(!boot.isEmpty)
        var info = statfs()
        #expect(statfs("/", &info) == 0)
        let from = withUnsafeBytes(of: info.f_mntfromname) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        // "/dev/disk3s1s1" lives on "disk3".
        let whole = from.firstMatch(of: #/disk[0-9]+/#).map { String($0.output) }
        #expect(whole.map { boot.contains($0) } == true, "\(from) -> \(boot)")
    }

    @Test func candidatesNeverIncludeTheStartupDisk() throws {
        let boot = startupWholeDisks()
        let candidates = try listDiskCandidates()
        #expect(candidates.allSatisfy { !$0.isBootDisk && !boot.contains($0.bsdName) })
        #expect(candidates.allSatisfy { $0.isEligible && !$0.isVirtual && (!$0.isInternal || $0.isRemovable) })
        let all = try listWholeDisks()
        #expect(all.contains { boot.contains($0.bsdName) && !$0.isEligible })
    }
}
