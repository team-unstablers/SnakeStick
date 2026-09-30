// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import NTFS3G
import Testing

@Suite struct RemoveTests {
    @Test func removeFileIsGoneAfterRemount() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let image = try scratch.makeVolume()
        do {
            let volume = try NTFSVolume(path: image, mode: .readWrite)
            try volume.createDirectory("/d")
            try volume.writeFile("/d/kept.txt", contents: [1])
            try volume.writeFile("/d/removed.txt", contents: pattern(count: 100_000))
            try volume.removeItem("/d/removed.txt")
            #expect(try volume.contentsOfDirectory("/d") == [.init(name: "kept.txt", kind: .file)])
            #expect(throws: NTFS3GError.notFound("/d/removed.txt")) {
                try volume.attributesOfItem("/d/removed.txt")
            }
            try volume.close()
        }
        let volume = try NTFSVolume(path: image, mode: .readOnly)
        defer { try? volume.close() }
        #expect(try volume.contentsOfDirectory("/d") == [.init(name: "kept.txt", kind: .file)])
        #expect(throws: NTFS3GError.notFound("/d/removed.txt")) {
            try volume.attributesOfItem("/d/removed.txt")
        }
    }

    /// The order SnakeStick uses to replace a file: writeFile refuses an existing path, so the
    /// old file is removed first.
    @Test func removeThenWriteFileAtSamePath() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let image = try scratch.makeVolume()
        let old = pattern(count: (9 << 20) + 1, seed: 1)
        let new = pattern(count: 300_000, seed: 2)
        let oldSource = scratch.url.appendingPathComponent("old.bin")
        let newSource = scratch.url.appendingPathComponent("new.bin")
        try Data(old).write(to: oldSource)
        try Data(new).write(to: newSource)

        do {
            let volume = try NTFSVolume(path: image, mode: .readWrite)
            try volume.createDirectory("/boot")
            try volume.writeFile("/boot/bootmgr.efi", from: oldSource)
            try volume.removeItem("/boot/bootmgr.efi")
            try volume.writeFile("/boot/bootmgr.efi", from: newSource, times: fixedTimes)
            try volume.close()
        }

        let volume = try NTFSVolume(path: image, mode: .readOnly)
        defer { try? volume.close() }
        #expect(try volume.contentsOfDirectory("/boot") == [.init(name: "bootmgr.efi", kind: .file)])
        #expect(try volume.attributesOfItem("/boot/bootmgr.efi").size == Int64(new.count))
        #expect(ticks(try volume.attributesOfItem("/boot/bootmgr.efi").times) == ticks(fixedTimes))
        #expect(try volume.readAll("/boot/bootmgr.efi") == new)
    }

    /// copyTree stores the ISO's lower-case names; SnakeStick may spell them as Windows does.
    @Test func removeIgnoresCase() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let source = scratch.url.appendingPathComponent("iso", isDirectory: true)
        for directory in ["", "/efi", "/efi/boot", "/efi/microsoft", "/efi/microsoft/boot", "/efi/microsoft/boot/fonts"] {
            try Fixtures.makeDirectory(source.path + directory)
        }
        try Fixtures.makeFile(source.path + "/efi/boot/bootx64.efi", pattern(count: 5000, seed: 1))
        try Fixtures.makeFile(source.path + "/efi/microsoft/boot/fonts/segmono_boot.ttf", pattern(count: 3000, seed: 2))
        try Fixtures.makeFile(source.path + "/efi/microsoft/boot/fonts/wgl4_boot.ttf", pattern(count: 4000, seed: 3))
        let replacement = pattern(count: 7000, seed: 4)
        let replacementSource = scratch.url.appendingPathComponent("replacement.efi")
        try Data(replacement).write(to: replacementSource)
        let image = try scratch.makeVolume()

        do {
            let volume = try NTFSVolume(path: image, mode: .readWrite)
            _ = try volume.copyTree(from: source)
            try volume.removeItem("/EFI/Boot/BOOTX64.EFI")
            try volume.removeItem("/Efi/Microsoft/Boot/Fonts/SEGMONO_BOOT.TTF")
            // The lookups of the other methods stay case-sensitive.
            #expect(throws: NTFS3GError.notFound("/EFI")) {
                try volume.writeFile("/EFI/Boot/BOOTX64.EFI", from: replacementSource)
            }
            try volume.writeFile("/efi/boot/bootx64.efi", from: replacementSource)
            try volume.close()
        }

        let volume = try NTFSVolume(path: image, mode: .readOnly)
        defer { try? volume.close() }
        #expect(try volume.contentsOfDirectory("/efi/boot") == [.init(name: "bootx64.efi", kind: .file)])
        #expect(try volume.readAll("/efi/boot/bootx64.efi") == replacement)
        #expect(try volume.contentsOfDirectory("/efi/microsoft/boot/fonts") == [.init(name: "wgl4_boot.ttf", kind: .file)])
    }

    @Test func removeNFDSpelling() throws {
        try withScratchVolume { volume, _ throws in
            try volume.writeFile("/한글 이름.txt", contents: [1])
            try volume.removeItem("/한글 이름.txt".decomposedStringWithCanonicalMapping)
            #expect(try volume.contentsOfDirectory("/").isEmpty)
        }
    }

    @Test func removeEmptyDirectory() throws {
        try withScratchVolume { volume, _ throws in
            try volume.createDirectory("/a")
            try volume.createDirectory("/a/b")
            try volume.removeItem("/a/b")
            #expect(try volume.contentsOfDirectory("/a").isEmpty)
            try volume.removeItem("/a")
            #expect(try volume.contentsOfDirectory("/").isEmpty)
        }
    }

    @Test func removeNonEmptyDirectoryThrows() throws {
        try withScratchVolume { volume, _ throws in
            try volume.createDirectory("/d")
            try volume.writeFile("/d/f", contents: [1, 2, 3])
            #expect(throws: NTFS3GError.directoryNotEmpty("/d")) {
                try volume.removeItem("/d")
            }
            #expect(try volume.contentsOfDirectory("/d") == [.init(name: "f", kind: .file)])
            #expect(try volume.readAll("/d/f") == [1, 2, 3])

            try volume.createDirectory("/e")
            try volume.createDirectory("/e/sub")
            #expect(throws: NTFS3GError.directoryNotEmpty("/e")) {
                try volume.removeItem("/e")
            }

            try volume.removeItem("/d/f")
            try volume.removeItem("/d")
            #expect(try volume.contentsOfDirectory("/") == [.init(name: "e", kind: .directory)])
        }
    }

    /// Enough entries that the directory index is a B+tree, removed with mixed case, and then
    /// the emptied directory itself.
    @Test func removeFromLargeDirectory() throws {
        try withScratchVolume { volume, _ throws in
            try volume.createDirectory("/d")
            for index in 0..<600 {
                try volume.writeFile("/d/Name-\(index)", contents: [UInt8(truncatingIfNeeded: index)])
            }
            for index in stride(from: 0, to: 600, by: 2) {
                try volume.removeItem("/d/NAME-\(index)")
            }
            let remaining = try volume.contentsOfDirectory("/d")
            #expect(remaining.count == 300)
            #expect(remaining.allSatisfy { Int($0.name.dropFirst("Name-".count))! % 2 == 1 })
            #expect(try volume.readAll("/d/Name-299") == [UInt8(299 & 0xFF)])
            for index in stride(from: 1, to: 600, by: 2) {
                try volume.removeItem("/d/Name-\(index)")
            }
            #expect(try volume.contentsOfDirectory("/d").isEmpty)
            try volume.removeItem("/d")
            #expect(try volume.contentsOfDirectory("/").isEmpty)
        }
    }

    @Test func removeMissingThrowsNotFound() throws {
        try withScratchVolume { volume, _ throws in
            try volume.createDirectory("/a")
            try volume.writeFile("/f", contents: [1])
            #expect(throws: NTFS3GError.notFound("/missing")) {
                try volume.removeItem("/missing")
            }
            #expect(throws: NTFS3GError.notFound("/a/missing")) {
                try volume.removeItem("/a/missing")
            }
            #expect(throws: NTFS3GError.notFound("/missing")) {
                try volume.removeItem("/missing/x")
            }
            #expect(throws: NTFS3GError.notADirectory("/f")) {
                try volume.removeItem("/f/x")
            }
            #expect(try volume.contentsOfDirectory("/").count == 2)
        }
    }

    @Test(arguments: ["/", "a", "", "/a/", "/a//b", "/a/..", "/./a"])
    func removeRejectsInvalidPaths(path: String) throws {
        try withScratchVolume { volume, _ throws in
            try volume.createDirectory("/a")
            #expect(throws: NTFS3GError.invalidPath(path)) {
                try volume.removeItem(path)
            }
            #expect(try volume.contentsOfDirectory("/") == [.init(name: "a", kind: .directory)])
        }
    }

    /// Removing a metadata file would corrupt the volume; the ntfs-3g driver refuses with EPERM.
    @Test(arguments: ["/$MFT", "/$mft", "/$Bitmap", "/$Extend", "/$Extend/$Quota", "/$extend/$ObjId"])
    func removeMetadataThrows(path: String) throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let image = try scratch.makeVolume()
        do {
            let volume = try NTFSVolume(path: image, mode: .readWrite)
            #expect(throws: NTFS3GError.posix(operation: "remove", path: path, errno: EPERM)) {
                try volume.removeItem(path)
            }
            try volume.close()
        }
        let volume = try NTFSVolume(path: image, mode: .readWrite)
        defer { try? volume.close() }
        try volume.writeFile("/after.txt", contents: [1])
        #expect(try volume.contentsOfDirectory("/") == [.init(name: "after.txt", kind: .file)])
    }

    @Test func removeOnReadOnlyVolume() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let image = try scratch.makeVolume()
        do {
            let volume = try NTFSVolume(path: image, mode: .readWrite)
            try volume.writeFile("/f", contents: [1])
            try volume.close()
        }
        let volume = try NTFSVolume(path: image, mode: .readOnly)
        defer { try? volume.close() }
        #expect(throws: NTFS3GError.readOnlyVolume) {
            try volume.removeItem("/f")
        }
        #expect(throws: NTFS3GError.readOnlyVolume) {
            try volume.removeItem("/missing")
        }
        #expect(try volume.contentsOfDirectory("/") == [.init(name: "f", kind: .file)])
    }

    @Test func removeAfterClose() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let volume = try NTFSVolume(path: try scratch.makeVolume(), mode: .readWrite)
        try volume.writeFile("/f", contents: [1])
        try volume.close()
        #expect(throws: NTFS3GError.volumeClosed) {
            try volume.removeItem("/f")
        }
    }
}
