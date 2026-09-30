// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SnakeStickCore

struct WindowsVersionTests {
    @Test(arguments: [
        (26200, "Windows 11 25H2"), (26100, "Windows 11 24H2"), (22631, "Windows 11 23H2"),
        (22621, "Windows 11 22H2"), (22000, "Windows 11 21H2"), (19045, "Windows 10 22H2"),
        (19044, "Windows 10 21H2"),
    ])
    func knownBuilds(build: Int, name: String) {
        #expect(ISOInfo.windowsVersion(build: build, major: 10) == name)
    }

    @Test func unknownBuildsShowTheNumber() {
        #expect(ISOInfo.windowsVersion(build: 27000, major: 10) == "Windows 11 (build 27000)")
        #expect(ISOInfo.windowsVersion(build: 19041, major: 10) == "Windows 10 (build 19041)")
        #expect(ISOInfo.windowsVersion(build: 22001, major: nil) == "Windows 11 (build 22001)")
    }

    @Test func architectureNames() {
        #expect(ISOInfo.architectureName(.x64) == "x64")
        #expect(ISOInfo.architectureName(.arm64) == "ARM64")
        #expect(ISOInfo.architectureName(.x86) == "x86")
    }

    @Test func requiredBytesAddsFiveMebibytes() {
        #expect(ISOInfo.requiredBytes(forVolumeEstimate: 7 << 30) == (7 << 30) + 5 * 1_048_576)
    }
}

struct PrimaryVolumeDescriptorTests {
    static func descriptor(label: String, type: UInt8 = 1) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 2048)
        bytes[0] = type
        bytes.replaceSubrange(1 ..< 6, with: Array("CD001".utf8))
        bytes[6] = 1
        let field = Array(label.utf8) + [UInt8](repeating: 0x20, count: 32 - label.utf8.count)
        bytes.replaceSubrange(40 ..< 72, with: field)
        return bytes
    }

    @Test func readsTheLabelWithoutPadding() {
        #expect(ISOImage.parseVolumeLabel(primaryDescriptor: Self.descriptor(label: "CCCOMA_X64FRE_EN-US_DV9")) == "CCCOMA_X64FRE_EN-US_DV9")
        #expect(ISOImage.parseVolumeLabel(primaryDescriptor: Self.descriptor(label: String(repeating: "A", count: 32))) == String(repeating: "A", count: 32))
        #expect(ISOImage.parseVolumeLabel(primaryDescriptor: Self.descriptor(label: "")) == "")
    }

    @Test func ignoresOtherDescriptors() {
        #expect(ISOImage.parseVolumeLabel(primaryDescriptor: Self.descriptor(label: "X", type: 2)) == nil)
        var bad = Self.descriptor(label: "X")
        bad[3] = UInt8(ascii: "X")
        #expect(ISOImage.parseVolumeLabel(primaryDescriptor: bad) == nil)
        #expect(ISOImage.parseVolumeLabel(primaryDescriptor: [1, 2, 3]) == nil)
    }

    @Test func readsTheLabelFromAFile() throws {
        let scratch = try ScratchDirectory()
        let path = scratch.path("pvd.iso")
        var image = [UInt8](repeating: 0, count: 16 * 2048)
        image += Self.descriptor(label: "SNAKETEST")
        image += Self.descriptor(label: "", type: 255)
        try Data(image).write(to: URL(fileURLWithPath: path))
        #expect(try ISOImage.readVolumeLabel(path: path) == "SNAKETEST")

        let empty = scratch.path("empty.iso")
        FileManager.default.createFile(atPath: empty, contents: nil)
        #expect(try ISOImage.readVolumeLabel(path: empty) == nil)
    }

    @Test func findsItemsIgnoringCase() throws {
        let scratch = try ScratchDirectory()
        let sources = scratch.url.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try Data([1]).write(to: sources.appendingPathComponent("BOOT.WIM"))
        let found = ISOImage.findItem(["sources", "boot.wim"], under: scratch.url)
        #expect(found?.lastPathComponent == "BOOT.WIM")
        #expect(ISOImage.findItem(["sources", "install.wim"], under: scratch.url) == nil)
    }
}

struct InspectISOErrorTests {
    @Test func emptyFileIsNotAWindowsISO() async throws {
        let scratch = try ScratchDirectory()
        let path = scratch.path("empty.iso")
        FileManager.default.createFile(atPath: path, contents: nil)
        let error = await #expect(throws: InstallerError.self) { try await inspectISO(at: path) }
        #expect(error?.message.contains("not a Windows ISO") == true)
        #expect(error?.kind == .invalidISO)
        #expect(error?.phase == .openISO)
    }

    @Test func missingFileIsReported() async throws {
        let error = await #expect(throws: InstallerError.self) { try await inspectISO(at: "/nonexistent/snakestick-test.iso") }
        #expect(error?.kind == .isoMissing)
    }

