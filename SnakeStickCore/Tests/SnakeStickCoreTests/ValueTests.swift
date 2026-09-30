import Foundation
import Testing
@testable import SnakeStickCore

struct SISizeTests {
    @Test(arguments: [
        ("8G", UInt64(8_000_000_000)),
        ("7.5G", 7_500_000_000),
        ("8g", 8_000_000_000),
        ("8GB", 8_000_000_000),
        ("500M", 500_000_000),
        ("1.5K", 1500),
        ("2T", 2_000_000_000_000),
        ("123", 123),
        ("7.50G", 7_500_000_000),
        (" 16G ", 16_000_000_000),
    ])
    func parses(text: String, bytes: UInt64) {
        #expect(SISize.parse(text) == bytes)
    }

    @Test(arguments: ["", "G", "0", "0G", "-1G", "1.0005K", "1.5", "8GiB", "8 G", "1e9", "1..5G", ".5G", "5.G", "99999999999T"])
    func rejects(text: String) {
        #expect(SISize.parse(text) == nil)
    }

    @Test func gigabyteIsNotBinary() {
        // C11: SDSize.gigabytes is 1024-based; --imgsize must not be.
        #expect(SISize.parse("8G") != 8 * 1024 * 1024 * 1024)
    }
}

struct VolumeLabelTests {
    @Test(arguments: ["", "WINDOWS", "CCCOMA_X64FRE_EN-US_DV9", "윈도우 설치", String(repeating: "A", count: 32), "CON"])
    func accepts(label: String) {
        #expect(VolumeLabel.isValid(label))
    }

    @Test(arguments: [String(repeating: "A", count: 33), "a:b", "a/b", "a\\b", "a|b", "a?", "a*", "a<b", "a>b", "a\"b",
                      "trailing ", "trailing.", "tab\there", "😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀"])
    func rejects(label: String) {
        #expect(!VolumeLabel.isValid(label))
    }

    @Test func resolveOrder() {
        #expect(VolumeLabel.resolve(requested: "MINE", isoLabel: "ISO") == "MINE")
        #expect(VolumeLabel.resolve(requested: nil, isoLabel: "CCCOMA_X64FRE") == "CCCOMA_X64FRE")
        #expect(VolumeLabel.resolve(requested: nil, isoLabel: "") == "WINDOWS")
        #expect(VolumeLabel.resolve(requested: nil, isoLabel: "BAD:LABEL") == "WINDOWS")
    }

    @Test func partitionNameIsCutToGPTLimit() {
        #expect(VolumeLabel.partitionName(for: "WINDOWS") == "WINDOWS")
        #expect(VolumeLabel.partitionName(for: String(repeating: "가", count: 40)).utf16.count == 36)
        #expect(VolumeLabel.partitionName(for: String(repeating: "😀", count: 20)).utf16.count == 36)
    }
}

struct ModelTests {
    @Test func eventsRoundTripThroughJSON() throws {
        let events: [InstallerEvent] = [
            .progress(.init(phase: .copyFiles, fraction: 0.5, detail: "/sources/install.wim", estimatedRemaining: 120)),
            .log("$ hdiutil attach -> 0"),
            .finished(.init(elapsed: 372, verified: true)),
            .failed(.init(phase: .copyFiles, kind: .io, message: "I/O error", underlying: "EIO", targetModified: true, path: "/sources/install.wim", errno: EIO)),
        ]
        let data = try JSONEncoder().encode(events)
        #expect(try JSONDecoder().decode([InstallerEvent].self, from: data) == events)
    }

    @Test func requestRoundTripsThroughJSON() throws {
        let request = InstallerRequest(
            isoPath: "/tmp/win.iso",
            target: .image(path: "/tmp/out.img", size: 8_000_000_000),
            options: .init(volumeLabel: "WIN", verifyAfterWrite: false, useCA2023Bootloaders: true)
        )
        #expect(try JSONDecoder().decode(InstallerRequest.self, from: JSONEncoder().encode(request)) == request)
    }

    @Test func phasesAreNumberedOneToEight() {
        #expect(Phase.allCases.map(\.rawValue) == Array(1 ... 8))
    }

    @Test func errorStateFollowsModification() {
        let error = InstallerError(phase: .openISO, kind: .invalidISO, message: "x")
        #expect(!error.targetModified)
        #expect(error.markingTargetModified.targetModified)
        #expect(error.markingTargetModified.targetState != error.targetState)
    }
}

struct HdiutilParsingTests {
    @Test func picksTheWholeDiskWhateverItsPosition() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>system-entities</key><array>
        <dict><key>dev-entry</key><string>/dev/disk23s1</string><key>mount-point</key><string>/tmp/x/iso</string></dict>
        <dict><key>content-hint</key><string>GUID_partition_scheme</string><key>dev-entry</key><string>/dev/disk23</string></dict>
        </array></dict></plist>
        """
        let attachment = try DiskTools.parseAttachment(Data(("Checksumming...\n" + plist).utf8))
        #expect(attachment.device == "/dev/disk23")
        #expect(attachment.mountPoint == "/tmp/x/iso")
    }

    @Test func rejectsOutputWithoutWholeDisk() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>system-entities</key><array>
        <dict><key>dev-entry</key><string>/dev/disk23s1</string></dict>
        </array></dict></plist>
        """
        #expect(throws: DiskToolError.self) { try DiskTools.parseAttachment(Data(plist.utf8)) }
    }
}
