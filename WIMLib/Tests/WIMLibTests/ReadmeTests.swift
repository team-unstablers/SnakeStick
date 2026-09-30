// SPDX-License-Identifier: LGPL-2.1-or-later

import Foundation
import Testing
import WIMLib

/// The README's SYNOPSIS, with a WIM made by its last step standing in for the ISO's boot.wim,
/// and scratch paths instead of /Volumes and /tmp. Keep the two in step.
@Test func readmeSynopsis() throws {
    let scratch = try ScratchDirectory()
    defer { scratch.remove() }
    let pe = try scratch.makeDirectory("fixture/pe")
    try Data("pe".utf8).write(to: pe.appendingPathComponent("pe.txt"))
    let setup = scratch.url("fixture/setup")
    let efiEx = setup.appendingPathComponent("Windows/Boot/EFI_EX")
    let fontsEx = setup.appendingPathComponent("Windows/Boot/Fonts_EX")
    try FileManager.default.createDirectory(at: efiEx, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: fontsEx, withIntermediateDirectories: true)
    let bootmgfw = randomBytes(count: 3000, seed: 5)
    try Data(bootmgfw).write(to: efiEx.appendingPathComponent("bootmgfw_EX.efi"))
    try Data(randomBytes(count: 2000, seed: 6)).write(to: efiEx.appendingPathComponent("bootmgr_EX.efi"))
    try Data(randomBytes(count: 1000, seed: 7)).write(to: fontsEx.appendingPathComponent("font_EX.ttf"))
    let bootWIM = scratch.path("fixture/boot.wim")

    // For tests: a two-image stand-in for boot.wim, captured from two host directories.
    try WIMFile.create(images: [
        WIMImageSource(directory: pe, name: "Microsoft Windows PE (x64)"),
        WIMImageSource(directory: setup, name: "Microsoft Windows Setup (x64)",
                       properties: ["WINDOWS/ARCH": "9", "WINDOWS/VERSION/BUILD": "26200"]),
    ], to: bootWIM)

    let wim = try WIMFile(path: bootWIM)
    defer { wim.close() }

    var lines: [String] = []
    for image in try wim.images {
        lines.append("\(image.index) \(image.name ?? "") \(image.architecture.map { "\($0)" } ?? "") \(image.build ?? 0)")
    }
    let setupImage = try wim.images[1]
    let isX64 = setupImage.architecture == .x64
    let build = setupImage.build ?? 0
    let edition = try wim.property("WINDOWS/EDITIONID", ofImage: 2)
    #expect(lines == ["1 Microsoft Windows PE (x64)  0", "2 Microsoft Windows Setup (x64) x64 26200"])
    #expect(isX64)
    #expect(build == 26200)
    #expect(edition == nil)

    let target = scratch.url("ca2023")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try wim.extract(paths: ["/Windows/Boot/EFI_EX", "/Windows/Boot/Fonts_EX"], fromImage: 2, to: target)
    #expect(try listing(of: target) == ["EFI_EX", "Fonts_EX"])
    #expect(try listing(of: target.appendingPathComponent("EFI_EX")) == ["bootmgfw_EX.efi", "bootmgr_EX.efi"])
    #expect(try listing(of: target.appendingPathComponent("Fonts_EX")) == ["font_EX.ttf"])
    #expect(try contents(of: target.appendingPathComponent("EFI_EX/bootmgfw_EX.efi")) == bootmgfw)
}
