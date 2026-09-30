// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import NTFS3G
import WIMLib

/// The Windows UEFI CA 2023 boot loader option (P7, §9, decision 28), done the way Rufus does it
/// (F23): extract `Windows/Boot/EFI_EX` and `Windows/Boot/Fonts_EX` from `boot.wim` image 2 and
/// put them over the 2011-signed files after the copy.
struct CA2023Replacements {
    struct Item: Equatable {
        /// Where the file goes on the NTFS volume, spelled as on the ISO when it replaces a file.
        let ntfsPath: String
        /// The extracted file.
        let source: URL
        /// Whether a file of that name is on the ISO (and so copied first, and removed here).
        let replacesExisting: Bool
    }

    let items: [Item]

    /// NTFS path → the file its content must equal after the replacement (for step 8).
    var expectedContents: [String: URL] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.ntfsPath, $0.source) })
    }

    static let missingMessage = "this ISO has no 2023-signed boot loaders"

    /// Extracts from `bootWIM` into `directory` (which must exist) and plans the replacements
    /// against the ISO tree at `isoRoot`. Any failure is an error: an option the user turned on
    /// must not be skipped silently (unlike Rufus).
    static func prepare(bootWIM: URL, isoRoot: URL, architecture: String, into directory: URL) throws -> CA2023Replacements {
        let loaderName: String
        switch architecture {
        case "x64": loaderName = "bootx64.efi"
        case "ARM64": loaderName = "bootaa64.efi"
        default:
            throw InstallerError(
                phase: .openISO, kind: .invalidISO,
                message: "The Windows UEFI CA 2023 boot loaders are only supported for x64 and ARM64, not \(architecture)."
            )
        }

        do {
            let wim = try WIMFile(path: bootWIM.path)
            defer { wim.close() }
            try wim.extract(paths: ["/Windows/Boot/EFI_EX", "/Windows/Boot/Fonts_EX"], fromImage: 2, to: directory)
        } catch let error as WIMLibError {
            // wimlib error codes (include/wimlib.h): 18 = INVALID_IMAGE, 49 = PATH_DOES_NOT_EXIST.
            if case .wimlib(let code, _) = error, code == 18 || code == 49 {
                throw InstallerError(phase: .openISO, kind: .invalidISO, message: "\(missingMessage.capitalizedFirst).", underlying: "\(error)")
            }
            throw InstallerError(
                phase: .openISO, kind: .io, message: "The 2023-signed boot loaders could not be extracted from boot.wim.",
                underlying: "\(error)", path: bootWIM.path
            )
        }

        // wimlib keeps the extracted directories: <directory>/EFI_EX/…, <directory>/Fonts_EX/….
        guard let bootmgfw = ISOImage.findItem(["EFI_EX", "bootmgfw_EX.efi"], under: directory),
              let bootmgr = ISOImage.findItem(["EFI_EX", "bootmgr_EX.efi"], under: directory)
        else {
            throw InstallerError(phase: .openISO, kind: .invalidISO, message: "\(missingMessage.capitalizedFirst).")
        }

        var items: [Item] = []
        items.append(try plan(["efi", "boot"], loaderName, source: bootmgfw, isoRoot: isoRoot))
        items.append(try plan([], "bootmgr.efi", source: bootmgr, isoRoot: isoRoot))

        if let fontsEX = ISOImage.findItem(["Fonts_EX"], under: directory) {
            let names = try FileManager.default.contentsOfDirectory(atPath: fontsEX.path).sorted()
            for name in names {
                guard let target = Self.fontName(forExtracted: name) else {
                    continue
                }
                items.append(try plan(["efi", "microsoft", "boot", "fonts"], target, source: fontsEX.appendingPathComponent(name), isoRoot: isoRoot))
            }
        }
        return CA2023Replacements(items: items)
    }

    /// `segoeui_EX.ttf` → `segoeui.ttf`; `nil` for names without `_EX` before the extension.
    static func fontName(forExtracted name: String) -> String? {
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        guard stem.count > 3, stem.uppercased().hasSuffix("_EX") else {
            return nil
        }
        let base = String(stem.dropLast(3))
        return ext.isEmpty ? base : "\(base).\(ext)"
    }

    /// Where `name` goes in `directory` (components under the ISO root), spelled as on the ISO.
    private static func plan(_ directory: [String], _ name: String, source: URL, isoRoot: URL) throws -> Item {
        guard let directoryURL = directory.isEmpty ? isoRoot : ISOImage.findItem(directory, under: isoRoot) else {
            throw InstallerError(
                phase: .openISO, kind: .invalidISO,
                message: "The ISO has no \(directory.joined(separator: "/")) directory for the 2023-signed boot files."
            )
        }
        let relativeDirectory = relativeComponents(of: directoryURL, under: isoRoot)
        let existing = ISOImage.findItem([name], under: directoryURL)
        let fileName = existing?.lastPathComponent ?? name
        let path = "/" + (relativeDirectory + [fileName]).map(\.precomposedStringWithCanonicalMapping).joined(separator: "/")
        return Item(ntfsPath: path, source: source, replacesExisting: existing != nil)
    }

    /// Removes each file that the copy put there and writes the 2023-signed one. Paths use the
    /// stored spelling: NTFS3G's `writeFile` looks up the parent directory case-sensitively.
    func apply(to volume: NTFSVolume, log: (String) -> Void) throws {
        for item in items {
            if item.replacesExisting {
                try volume.removeItem(item.ntfsPath)
            }
            try volume.writeFile(item.ntfsPath, from: item.source)
            log("CA 2023: \(item.replacesExisting ? "replaced" : "added") \(item.ntfsPath)")
        }
    }
}

func relativeComponents(of url: URL, under root: URL) -> [String] {
    let rootComponents = root.standardizedFileURL.pathComponents
    let components = url.standardizedFileURL.pathComponents
    return Array(components.dropFirst(rootComponents.count))
}

extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