    @Test func directoryIsNotAWindowsISO() async throws {
        let scratch = try ScratchDirectory()
        let error = await #expect(throws: InstallerError.self) { try await inspectISO(at: scratch.url.path) }
        #expect(error?.kind == .invalidISO)
    }
}

/// §15 (a), (b): a fixture ISO made with `hdiutil makehybrid`, attached read-only.
extension IntegrationTests {
@Suite struct InspectISO {
    @Test func fixtureISO() async throws {
        let before = try attachedImageCount()
        let scratch = try ScratchDirectory()
        let fixture = try FixtureISO.make(in: scratch)
        let info = try await inspectISO(at: fixture.iso.path)
        #expect(info.volumeLabel == "SNAKETEST")
        #expect(info.build == 26200)
        #expect(info.architecture == "x64")
        #expect(info.supportsCA2023)
        #expect(info.windowsVersion == "Windows 11 25H2")
        let size = try FileManager.default.attributesOfItem(atPath: fixture.iso.path)[.size] as? NSNumber
        #expect(info.fileSize == size?.uint64Value)
        #expect(info.requiredBytes > info.fileSize)
        #expect(info.requiredBytes % 1_048_576 == 0)
        #expect(try attachedImageCount() == before)
        #expect(try !imageIsAttached(containing: scratch.url.lastPathComponent))
    }

    @Test func olderBuildDoesNotSupportCA2023() async throws {
        let scratch = try ScratchDirectory()
        let fixture = try FixtureISO.make(in: scratch, ca2023: false, build: 26100)
        let info = try await inspectISO(at: fixture.iso.path)
        #expect(info.build == 26100)
        #expect(info.windowsVersion == "Windows 11 24H2")
        #expect(!info.supportsCA2023)
    }

    /// The release comes from install.wim when boot.wim (Windows PE) is older, as on a real
    /// build-26300 ISO whose boot.wim says 26100.
    @Test func installImageDecidesTheRelease() async throws {
        let scratch = try ScratchDirectory()
        let fixture = try FixtureISO.make(in: scratch, ca2023: true, build: 26100, installBuild: 26300)
        let info = try await inspectISO(at: fixture.iso.path)
        #expect(info.build == 26300)
        #expect(info.windowsVersion == "Windows 11 (build 26300)")
        #expect(info.supportsCA2023)

        let older = try FixtureISO.make(in: scratch, name: "older.iso", ca2023: false, build: 26100, installBuild: 26100)
        let olderInfo = try await inspectISO(at: older.iso.path)
        #expect(olderInfo.windowsVersion == "Windows 11 24H2")
        #expect(!olderInfo.supportsCA2023)
    }

    @Test func isoWithoutBootWIMIsRejected() async throws {
        let scratch = try ScratchDirectory()
        let tree = scratch.url.appendingPathComponent("tree")
        try FileManager.default.createDirectory(at: tree.appendingPathComponent("sources"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: tree.appendingPathComponent("setup.exe"))
        let iso = scratch.path("noboot.iso")
        let result = try runProcess("/usr/bin/hdiutil", ["makehybrid", "-quiet", "-o", iso, "-udf", "-iso", "-default-volume-name", "NOBOOT", tree.path])
        #expect(result.status == 0)
        let before = try attachedImageCount()
        let error = await #expect(throws: InstallerError.self) { try await inspectISO(at: iso) }
        #expect(error?.message.contains("sources/boot.wim is missing") == true)
        #expect(try attachedImageCount() == before)
    }

    /// U13: the tree survives `makehybrid -udf -iso` and a read-only attach unchanged.
    @Test func makehybridPreservesTheTree() throws {
        let scratch = try ScratchDirectory()
        let fixture = try FixtureISO.make(in: scratch)
        let mountPoint = scratch.url.appendingPathComponent("mnt")
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        let tools = DiskTools(log: { _ in })
        let attachment = try tools.attachISO(fixture.iso.path, at: mountPoint.path)
        defer { tools.detach(attachment.device) }
        let expected = try treeListing(fixture.tree)
        let actual = try treeListing(mountPoint)
        #expect(actual == expected)
    }
}
}

/// Relative path → (is directory, size, contents hash) for every item under `root`.
func treeListing(_ root: URL) throws -> [String: String] {
    var result: [String: String] = [:]
    let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else {
        return result
    }
    for case let url as URL in enumerator {
        let relative = String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count))
            .precomposedStringWithCanonicalMapping
        let values = try url.resourceValues(forKeys: Set(keys))
        if values.isDirectory == true {
            result[relative] = "dir"
        } else {
            result[relative] = "file \(values.fileSize ?? -1) \(try UEFINTFSPayload.sha256(of: url))"
        }
    }
    return result
}
