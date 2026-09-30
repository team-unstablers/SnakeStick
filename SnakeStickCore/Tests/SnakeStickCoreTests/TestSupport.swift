// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import WIMLib
@testable import SnakeStickCore

enum TestEnvironment {
    /// Opt-in for the suites that attach images with `hdiutil` (§15).
    static let integration = ProcessInfo.processInfo.environment["SNAKESTICK_TEST_INTEGRATION"] == "1"
}

/// Parent of every suite that attaches images. Serialized as a whole, so that the attached-image
/// count each test compares before and after is not changed by another suite running alongside.
@Suite(.serialized, .enabled(if: TestEnvironment.integration))
struct IntegrationTests {}

/// The work directory the pipeline logged, which cleanup must have removed.
func workDirectory(in events: [InstallerEvent]) -> String? {
    for case .log(let line) in events where line.hasPrefix("work directory: ") {
        return String(line.dropFirst("work directory: ".count))
    }
    return nil
}

/// A directory under `$TMPDIR` removed at the end of the test.
final class ScratchDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnakeStickCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func path(_ name: String) -> String {
        url.appendingPathComponent(name).path
    }
}

struct ProcessResult {
    var status: Int32
    var stdout: String
    var stderr: String
}

@discardableResult
func runProcess(_ executable: String, _ arguments: [String], environment: [String: String]? = nil) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let environment {
        process.environment = environment
    }
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    process.standardInput = FileHandle.nullDevice
    try process.run()
    let errorData = LockedBox<Data>(Data())
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
        errorData.value = err.fileHandleForReading.readDataToEndOfFile()
        group.leave()
    }
    let outputData = out.fileHandleForReading.readDataToEndOfFile()
    group.wait()
    process.waitUntilExit()
    return ProcessResult(
        status: process.terminationStatus,
        stdout: String(decoding: outputData, as: UTF8.self),
        stderr: String(decoding: errorData.value, as: UTF8.self)
    )
}

