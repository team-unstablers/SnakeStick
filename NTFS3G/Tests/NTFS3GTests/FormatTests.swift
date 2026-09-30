// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import NTFS3G
import os
import Testing

@Suite struct FormatTests {
    @Test func formatSetsLabel() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let image = try scratch.makeVolume(options: .init(label: "SNAKESTICK"))

        let volume = try NTFSVolume(path: image, mode: .readOnly)
        defer { try? volume.close() }
        #expect(volume.label == "SNAKESTICK")
        #expect(volume.clusterSize == 4096)
    }

    @Test func formatWith4KSectors() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let image = try scratch.makeVolume(options: .init(sectorSize: 4096))

        let volume = try NTFSVolume(path: image, mode: .readOnly)
        defer { try? volume.close() }
        #expect(try volume.contentsOfDirectory("/").isEmpty)
    }

    @Test func formatWritesBootSectorGeometry() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let image = try scratch.makeVolume(options: .init(clusterSize: 8192, partitionStartSector: 2048))

        let bootSector = try [UInt8](Data(contentsOf: URL(fileURLWithPath: image)).prefix(512))
        func le(_ offset: Int, _ count: Int) -> UInt64 {
            (0..<count).reduce(0) { $0 | UInt64(bootSector[offset + $1]) << (8 * $1) }
        }
        #expect(bootSector[3..<11].elementsEqual("NTFS    ".utf8))
        #expect(le(0x0B, 2) == 512)                       // bytes per sector
        #expect(bootSector[0x0D] == 16)                   // sectors per cluster
        #expect(le(0x18, 2) == 63)                        // sectors per track
        #expect(le(0x1A, 2) == 255)                       // heads
        #expect(le(0x1C, 4) == 2048)                      // hidden sectors
    }

    @Test func formatMissingFileThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        #expect(throws: NTFS3GError.posix(operation: "stat", path: scratch.path("missing.img"), errno: ENOENT)) {
            try NTFSVolume.format(path: scratch.path("missing.img"))
        }
    }

    @Test(arguments: ["A:B", "A*", "trailing.", "trailing ", String(repeating: "L", count: 33)])
    func formatRejectsInvalidLabel(label: String) throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let image = try scratch.makeSparseFile("volume.img", size: 64 << 20)
        #expect(throws: NTFS3GError.invalidName(label)) {
            try NTFSVolume.format(path: image, options: .init(label: label))
        }
    }

    @Test func formatAcceptsReservedNameAsLabel() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let image = try scratch.makeVolume(options: .init(label: "CON"))
        let volume = try NTFSVolume(path: image, mode: .readOnly)
        defer { try? volume.close() }
        #expect(volume.label == "CON")
    }

    @Test func formatLeavesLocaleUnchanged() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let before = String(cString: setlocale(LC_ALL, nil))
        try scratch.makeVolume()
        let after = String(cString: setlocale(LC_ALL, nil))
        #expect(before == after)
    }

    /// The mkntfs program calls setlocale(LC_ALL, ""), which picks up the locale from the
    /// environment. In a child process, set the environment to a locale whose decimal point is a
    /// comma, and check that the process locale stays the same while and after formatting.
    @Test func formatIgnoresEnvironmentLocale() async {
        await #expect(processExitsWith: .success) {
            setenv("LC_ALL", "de_DE.UTF-8", 1)
            _ = setlocale(LC_ALL, "C")
            _ = setlocale(LC_TIME, "en_US.UTF-8")
            let before = String(cString: setlocale(LC_ALL, nil))

            // Watch the locale from another thread while mkntfs runs.
            let seen = OSAllocatedUnfairLock(initialState: Set<String>())
            let done = OSAllocatedUnfairLock(initialState: false)
            let watcher = Thread {
                while !done.withLock({ $0 }) {
                    let current = String(cString: setlocale(LC_ALL, nil))
                    seen.withLock { _ = $0.insert(current) }
                }
            }
            watcher.start()
            let scratch = try! ScratchDirectory()
            // Large enough that mkntfs runs long enough to be observed.
            try! scratch.makeVolume(size: 8 << 30)
            scratch.remove()
            done.withLock { $0 = true }

            let after = String(cString: setlocale(LC_ALL, nil))
            let observed = seen.withLock { $0 }
            let decimalPoint = String(cString: localeconv().pointee.decimal_point)
            guard before == after, observed.subtracting([before]).isEmpty, decimalPoint == "." else {
                fputs("locale before: \(before), after: \(after), observed: \(observed), decimal point: \(decimalPoint)\n", stderr)
                exit(1)
            }
            // Make sure the environment's locale really differs, or the checks above prove
            // nothing.
            _ = setlocale(LC_ALL, "")
            guard String(cString: setlocale(LC_ALL, nil)) != before,
                  String(cString: localeconv().pointee.decimal_point) == ","
            else {
                fputs("de_DE.UTF-8 is not available; the test is vacuous\n", stderr)
                exit(2)
            }
            exit(0)
        }
    }

    @Test func formatManyTimesInOneProcess() throws {
        // mkntfs.c is written to run once per process; see mkntfs_entry.c.
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        for index in 0..<5 {
            let image = try scratch.makeVolume("volume\(index).img", options: .init(label: "V\(index)"))
            let volume = try NTFSVolume(path: image, mode: .readOnly)
            #expect(volume.label == "V\(index)")
            try volume.close()
        }
    }

    @Test func mountUnformattedThrows() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let image = try scratch.makeSparseFile("zero.img", size: 64 << 20)
        #expect(throws: NTFS3GError.self) {
            try NTFSVolume(path: image, mode: .readOnly)
        }
        #expect(throws: NTFS3GError.self) {
            try NTFSVolume(path: image, mode: .readWrite)
        }
    }

    @Test func volumeReportsSizes() throws {
        let scratch = try ScratchDirectory()
        defer { scratch.remove() }
        let image = try scratch.makeVolume(size: 64 << 20)
        let volume = try NTFSVolume(path: image, mode: .readWrite)
        // The last cluster holds the backup boot sector and is not part of the volume.
        #expect(volume.totalBytes == (64 << 20) - 4096)
        let freeBefore = volume.freeBytes
        #expect(freeBefore > 60 << 20 && freeBefore < volume.totalBytes)
        try volume.writeFile("/f", contents: pattern(count: 1 << 20))
        #expect(volume.freeBytes <= freeBefore - (1 << 20))
        let freeAtClose = volume.freeBytes
        try volume.close()
        #expect(volume.freeBytes == freeAtClose)
    }
}
