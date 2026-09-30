// SPDX-License-Identifier: LGPL-2.1-or-later

import CWIMLib
import Foundation
import Testing
import WIMLib

@Suite struct ImageTests {
    @Test func createdWIMHasOneNamedImage() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let path = try Fixture.makeWIM(in: scratch)

        let file = try WIMFile(path: path)
        defer { file.close() }
        let images = try file.images
        #expect(images.count == 1)
        #expect(images[0].index == 1)
        #expect(images[0].name == Fixture.imageName)
        #expect(file.path == path)
    }

    @Test func propertiesMapToFields() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let path = try Fixture.makeWIM(in: scratch, properties: [
            "WINDOWS/ARCH": "9",
            "WINDOWS/VERSION/BUILD": "26200",
            "WINDOWS/VERSION/MAJOR": "10",
            "WINDOWS/VERSION/MINOR": "0",
            "DESCRIPTION": "Microsoft Windows Setup (x64)",
            "DISPLAYNAME": "Windows Setup",
            "WINDOWS/EDITIONID": "WindowsPE",
        ])

        let file = try WIMFile(path: path)
        defer { file.close() }
        let image = try #require(try file.images.first)
        #expect(image.architecture == .x64)
        #expect(image.build == 26200)
        #expect(image.major == 10)
        #expect(image.minor == 0)
        #expect(image.description == "Microsoft Windows Setup (x64)")
        #expect(image.displayName == "Windows Setup")
        #expect(try file.property("WINDOWS/EDITIONID", ofImage: 1) == "WindowsPE")
        #expect(try file.property("WINDOWS/ARCH", ofImage: 1) == "9")
    }

    @Test func missingPropertiesAreNil() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let path = try Fixture.makeWIM(in: scratch)

        let file = try WIMFile(path: path)
        defer { file.close() }
        let image = try #require(try file.images.first)
        #expect(image.description == nil)
        #expect(image.displayName == nil)
        #expect(image.architecture == nil)
        #expect(image.major == nil)
        #expect(image.minor == nil)
        #expect(image.build == nil)
        #expect(try file.property("WINDOWS/EDITIONID", ofImage: 1) == nil)
    }

    /// Property names are case-sensitive, unlike paths.
    @Test func propertyNamesAreCaseSensitive() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let path = try Fixture.makeWIM(in: scratch, properties: ["WINDOWS/ARCH": "12"])

        let file = try WIMFile(path: path)
        defer { file.close() }
        #expect(try file.property("WINDOWS/ARCH", ofImage: 1) == "12")
        #expect(try file.property("windows/arch", ofImage: 1) == nil)
    }

    @Test func nonIntegerNumbersAreNil() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let path = try Fixture.makeWIM(in: scratch, properties: [
            "WINDOWS/ARCH": "x64",
            "WINDOWS/VERSION/BUILD": "26200.1",
            "WINDOWS/VERSION/MAJOR": " 10",
        ])

        let file = try WIMFile(path: path)
        defer { file.close() }
        let image = try #require(try file.images.first)
        #expect(image.architecture == nil)
        #expect(image.build == nil)
        #expect(image.major == nil)
    }

    @Test(arguments: [
        (0, WIMArchitecture.x86),
        (5, .arm),
        (9, .x64),
        (12, .arm64),
        (6, .other(6)),
    ])
    func architectureCodes(code: Int, architecture: WIMArchitecture) throws {
        #expect(WIMArchitecture(code: code) == architecture)
        #expect(architecture.code == code)

        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let path = try Fixture.makeWIM(in: scratch, properties: ["WINDOWS/ARCH": String(code)])
        let file = try WIMFile(path: path)
        defer { file.close() }
        #expect(try file.images.first?.architecture == architecture)
    }

    @Test func propertyOfMissingImageThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let path = try Fixture.makeWIM(in: scratch)

        let file = try WIMFile(path: path)
        defer { file.close() }
        for index in [0, 2, -1] {
            let error = #expect(throws: WIMLibError.self) {
                try file.property("NAME", ofImage: index)
            }
            #expect(error?.wimlibCode == code(WIMLIB_ERR_INVALID_IMAGE))
        }
    }

    /// Every compression format round-trips the fixture, including the 1 MiB + 17 B file
    /// that spans several compression chunks.
    @Test(arguments: [WIMCompression.none, .xpress, .lzx])
    func compressionFormats(compression: WIMCompression) throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let path = try Fixture.makeWIM(in: scratch, compression: compression)

        let file = try WIMFile(path: path)
        defer { file.close() }
        let target = try scratch.makeDirectory("out")
        try file.extract(paths: ["/dir"], fromImage: 1, to: target)
        for (name, bytes) in Fixture.files {
            #expect(try contents(of: target.appendingPathComponent("dir/\(name)")) == bytes, "\(name)")
        }
    }

    @Test func wimlibVersion() {
        #expect(WIMFile.wimlibVersion == "1.14.5")
    }
}
