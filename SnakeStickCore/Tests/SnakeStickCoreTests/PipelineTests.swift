// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import NTFS3G
import SlopDisk
import Testing
@testable import SnakeStickCore

/// Pipeline pieces that need no device.
struct PipelineUnitTests {
    @Test func remainingTimeNeedsTwoSecondsOfSamples() {
        #expect(ProgressReporter.remainingTime(samples: [(0, 0), (1, 100)], done: 100, total: 1000) == nil)
        #expect(ProgressReporter.remainingTime(samples: [(0, 0), (2, 200)], done: 200, total: 1000) == 8)
        #expect(ProgressReporter.remainingTime(samples: [(0, 0), (5, 0)], done: 0, total: 1000) == nil)
    }

    @Test func onlyTheCopyReportsRemainingTime() {
        var time: TimeInterval = 0
        let events = LockedBox<[InstallerEvent]>([])
        let reporter = ProgressReporter(verify: true, clock: { time }) { events.value.append($0) }
        reporter.start(.copyFiles)
        for step in 0 ... 30 {
            time = Double(step) * 0.5
            reporter.copied(Int64(step) * 10, of: 300, path: "/a")
            Thread.sleep(forTimeInterval: 0.11)
        }
        reporter.start(.verify)
        reporter.verified(10, of: 100, path: "/a")
        let progress = events.value.compactMap { event -> InstallerProgress? in
            if case .progress(let progress) = event { progress } else { nil }
        }
        #expect(progress.contains { $0.phase == .copyFiles && $0.estimatedRemaining != nil })
        #expect(progress.allSatisfy { $0.phase == .copyFiles || $0.estimatedRemaining == nil })
        #expect(zip(progress, progress.dropFirst()).allSatisfy { $0.fraction <= $1.fraction })
        #expect(progress.last!.fraction > 0.8)
    }

    @Test func phaseFractionsIncrease() {
        for verify in [true, false] {
            let reporter = ProgressReporter(verify: verify) { _ in }
            let bases = Phase.allCases.map { reporter.base(of: $0) }
            #expect(zip(bases, bases.dropFirst()).allSatisfy { $0 < $1 })
            #expect(bases.last! < 1)
        }
    }

    @Test(arguments: [("segoeui_EX.ttf", "segoeui.ttf"), ("wgl4_boot_EX.ttf", "wgl4_boot.ttf"), ("CHS_BOOT_ex.TTF", "CHS_BOOT.TTF"), ("segoeui.ttf", nil), ("_EX.ttf", nil)])
    func fontNames(extracted: String, target: String?) {
        #expect(CA2023Replacements.fontName(forExtracted: extracted) == target)
    }

    @Test func errnoNames() {
        #expect(errnoName(EIO) == "EIO")
        #expect(errnoName(ENOSPC) == "ENOSPC")
        #expect(errnoName(9999) == "errno 9999")
    }

    @Test func sliceNamesFollowEntrySlots() throws {
        let target = try TargetDevice(wholeBSD: "disk23")
        #expect(target.raw == "/dev/rdisk23")
        #expect(target.slice(forEntry: 0).buffered == "/dev/disk23s1")
        #expect(target.slice(forEntry: 1).raw == "/dev/rdisk23s2")
        #expect(target.slice(forEntry: 1).hasSlicePaths)
        #expect(throws: InstallerError.self) { try TargetDevice(wholeBSD: "disk23s1") }
    }
}

/// Requests rejected before anything is attached or written.
struct RequestCheckTests {
    @Test func deviceTargetsNeedRoot() async throws {
        try #require(getuid() != 0, "must not run as root")
        let events = LockedBox<[InstallerEvent]>([])
        let request = InstallerRequest(isoPath: "/nonexistent/snakestick.iso", target: .device(bsdName: "disk999"))
        let error = await #expect(throws: InstallerError.self) { try await runInstaller(request) { events.value.append($0) } }
        #expect(error?.kind == .rootRequired)
        #expect(error?.phase == .prepareTarget)
        #expect(error?.message.contains("root required") == true)
        #expect(events.value.contains { if case .failed(let failure) = $0 { failure.kind == .rootRequired } else { false } })
    }