final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T

    init(_ value: T) {
        stored = value
    }

    var value: T {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// The number of images `hdiutil info` lists (acceptance: the same before and after a run).
func attachedImageCount() throws -> Int {
    try runProcess("/usr/bin/hdiutil", ["info"]).stdout
        .split(separator: "\n").filter { $0.hasPrefix("image-path") }.count
}

/// Whether an image whose path contains `fragment` is still attached.
func imageIsAttached(containing fragment: String) throws -> Bool {
    try runProcess("/usr/bin/hdiutil", ["info"]).stdout
        .split(separator: "\n").contains { $0.hasPrefix("image-path") && $0.contains(fragment) }
}

/// A small Windows-like installation tree and the ISO made from it (§15 (a)).
struct FixtureISO {
    let tree: URL
    let iso: URL
    /// The 2023-signed replacements inside `boot.wim` image 2, by destination path on the NTFS
    /// volume (only when made with `ca2023: true`).
    let ca2023Files: [String: [UInt8]]

    static let label = "SNAKETEST"

    /// Builds `tree/` with `sources/boot.wim` (two images; image 2 carries `WINDOWS/ARCH` 9 and
    /// build 26200) and turns it into `name` with `hdiutil makehybrid -udf -iso`.
    static func make(in scratch: ScratchDirectory, name: String = "test.iso", ca2023: Bool = true, build: Int = 26200) throws -> FixtureISO {
        // No ".iso" in the directory name: makehybrid takes such a source for an image.
        let stem = (name as NSString).deletingPathExtension
        let tree = scratch.url.appendingPathComponent("tree-\(stem)", isDirectory: true)
        let fm = FileManager.default
        func write(_ path: String, _ bytes: [UInt8]) throws {
            let url = tree.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(bytes).write(to: url)
        }
        try write("setup.exe", pseudoRandomBytes(count: 70_001, seed: 1))
        try write("bootmgr", pseudoRandomBytes(count: 4096, seed: 2))
        try write("bootmgr.efi", pseudoRandomBytes(count: 9000, seed: 3))
        try write("efi/boot/bootx64.efi", pseudoRandomBytes(count: 12_345, seed: 4))
        try write("efi/microsoft/boot/bcd", pseudoRandomBytes(count: 16384, seed: 5))
        try write("efi/microsoft/boot/fonts/segoeui.ttf", pseudoRandomBytes(count: 5000, seed: 6))
        try write("efi/microsoft/boot/fonts/wgl4_boot.ttf", pseudoRandomBytes(count: 6000, seed: 7))
        try write("sources/install.wim", pseudoRandomBytes(count: 3 * 1024 * 1024 + 11, seed: 8))
        try write("sources/empty.txt", [])
        try write("support/logging/readme.txt", Array("logging\n".utf8))
        try write("sources/ko-kr/설치.txt", Array("한국어\n".utf8))
        try fm.createDirectory(at: tree.appendingPathComponent("support/empty-dir"), withIntermediateDirectories: true)

        // boot.wim: image 1 is WinPE, image 2 is Setup with the version properties.
        let winpe = scratch.url.appendingPathComponent("wim-\(name)-1", isDirectory: true)
        let setup = scratch.url.appendingPathComponent("wim-\(name)-2", isDirectory: true)
        try fm.createDirectory(at: winpe.appendingPathComponent("Windows/System32"), withIntermediateDirectories: true)
        try Data("winpe".utf8).write(to: winpe.appendingPathComponent("Windows/System32/winpe.txt"))
        try fm.createDirectory(at: setup.appendingPathComponent("Windows/System32"), withIntermediateDirectories: true)
        try Data("setup".utf8).write(to: setup.appendingPathComponent("Windows/System32/setup.txt"))
        var replacements: [String: [UInt8]] = [:]
        if ca2023 {
            let efiEX = setup.appendingPathComponent("Windows/Boot/EFI_EX", isDirectory: true)
            let fontsEX = setup.appendingPathComponent("Windows/Boot/Fonts_EX", isDirectory: true)
            try fm.createDirectory(at: efiEX, withIntermediateDirectories: true)
            try fm.createDirectory(at: fontsEX, withIntermediateDirectories: true)
            let bootmgfw = pseudoRandomBytes(count: 20_000, seed: 20)
            let bootmgr = pseudoRandomBytes(count: 21_000, seed: 21)
            let segoe = pseudoRandomBytes(count: 5500, seed: 22)
            let newFont = pseudoRandomBytes(count: 700, seed: 23)
            try Data(bootmgfw).write(to: efiEX.appendingPathComponent("bootmgfw_EX.efi"))
            try Data(bootmgr).write(to: efiEX.appendingPathComponent("bootmgr_EX.efi"))
            try Data(segoe).write(to: fontsEX.appendingPathComponent("segoeui_EX.ttf"))
            try Data(newFont).write(to: fontsEX.appendingPathComponent("newfont_EX.ttf"))
            replacements = [
                "/efi/boot/bootx64.efi": bootmgfw,
                "/bootmgr.efi": bootmgr,
                "/efi/microsoft/boot/fonts/segoeui.ttf": segoe,
                "/efi/microsoft/boot/fonts/newfont.ttf": newFont,
            ]
        }
        let wim = tree.appendingPathComponent("sources/boot.wim")
        try WIMFile.create(images: [
            WIMImageSource(directory: winpe, name: "Microsoft Windows PE (amd64)", properties: [
                "WINDOWS/ARCH": "9", "WINDOWS/VERSION/MAJOR": "10", "WINDOWS/VERSION/BUILD": "\(build)",
            ]),
            WIMImageSource(directory: setup, name: "Microsoft Windows Setup (amd64)", properties: [
                "WINDOWS/ARCH": "9", "WINDOWS/VERSION/MAJOR": "10", "WINDOWS/VERSION/MINOR": "0",
                "WINDOWS/VERSION/BUILD": "\(build)",
            ]),
        ], to: wim.path)

        let iso = scratch.url.appendingPathComponent(name)
        let result = try runProcess("/usr/bin/hdiutil", [
            "makehybrid", "-quiet", "-o", iso.path, "-udf", "-iso", "-default-volume-name", label, tree.path,
        ])
        guard result.status == 0 else {
            throw FixtureError("hdiutil makehybrid failed: \(result.stderr)")
        }
        return FixtureISO(tree: tree, iso: iso, ca2023Files: replacements)
    }
}

struct FixtureError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

/// Deterministic bytes (SplitMix64), so that fixtures are reproducible.
func pseudoRandomBytes(count: Int, seed: UInt64) -> [UInt8] {
    var state = seed
    var bytes = [UInt8]()
    bytes.reserveCapacity(count)
    while bytes.count < count {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        withUnsafeBytes(of: z.littleEndian) { bytes.append(contentsOf: $0.prefix(count - bytes.count)) }
    }
    return bytes
}
