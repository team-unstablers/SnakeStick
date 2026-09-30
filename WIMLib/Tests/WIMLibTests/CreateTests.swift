// SPDX-License-Identifier: LGPL-2.1-or-later

import CWIMLib
import Foundation
import Testing
import WIMLib

@Suite struct CreateTests {
    /// A stand-in for a Windows `boot.wim`: image 1 is Windows PE, image 2 is Windows Setup
    /// with the boot files. Each image keeps its own tree and properties.
    @Test func twoImages() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let pe = scratch.url("pe")
        try FileManager.default.createDirectory(at: pe.appendingPathComponent("Windows"), withIntermediateDirectories: true)
        try Data("pe".utf8).write(to: pe.appendingPathComponent("Windows/pe.txt"))
        let setup = scratch.url("setup")
        let efiEx = setup.appendingPathComponent("Windows/Boot/EFI_EX")
        try FileManager.default.createDirectory(at: efiEx, withIntermediateDirectories: true)
        let loader = randomBytes(count: 5000, seed: 4)
        try Data(loader).write(to: efiEx.appendingPathComponent("bootmgfw_EX.efi"))

        let path = scratch.path("boot.wim")
        try WIMFile.create(images: [
            WIMImageSource(directory: pe, name: "Microsoft Windows PE (x64)", properties: ["WINDOWS/ARCH": "9"]),
            WIMImageSource(directory: setup, name: "Microsoft Windows Setup (x64)", properties: [
                "WINDOWS/ARCH": "9",
                "WINDOWS/VERSION/BUILD": "26200",
            ]),
        ], to: path)

        let file = try WIMFile(path: path)
        defer { file.close() }
        let images = try file.images
        #expect(images.map(\.index) == [1, 2])
        #expect(images.map(\.name) == ["Microsoft Windows PE (x64)", "Microsoft Windows Setup (x64)"])
        #expect(images.map(\.build) == [nil, 26200])
        #expect(images.map(\.architecture) == [.x64, .x64])

        let target = try scratch.makeDirectory("out")
        try file.extract(paths: ["/Windows/Boot/EFI_EX"], fromImage: 2, to: target)
        #expect(try listing(of: target) == ["EFI_EX"])
        #expect(try contents(of: target.appendingPathComponent("EFI_EX/bootmgfw_EX.efi")) == loader)

        let error = #expect(throws: WIMLibError.self) {
            try file.extract(paths: ["/Windows/Boot/EFI_EX"], fromImage: 1, to: target)
        }
        #expect(error?.wimlibCode == code(WIMLIB_ERR_PATH_DOES_NOT_EXIST))
    }

    @Test func duplicateImageNamesThrow() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let source = scratch.url("source")
        try Fixture.makeTree(at: source)

        let error = #expect(throws: WIMLibError.self) {
            try WIMFile.create(images: [
                WIMImageSource(directory: source, name: "Same"),
                WIMImageSource(directory: source, name: "Same"),
            ], to: scratch.path("out.wim"))
        }
        #expect(error?.wimlibCode == code(WIMLIB_ERR_IMAGE_NAME_COLLISION))
    }

    @Test func noImages() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let path = scratch.path("empty.wim")
        try WIMFile.create(images: [], to: path)

        let file = try WIMFile(path: path)
        defer { file.close() }
        #expect(try file.images == [])
        let target = try scratch.makeDirectory("out")
        let error = #expect(throws: WIMLibError.self) {
            try file.extract(paths: ["/dir"], fromImage: 1, to: target)
        }
        #expect(error?.wimlibCode == code(WIMLIB_ERR_INVALID_IMAGE))
    }

    @Test func existingFileIsReplaced() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let path = try Fixture.makeWIM(in: scratch)
        let source = scratch.url("other")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try WIMFile.create(from: source, to: path, imageName: "Replacement")

        let file = try WIMFile(path: path)
        defer { file.close() }
        #expect(try file.images.map(\.name) == ["Replacement"])
    }
}