    @Test func existingImageIsNotOverwritten() async throws {
        let scratch = try ScratchDirectory()
        let path = scratch.path("exists.img")
        try Data([1, 2, 3]).write(to: URL(fileURLWithPath: path))
        let request = InstallerRequest(isoPath: "/nonexistent/snakestick.iso", target: .image(path: path, size: 1 << 30))
        let error = await #expect(throws: InstallerError.self) { try await runInstaller(request) { _ in } }
        #expect(error?.kind == .targetExists)
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == Data([1, 2, 3]))
    }

    @Test func invalidLabelIsRejectedFirst() async throws {
        let scratch = try ScratchDirectory()
        let request = InstallerRequest(
            isoPath: "/nonexistent/snakestick.iso",
            target: .image(path: scratch.path("x.img"), size: 1 << 30),
            options: .init(volumeLabel: "BAD:LABEL")
        )
        let error = await #expect(throws: InstallerError.self) { try await runInstaller(request) { _ in } }
        #expect(error?.kind == .usage)
        #expect(!FileManager.default.fileExists(atPath: scratch.path("x.img")))
    }
}

/// §15 (c)–(e): the whole pipeline on attached images. Device paths come only from the
/// `hdiutil attach` output of the image the test made (C20).
extension IntegrationTests {
@Suite struct Pipeline {
    static let extraBytes: UInt64 = 64 << 20

    /// (c) `build`: the image holds a healthy GPT, the ISO tree on NTFS and the four loaders on FAT.
    @Test func buildsAnImage() async throws {
        let before = try attachedImageCount()
        let scratch = try ScratchDirectory()
        let fixture = try FixtureISO.make(in: scratch, ca2023: false)
        let info = try await inspectISO(at: fixture.iso.path)
        let image = scratch.path("out.img")
        let events = LockedBox<[InstallerEvent]>([])
        let result = try await runInstaller(
            InstallerRequest(isoPath: fixture.iso.path, target: .image(path: image, size: info.requiredBytes + Self.extraBytes))
        ) { events.value.append($0) }
        #expect(result.verified)
        for case .log(let line) in events.value {
            print("pipeline log: \(line)")
        }

        let phases = events.value.compactMap { event -> Phase? in
            if case .progress(let progress) = event { progress.phase } else { nil }
        }
        #expect(Array(Set(phases)).sorted() == Phase.allCases)
        #expect(phases == phases.sorted())
        #expect(events.value.contains { if case .finished = $0 { true } else { false } })
        #expect(!events.value.contains { if case .failed = $0 { true } else { false } })
        #expect(events.value.contains { if case .log(let line) = $0 { line.contains("hdiutil attach") } else { false } })

        try ImageChecks.check(image: image, fixture: fixture, label: FixtureISO.label, scratch: scratch)
        reportSparseness(image)
        #expect(try attachedImageCount() == before)
        let work = try #require(workDirectory(in: events.value))
        #expect(!FileManager.default.fileExists(atPath: work))
    }

    /// (d) Cancelling during the copy throws CancellationError and leaves nothing attached or mounted.
    @Test func cancelDuringCopy() async throws {
        let before = try attachedImageCount()
        let scratch = try ScratchDirectory()
        let fixture = try FixtureISO.make(in: scratch, ca2023: false)
        let info = try await inspectISO(at: fixture.iso.path)
        let events = LockedBox<[InstallerEvent]>([])
        let taskBox = LockedBox<Task<InstallerResult, Error>?>(nil)
        let request = InstallerRequest(isoPath: fixture.iso.path, target: .image(path: scratch.path("cancel.img"), size: info.requiredBytes + Self.extraBytes))
        let task = Task {
            try await runInstaller(request) { event in
                events.value.append(event)
                if case .progress(let progress) = event, progress.phase == .copyFiles, progress.detail?.hasPrefix("/") == true {
                    taskBox.value?.cancel()
                }
            }
        }
        taskBox.value = task
        await #expect(throws: CancellationError.self) { try await task.value }
        let failure = events.value.compactMap { event -> InstallerError? in
            if case .failed(let error) = event { error } else { nil }
        }.first
        #expect(failure?.kind == .cancelled)
        #expect(failure?.phase == .copyFiles)
        #expect(failure?.targetModified == true)
        #expect(try attachedImageCount() == before)
        #expect(try !imageIsAttached(containing: scratch.url.lastPathComponent))
        let work = try #require(workDirectory(in: events.value))
        #expect(!WorkDirectory.mountPoints().contains { $0.hasPrefix(work) })
        #expect(!FileManager.default.fileExists(atPath: work))
    }

