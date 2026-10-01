// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import snakestick
@testable import SnakeStickCore

private final class BundleMarker {}

/// The `snakestick` binary built next to the test bundle, or `SNAKESTICK_TEST_BINARY` (the one in a
/// built app, `SnakeStick.app/Contents/Helpers/snakestick`).
let snakestickBinary = ProcessInfo.processInfo.environment["SNAKESTICK_TEST_BINARY"]
    ?? Bundle(for: BundleMarker.self).bundleURL.deletingLastPathComponent().appendingPathComponent("snakestick").path

struct ArgumentTests {
    @Test func make() throws {
        #expect(try Arguments.parse(["make", "win.iso", "disk4"]) == .make(iso: "win.iso", disk: "disk4", options: .init(), assumeYes: false))
        #expect(try Arguments.parse(["make", "--label", "WIN", "--no-verify", "--ca-2023", "--yes", "--verbose", "win.iso", "/dev/rdisk4"])
            == .make(iso: "win.iso", disk: "disk4", options: .init(label: "WIN", verify: false, ca2023: true, verbose: true), assumeYes: true))
        #expect(try Arguments.parse(["make", "--label=A B", "win.iso", "/dev/disk12"])
            == .make(iso: "win.iso", disk: "disk12", options: .init(label: "A B"), assumeYes: false))
        #expect(try Arguments.parse(["make", "--", "-odd.iso", "disk4"]) == .make(iso: "-odd.iso", disk: "disk4", options: .init(), assumeYes: false))
    }

    @Test func build() throws {
        #expect(try Arguments.parse(["build", "-o", "out.img", "win.iso"]) == .build(iso: "win.iso", output: "out.img", imageSize: nil, options: .init()))
        #expect(try Arguments.parse(["build", "--imgsize", "7.5G", "-o", "out.img", "win.iso"])
            == .build(iso: "win.iso", output: "out.img", imageSize: 7_500_000_000, options: .init()))
        #expect(try Arguments.parse(["build", "--imgsize=8G", "-o=out.img", "win.iso"])
            == .build(iso: "win.iso", output: "out.img", imageSize: 8_000_000_000, options: .init()))
    }

    @Test func others() throws {
        #expect(try Arguments.parse(["disks"]) == .disks)
        #expect(try Arguments.parse(["info", "win.iso"]) == .info(iso: "win.iso"))
        #expect(try Arguments.parse(["--help"]) == .help)
        #expect(try Arguments.parse(["-h"]) == .help)
    }

    @Test(arguments: [
        [], ["write", "a", "b"], ["make", "win.iso"], ["make", "win.iso", "disk4", "extra"], ["make", "win.iso", "disk4s1"],
        ["make", "win.iso", "/dev/disk"], ["make", "--imgsize", "8G", "win.iso", "disk4"], ["make", "-o", "x", "win.iso", "disk4"],
        ["make", "--yes=1", "win.iso", "disk4"], ["make", "--label"], ["build", "win.iso"], ["build", "-o", "out.img"],
        ["build", "--imgsize", "8GiB", "-o", "out.img", "win.iso"], ["build", "--yes", "-o", "out.img", "win.iso"],
        ["disks", "extra"], ["info"], ["info", "a", "b"], ["make", "--bogus", "win.iso", "disk4"],
    ])
    func usageErrors(arguments: [String]) async {
        #expect(throws: UsageError.self) { try Arguments.parse(arguments) }
        #expect(await SnakeStickCLI.run(arguments) == .usage)
    }

    @Test(arguments: [("disk4", "disk4"), ("/dev/disk4", "disk4"), ("/dev/rdisk4", "disk4"), ("/dev/disk10", "disk10")])
    func diskNames(text: String, name: String) throws {
        #expect(try Arguments.diskName(text) == name)
    }

    @Test(arguments: ["rdisk4", "disk4s2", "/dev/rdisk4s1", "/tmp/disk4", "sda", "disk", "/dev/rrdisk4"])
    func rejectedDiskNames(text: String) {
        #expect(throws: UsageError.self) { try Arguments.diskName(text) }
    }

    @Test func exitCodes() {
        func code(_ kind: InstallerError.Kind) -> Int32 {
            ExitCode(for: InstallerError(phase: .openISO, kind: kind, message: "")).rawValue
        }
        #expect(code(.usage) == 64)
        #expect(code(.invalidISO) == 65)
        #expect(code(.isoMissing) == 66)
        #expect(code(.targetIneligible) == 69)
        #expect(code(.insufficientSpace) == 69)
        #expect(code(.io) == 74)
        #expect(code(.rootRequired) == 77)
        #expect(code(.cancelled) == 130)
    }

    @Test func minimumImageSizes() {
        #expect(SnakeStickCLI.minimumSISize(7_200_000_001) == "7.3G")
        #expect(SnakeStickCLI.minimumSISize(8_000_000_000) == "8G")
        #expect(SISize.parse(SnakeStickCLI.minimumSISize(7_234_567_890))! >= 7_234_567_890)
    }

    /// P14: make without root stops before it opens anything.
    @Test func makeNeedsRoot() async throws {
        try #require(getuid() != 0)
        #expect(await SnakeStickCLI.run(["make", "/nonexistent/snakestick.iso", "disk0"]) == .noPermission)
        #expect(await SnakeStickCLI.run(["make", "--yes", "/nonexistent/snakestick.iso", "disk999"]) == .noPermission)
    }

    @Test func infoOnMissingAndBadFiles() async throws {
        #expect(await SnakeStickCLI.run(["info", "/nonexistent/snakestick.iso"]) == .noInput)
        let scratch = try ScratchDirectory()
        FileManager.default.createFile(atPath: scratch.path("empty.iso"), contents: nil)
        #expect(await SnakeStickCLI.run(["info", scratch.path("empty.iso")]) == .invalidISO)
    }

    @Test func buildRefusesAnExistingImage() async throws {
        let scratch = try ScratchDirectory()
        FileManager.default.createFile(atPath: scratch.path("out.img"), contents: Data([7]))
        #expect(await SnakeStickCLI.run(["build", "-o", scratch.path("out.img"), "/nonexistent/snakestick.iso"]) == .cannotCreate)
        #expect(try Data(contentsOf: URL(fileURLWithPath: scratch.path("out.img"))) == Data([7]))
    }
}

