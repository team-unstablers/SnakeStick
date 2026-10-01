// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

/// The bundled, Microsoft-signed UEFI:NTFS loader and NTFS driver (`Resources/UEFI-NTFS`).
///
/// `Scripts/update-uefi-ntfs.sh` downloads them and records their hashes in `VERSIONS.md`.
public enum UEFINTFSPayload {
    /// The files copied to `/efi/boot/` on the FAT partition, under these names.
    public static let fileNames = ["bootx64.efi", "bootaa64.efi", "ntfs_x64.efi", "ntfs_aa64.efi"]

    /// Where the files are copied on the FAT partition.
    static let directoryOnPartition = "efi/boot"

    /// The resource directory holding the files and `VERSIONS.md`.
    ///
    /// Looked up by hand rather than through `Bundle.module`, whose accessor calls `fatalError`
    /// when the bundle is missing, and which does not look in `Contents/Resources` for the
    /// command line tool the app bundles as `Contents/Helpers/snakestick`.
    public static func directory() throws -> URL {
        let bundleName = "SnakeStickCore_SnakeStickCore.bundle"
        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
        let candidates: [URL?] = [
            Bundle.main.resourceURL,                                            // app
            executableDirectory?.deletingLastPathComponent().appendingPathComponent("Resources"),  // tool in Contents/Helpers
            Bundle.main.bundleURL,                                              // command line tool
            executableDirectory,
            Bundle(for: BundleMarker.self).resourceURL,                         // test bundle, framework
            Bundle(for: BundleMarker.self).bundleURL.deletingLastPathComponent(),
        ]
        for candidate in candidates.compactMap({ $0 }) {
            if let bundle = Bundle(url: candidate.appendingPathComponent(bundleName)),
               let url = bundle.url(forResource: "UEFI-NTFS", withExtension: nil) {
                return url
            }
        }
        throw InstallerError(
            phase: .prepareBootPartition, kind: .other,
            message: "The bundled UEFI:NTFS files (\(bundleName)) are missing next to \(Bundle.main.bundlePath)."
        )
    }

    private final class BundleMarker {}

    public static func url(of name: String) throws -> URL {
        try directory().appendingPathComponent(name)
    }

    /// The SHA-256 of the file at `url`, in lowercase hex.
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The hashes recorded in `VERSIONS.md`, by file name.
    public static func recordedHashes() throws -> [String: String] {
        let text = try String(contentsOf: directory().appendingPathComponent("VERSIONS.md"), encoding: .utf8)
        return parseRecordedHashes(text)
    }

    /// Reads the rows `| \`name\` | ... | \`<64 hex digits>\` | ...` of `VERSIONS.md`.
    static func parseRecordedHashes(_ text: String) -> [String: String] {
        var hashes: [String: String] = [:]
        for line in text.split(separator: "\n") where line.hasPrefix("| `") {
            let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let name = cells.first?.trimmingCharacters(in: CharacterSet(charactersIn: "`")),
                  fileNames.contains(name),
                  let hash = cells.lazy
                      .map({ $0.trimmingCharacters(in: CharacterSet(charactersIn: "`")) })
                      .first(where: { $0.count == 64 && $0.allSatisfy(\.isHexDigit) })
            else {
                continue
            }
            hashes[name] = hash.lowercased()
        }
        return hashes
    }
}