    /// (e) The CA 2023 option puts the 2023-signed loaders from boot.wim over the copied ones.
    @Test func replacesBootLoadersWithCA2023Ones() async throws {
        let before = try attachedImageCount()
        let scratch = try ScratchDirectory()
        let fixture = try FixtureISO.make(in: scratch, ca2023: true)
        let info = try await inspectISO(at: fixture.iso.path)
        let image = scratch.path("ca2023.img")
        let events = LockedBox<[InstallerEvent]>([])
        _ = try await runInstaller(InstallerRequest(
            isoPath: fixture.iso.path,
            target: .image(path: image, size: info.requiredBytes + Self.extraBytes),
            options: .init(volumeLabel: "CA2023TEST", useCA2023Bootloaders: true)
        )) { events.value.append($0) }
        try ImageChecks.check(image: image, fixture: fixture, label: "CA2023TEST", scratch: scratch, overrides: fixture.ca2023Files)
        #expect(events.value.contains { if case .log(let line) = $0 { line.contains("CA 2023: replaced /efi/boot/bootx64.efi") } else { false } })
        #expect(events.value.contains { if case .log(let line) = $0 { line.contains("CA 2023: added /efi/microsoft/boot/fonts/newfont.ttf") } else { false } })
        #expect(try attachedImageCount() == before)
    }

    @Test func ca2023NeedsLoadersInBootWIM() async throws {
        let scratch = try ScratchDirectory()
        let fixture = try FixtureISO.make(in: scratch, ca2023: false)
        let image = scratch.path("noca.img")
        let error = await #expect(throws: InstallerError.self) {
            try await runInstaller(InstallerRequest(
                isoPath: fixture.iso.path, target: .image(path: image, size: 1 << 30), options: .init(useCA2023Bootloaders: true)
            )) { _ in }
        }
        #expect(error?.message.contains("2023-signed boot loaders") == true)
        #expect(error?.phase == .openISO)
        #expect(error?.targetModified == false)
        #expect(!FileManager.default.fileExists(atPath: image))
    }

