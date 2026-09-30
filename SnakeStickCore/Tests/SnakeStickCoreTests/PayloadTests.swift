// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SnakeStickCore

struct PayloadTests {
    @Test func bundledFilesMatchVersionsFile() throws {
        let recorded = try UEFINTFSPayload.recordedHashes()
        #expect(Set(recorded.keys) == Set(UEFINTFSPayload.fileNames))
        for name in UEFINTFSPayload.fileNames {
            let actual = try UEFINTFSPayload.sha256(of: UEFINTFSPayload.url(of: name))
            #expect(actual == recorded[name], "\(name)")
        }
    }

    @Test func bundledFilesAreSignedPEImages() throws {
        for name in UEFINTFSPayload.fileNames {
            let data = try Data(contentsOf: UEFINTFSPayload.url(of: name))
            #expect(data.prefix(2) == Data("MZ".utf8), "\(name) is a PE image")
            // A signed PE has a non-empty certificate table (data directory entry 4).
            let peOffset = Int(data[0x3C]) | Int(data[0x3D]) << 8 | Int(data[0x3E]) << 16 | Int(data[0x3F]) << 24
            let magic = UInt16(data[peOffset + 24]) | UInt16(data[peOffset + 25]) << 8
            let directories = peOffset + 24 + (magic == 0x20B ? 112 : 96)
            let entry = directories + 4 * 8
            let size = (0 ..< 4).reduce(0) { $0 | Int(data[entry + 4 + $1]) << (8 * $1) }
            #expect(size > 0, "\(name) carries an Authenticode signature")
        }
    }

    @Test func licenseIsBundled() throws {
        let text = try String(contentsOf: UEFINTFSPayload.directory().appendingPathComponent("LICENSE.uefi-ntfs"), encoding: .utf8)
        #expect(text.contains("GNU GENERAL PUBLIC LICENSE"))
        #expect(text.contains("Version 2, June 1991"))
    }

    @Test func versionsParserReadsRowsOnly() {
        let text = """
        | File | Release asset | Size | SHA-256 | Downloaded from |
        |---|---|---|---|---|
        | `bootx64.efi` | `bootx64_signed.efi` | 1 | `\(String(repeating: "A", count: 64))` | https://example |
        | `other.efi` | `x` | 1 | `\(String(repeating: "b", count: 64))` | https://example |
        """
        #expect(UEFINTFSPayload.parseRecordedHashes(text) == ["bootx64.efi": String(repeating: "a", count: 64)])
    }
}