extension IntegrationTests {
    /// §15 (f): the built binary, run as a process.
    @Suite struct CommandLine {
        @Test func binaryIsBuilt() {
            #expect(FileManager.default.isExecutableFile(atPath: snakestickBinary))
        }

        @Test func buildWritesAnImage() throws {
            let before = try attachedImageCount()
            let scratch = try ScratchDirectory()
            let fixture = try FixtureISO.make(in: scratch, ca2023: false)
            let image = scratch.path("cli.img")
            let result = try runProcess(snakestickBinary, ["build", "--verbose", "-o", image, fixture.iso.path])
            #expect(result.status == 0, "\(result.stderr)")
            #expect(result.stdout.contains("The written data matches the ISO."))
            #expect(result.stderr.contains("Step 8/8"))
            try ImageChecks.check(image: image, fixture: fixture, label: FixtureISO.label, scratch: scratch)
            #expect(try attachedImageCount() == before)
        }

        @Test func buildRejectsASmallImageSize() throws {
            let scratch = try ScratchDirectory()
            let fixture = try FixtureISO.make(in: scratch, ca2023: false)
            let result = try runProcess(snakestickBinary, ["build", "--imgsize", "1M", "-o", scratch.path("small.img"), fixture.iso.path])
            #expect(result.status == 64)
            #expect(result.stderr.contains("too small"))
            #expect(!FileManager.default.fileExists(atPath: scratch.path("small.img")))
        }

        @Test func makeWithoutRoot() throws {
            try #require(getuid() != 0)
            let scratch = try ScratchDirectory()
            let fixture = try FixtureISO.make(in: scratch, ca2023: false)
            let result = try runProcess(snakestickBinary, ["make", fixture.iso.path, "disk0"])
            #expect(result.status == 77)
            #expect(result.stderr.contains("sudo"))
        }

        @Test func infoAndDisks() throws {
            let scratch = try ScratchDirectory()
            let fixture = try FixtureISO.make(in: scratch)
            let info = try runProcess(snakestickBinary, ["info", fixture.iso.path])
            #expect(info.status == 0)
            #expect(info.stdout.contains("SNAKETEST"))
            #expect(info.stdout.contains("26200"))
            #expect(info.stdout.contains("x64"))
            let disks = try runProcess(snakestickBinary, ["disks"])
            #expect(disks.status == 0)
            #expect(disks.stdout.contains("startup disk"))
        }
    }
}