    @Test func ca2023NeedsBuild26200() async throws {
        let scratch = try ScratchDirectory()
        let fixture = try FixtureISO.make(in: scratch, ca2023: true, build: 26100)
        let error = await #expect(throws: InstallerError.self) {
            try await runInstaller(InstallerRequest(
                isoPath: fixture.iso.path, target: .image(path: scratch.path("old.img"), size: 1 << 30), options: .init(useCA2023Bootloaders: true)
            )) { _ in }
        }
        #expect(error?.kind == .invalidISO)
        #expect(error?.message.contains("26200") == true)
    }

    @Test func tooSmallImageIsRejectedBeforeWriting() async throws {
        let before = try attachedImageCount()
        let scratch = try ScratchDirectory()
        let fixture = try FixtureISO.make(in: scratch, ca2023: false)
        let info = try await inspectISO(at: fixture.iso.path)
        let image = scratch.path("small.img")
        let error = await #expect(throws: InstallerError.self) {
            try await runInstaller(InstallerRequest(isoPath: fixture.iso.path, target: .image(path: image, size: info.requiredBytes - 1_048_576))) { _ in }
        }
        #expect(error?.kind == .insufficientSpace)
        #expect(!FileManager.default.fileExists(atPath: image))
        #expect(try attachedImageCount() == before)
    }

    /// `code#partition`'s ensures, on a 64 MiB image.
    @Test func partitionLayoutOn64MiB() throws {
        let scratch = try ScratchDirectory()
        let image = scratch.path("layout.img")
        FileManager.default.createFile(atPath: image, contents: nil)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: image))
        try handle.truncate(atOffset: 64 << 20)
        try handle.close()
        let attached = try AttachedImage(path: image, readOnly: false)
        defer { attached.detach() }
        let table = try Partitioning.writePartitionTable(devicePath: attached.raw, label: "LAYOUT")
        #expect(table.sectorSize == 512)
        #expect(table.ntfs.index == 0)
        #expect(table.ntfs.begin == 2048)
        #expect(table.fat.index == 1)
        #expect(table.fat.end == 131_038)
        // Flush with the end rather than 1 MiB aligned (the user's choice over code#partition's ensure).
        #expect(table.fat.begin == 131_038 + 1 - 2048)
        #expect(table.fat.size.bytes == 1_048_576)
        #expect(table.ntfs.end + 1 == table.fat.begin)
        #expect(table.ntfs.label == "LAYOUT")
        #expect(table.fat.label == "UEFI:NTFS")
        #expect(table.fat.type == .efiSystem)
        #expect(table.ntfs.type == .microsoftBasicData)
        // fat.end == LastUsableLBA: nothing is free after it (N - 34 for 512-byte sectors).
        #expect(table.fat.end == UInt64(64 << 20) / 512 - 34)

        let rows = try runProcess("/usr/sbin/gpt", ["-r", "show", image]).stdout
            .split(separator: "\n").filter { $0.contains("GPT part") }
            .map { $0.split(separator: " ", omittingEmptySubsequences: true).prefix(2).map { UInt64($0)! } }
        #expect(rows == [[table.ntfs.begin, table.ntfs.end - table.ntfs.begin + 1], [table.fat.begin, table.fat.end - table.fat.begin + 1]])
    }

    @Test func tooSmallDeviceIsRejectedBeforeTheTransaction() throws {
        let scratch = try ScratchDirectory()
        let image = scratch.path("tiny.img")
        FileManager.default.createFile(atPath: image, contents: nil)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: image))
        try handle.truncate(atOffset: 2 << 20)
        try handle.close()
        let attached = try AttachedImage(path: image, readOnly: false)
        defer { attached.detach() }
        let error = #expect(throws: InstallerError.self) { try Partitioning.writePartitionTable(devicePath: attached.raw, label: "TINY") }
        #expect(error?.kind == .insufficientSpace)
        #expect(try Data(contentsOf: URL(fileURLWithPath: image)).allSatisfy { $0 == 0 })
    }
}
}

/// An image attached by the test itself with `-nomount` (C20).
struct AttachedImage {
    let device: String
    let slices: [String]

    var raw: String { device.replacingOccurrences(of: "/dev/disk", with: "/dev/rdisk") }

