// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import NTFS3G
import Testing

@Suite struct DirectoryTests {
    @Test func freshVolumeRootIsEmpty() throws {
        try withScratchVolume { volume, _ throws in
            // No ".", "..", or metadata files such as $MFT.
            #expect(try volume.contentsOfDirectory("/").isEmpty)
        }
    }

    @Test func createDirectoryAppearsInListing() throws {
        try withScratchVolume { volume, _ throws in
            try volume.createDirectory("/a")
            #expect(try volume.contentsOfDirectory("/") == [.init(name: "a", kind: .directory)])
            #expect(try volume.contentsOfDirectory("/a").isEmpty)
            #expect(try volume.attributesOfItem("/a").kind == .directory)
            #expect(try volume.attributesOfItem("/a").size == 0)
        }
    }

    @Test func listingIsSortedAndTyped() throws {
        try withScratchVolume { volume, _ throws in
            try volume.createDirectory("/b")
            try volume.writeFile("/c", contents: [1])
            try volume.createDirectory("/A")
            try volume.writeFile("/a.txt", contents: [])
            try volume.createDirectory("/b/nested")
            #expect(try volume.contentsOfDirectory("/") == [
                .init(name: "A", kind: .directory),
                .init(name: "a.txt", kind: .file),
                .init(name: "b", kind: .directory),
                .init(name: "c", kind: .file),
            ])
            #expect(try volume.contentsOfDirectory("/b") == [.init(name: "nested", kind: .directory)])
        }
    }

    @Test func createDirectoryWithoutParentThrowsNotFound() throws {
        try withScratchVolume { volume, _ throws in
            #expect(throws: NTFS3GError.notFound("/a")) {
                try volume.createDirectory("/a/b")
            }
            try volume.createDirectory("/a")
            #expect(throws: NTFS3GError.notFound("/a/b")) {
                try volume.createDirectory("/a/b/c")
            }
        }
    }

    @Test func createDirectoryUnderFileThrowsNotADirectory() throws {
        try withScratchVolume { volume, _ throws in
            try volume.writeFile("/f", contents: [1])
            #expect(throws: NTFS3GError.notADirectory("/f")) {
                try volume.createDirectory("/f/d")
            }
        }
    }

    @Test func createDirectoryCaseCollision() throws {
        try withScratchVolume { volume, _ throws in
            try volume.createDirectory("/Sources")
            #expect(throws: NTFS3GError.alreadyExists("/sources")) {
                try volume.createDirectory("/sources")
            }
            #expect(throws: NTFS3GError.alreadyExists("/SOURCES")) {
                try volume.writeFile("/SOURCES", contents: [])
            }
            #expect(throws: NTFS3GError.alreadyExists("/Sources")) {
                try volume.createDirectory("/Sources")
            }
            // Lookups stay case-sensitive.
            #expect(throws: NTFS3GError.notFound("/sources")) {
                try volume.contentsOfDirectory("/sources")
            }
            #expect(try volume.contentsOfDirectory("/") == [.init(name: "Sources", kind: .directory)])
        }
    }

    @Test func caseCollisionIgnoresCaseOfNonASCIILetters() throws {
        try withScratchVolume { volume, _ throws in
            try volume.createDirectory("/Ärger")
            #expect(throws: NTFS3GError.alreadyExists("/ärger")) {
                try volume.createDirectory("/ärger")
            }
        }
    }

    @Test func caseCollisionInLargeDirectory() throws {
        // Enough entries that the index no longer fits in the MFT record and becomes a B+tree.
        try withScratchVolume { volume, _ throws in
            try volume.createDirectory("/d")
            for index in 0..<600 {
                try volume.writeFile("/d/Name-\(index)", contents: [])
            }
            for index in [0, 17, 299, 599] {
                #expect(throws: NTFS3GError.alreadyExists("/d/NAME-\(index)")) {
                    try volume.writeFile("/d/NAME-\(index)", contents: [])
                }
            }
            try volume.writeFile("/d/Name-600", contents: [])
            #expect(try volume.contentsOfDirectory("/d").count == 601)
        }
    }

    @Test(arguments: ["CON", "con", "NUL.txt", "COM1", "LPT9.log", "a.", "a ", "a:b", "a*b", "a?b", "a<b", "a>b", "a|b", "a\"b", "a\\b", "tab\tname"])
    func createDirectoryRejectsWindowsNames(name: String) throws {
        try withScratchVolume { volume, _ throws in
            #expect(throws: NTFS3GError.invalidName(name)) {
                try volume.createDirectory("/" + name)
            }
            #expect(throws: NTFS3GError.invalidName(name)) {
                try volume.writeFile("/" + name, contents: [])
            }
            #expect(try volume.contentsOfDirectory("/").isEmpty)
        }
    }

    @Test func createDirectoryRejectsOverlongName() throws {
        try withScratchVolume { volume, _ throws in
            try volume.createDirectory("/" + String(repeating: "x", count: 255))
            let tooLong = String(repeating: "x", count: 256)
            #expect(throws: NTFS3GError.invalidName(tooLong)) {
                try volume.createDirectory("/" + tooLong)
            }
            // 128 characters outside the BMP take 256 UTF-16 code units.
            let astral = String(repeating: "😀", count: 128)
            #expect(throws: NTFS3GError.invalidName(astral)) {
                try volume.createDirectory("/" + astral)
            }
        }
    }

    @Test(arguments: ["a", "", "/a//b", "//", "/a/", "/./a", "/a/..", "/a/.", "a/b"])
    func createDirectoryRejectsInvalidPaths(path: String) throws {
        try withScratchVolume { volume, _ throws in
            try volume.createDirectory("/a")
            #expect(throws: NTFS3GError.invalidPath(path)) {
                try volume.createDirectory(path)
            }
        }
    }

    @Test func createRootThrowsAlreadyExists() throws {
        try withScratchVolume { volume, _ throws in
            #expect(throws: NTFS3GError.alreadyExists("/")) {
                try volume.createDirectory("/")
            }
        }
    }

    @Test func createDirectoryOnReadOnlyVolume() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let image = try scratch.makeVolume()
        let volume = try NTFSVolume(path: image, mode: .readOnly)
        defer { try? volume.close() }
        #expect(throws: NTFS3GError.readOnlyVolume) {
            try volume.createDirectory("/a")
        }
        #expect(throws: NTFS3GError.readOnlyVolume) {
            try volume.writeFile("/a", contents: [])
        }
        #expect(throws: NTFS3GError.readOnlyVolume) {
            _ = try volume.copyTree(from: scratch.url)
        }
    }

    @Test func createDirectoryWithTimes() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let image = try scratch.makeVolume()
        do {
            let volume = try NTFSVolume(path: image, mode: .readWrite)
            try volume.createDirectory("/d", times: fixedTimes)
            try volume.close()
        }
        let volume = try NTFSVolume(path: image, mode: .readOnly)
        defer { try? volume.close() }
        #expect(ticks(try volume.attributesOfItem("/d").times) == ticks(fixedTimes))
    }

    @Test func contentsOfFileThrows() throws {
        try withScratchVolume { volume, _ throws in
            try volume.writeFile("/f", contents: [1, 2, 3])
            #expect(throws: NTFS3GError.notADirectory("/f")) {
                try volume.contentsOfDirectory("/f")
            }
            #expect(throws: NTFS3GError.notFound("/missing")) {
                try volume.contentsOfDirectory("/missing")
            }
        }
    }

    @Test func closeTwice() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let volume = try NTFSVolume(path: try scratch.makeVolume(), mode: .readWrite)
        try volume.close()
        try volume.close()
    }

    @Test func useAfterClose() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let volume = try NTFSVolume(path: try scratch.makeVolume(), mode: .readWrite)
        try volume.close()
        #expect(throws: NTFS3GError.volumeClosed) {
            try volume.contentsOfDirectory("/")
        }
        #expect(throws: NTFS3GError.volumeClosed) {
            try volume.createDirectory("/a")
        }
        #expect(throws: NTFS3GError.volumeClosed) {
            try volume.attributesOfItem("/")
        }
    }

    @Test func unclosedVolumeIsUnmountedOnDeinit() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let image = try scratch.makeVolume()
        do {
            let volume = try NTFSVolume(path: image, mode: .readWrite)
            try volume.createDirectory("/kept")
        }
        // The image is closed and consistent again, so it can be mounted and shows the change.
        let volume = try NTFSVolume(path: image, mode: .readWrite)
        defer { try? volume.close() }
        #expect(try volume.contentsOfDirectory("/") == [.init(name: "kept", kind: .directory)])
    }
}