    init(path: String, readOnly: Bool) throws {
        var arguments = ["attach", "-nomount", "-imagekey", "diskimage-class=CRawDiskImage", "-plist"]
        if readOnly {
            arguments.append("-readonly")
        }
        let result = try runProcess("/usr/bin/hdiutil", arguments + [path])
        guard result.status == 0 else {
            throw FixtureError("hdiutil attach failed: \(result.stderr)")
        }
        let plist = try PropertyListSerialization.propertyList(from: Data(result.stdout.utf8), format: nil) as? [String: Any]
        let entries = (plist?["system-entities"] as? [[String: Any]] ?? []).compactMap { $0["dev-entry"] as? String }
        guard let whole = entries.first(where: { $0.wholeMatch(of: #/\/dev\/disk[0-9]+/#) != nil }) else {
            throw FixtureError("no whole disk in \(entries)")
        }
        device = whole
        slices = entries.filter { $0.wholeMatch(of: #/\/dev\/disk[0-9]+s[0-9]+/#) != nil && $0.hasPrefix(whole + "s") }.sorted()
    }

    func detach() {
        _ = try? runProcess("/usr/bin/hdiutil", ["detach", device])
    }
}

enum ImageChecks {
    /// Attaches `image` read-only and checks the GPT, the NTFS tree against `fixture.tree` (with
    /// `overrides` by NTFS path) and the FAT files.
    static func check(image: String, fixture: FixtureISO, label: String, scratch: ScratchDirectory, overrides: [String: [UInt8]] = [:]) throws {
        let attached = try AttachedImage(path: image, readOnly: true)
        defer { attached.detach() }
        try #require(attached.slices.count == 2, "\(attached.slices)")

        do {
            let disk = try SDDisk(device: try SDRawDevice(readOnlyPath: attached.raw))
            #expect(disk.scheme == .gpt(.healthy))
            #expect(disk.partitions.map(\.label) == [label, "UEFI:NTFS"])
            #expect(disk.partitions.map(\.type) == [.microsoftBasicData, .efiSystem])
            #expect(disk.partitions[1].size.bytes == 1_048_576)
        }

        // NTFS3G reads through the buffered slice for the same reason the pipeline writes through it (U11).
        let volume = try NTFSVolume(path: attached.slices[0], mode: .readOnly)
        defer { try? volume.close() }
        #expect(volume.label == label)
        var expected = try hostTree(fixture.tree)
        for (path, bytes) in overrides {
            expected[path] = .file(bytes)
        }
        let actual = try ntfsTree(volume, "/")
        #expect(Set(actual.keys) == Set(expected.keys))
        for (path, item) in expected {
            #expect(actual[path] == item, "\(path)")
        }

        let mountPoint = scratch.url.appendingPathComponent("fat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        let mount = try runProcess("/usr/sbin/diskutil", ["mount", "readOnly", "-mountPoint", mountPoint.path, attached.slices[1]])
        try #require(mount.status == 0, "\(mount.stderr)")
        defer { _ = try? runProcess("/usr/sbin/diskutil", ["unmount", mountPoint.path]) }
        for name in UEFINTFSPayload.fileNames {
            #expect(try UEFINTFSPayload.sha256(of: mountPoint.appendingPathComponent("efi/boot/\(name)")) == UEFINTFSPayload.sha256(of: UEFINTFSPayload.url(of: name)))
        }
        let items = FileManager.default.enumerator(atPath: mountPoint.path)?.allObjects as? [String] ?? []
        #expect(!items.contains { ($0 as NSString).lastPathComponent.hasPrefix("._") || ($0 as NSString).lastPathComponent == ".DS_Store" }, "\(items)")
        print("U9: boot partition contents after the pipeline: \(items.sorted())")
        let volumeName = try runProcess("/usr/sbin/diskutil", ["info", attached.slices[1]]).stdout
        #expect(volumeName.contains("UEFI_NTFS"))
    }

    enum Item: Equatable {
        case directory
        case file([UInt8])
    }

    static func hostTree(_ root: URL) throws -> [String: Item] {
        var result: [String: Item] = [:]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])!
        for case let url as URL in enumerator {
            let relative = "/" + relativeComponents(of: url, under: root).joined(separator: "/").precomposedStringWithCanonicalMapping
            if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                result[relative] = .directory
            } else {
                result[relative] = .file([UInt8](try Data(contentsOf: url)))
            }
        }
        return result
    }

    static func ntfsTree(_ volume: NTFSVolume, _ path: String) throws -> [String: Item] {
        var result: [String: Item] = [:]
        for entry in try volume.contentsOfDirectory(path) {
            let child = (path == "/" ? "" : path) + "/" + entry.name
            switch entry.kind {
            case .directory:
                result[child] = .directory
                result.merge(try ntfsTree(volume, child)) { $1 }
            default:
                let size = Int(try volume.attributesOfItem(child).size)
                var bytes = [UInt8](repeating: 0, count: size)
                if size > 0 {
                    let count = try bytes.withUnsafeMutableBytes { try volume.readFile(child, into: $0, at: 0) }
                    #expect(count == size)
                }
                result[child] = .file(bytes)
            }
        }
        return result
    }
}

/// U10: whether the image stayed sparse.
func reportSparseness(_ path: String) {
    var info = stat()
    guard stat(path, &info) == 0 else {
        return
    }
    print("U10: \(path) is \(info.st_size) bytes long and occupies \(Int64(info.st_blocks) * 512) bytes")
}
