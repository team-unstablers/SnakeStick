import Foundation

/// NTFS volume label rules.
///
/// These mirror `NTFSVolume.validateLabel` in NTFS3G, which is internal to that package, so that
/// a bad label is rejected before the target is touched instead of when mkntfs runs (step 5).
/// NTFS3G still checks the label itself when it formats.
public enum VolumeLabel {
    /// The longest label NTFS accepts, in UTF-16 code units.
    public static let maximumLength = 32

    /// Used when neither the caller nor the ISO gives a usable label.
    public static let fallback = "WINDOWS"

    /// Whether `label` can be given to NTFS3G: empty (no label), or 1 to 32 UTF-16 code units
    /// after NFC normalization, without control characters or `"*/:<>?\|`, and not ending with
    /// a space or a dot.
    public static func isValid(_ label: String) -> Bool {
        let normalized = label.precomposedStringWithCanonicalMapping
        if normalized.isEmpty {
            return true
        }
        let units = Array(normalized.utf16)
        guard units.count <= maximumLength else {
            return false
        }
        if let last = units.last, last == 0x20 || last == 0x2E {  // space, dot
            return false
        }
        let forbidden = Set("\"*/:<>?\\|".utf16)
        return !units.contains { $0 < 0x20 || forbidden.contains($0) }
    }

    /// The label to write: `requested` if given (it must be valid; the caller checks), else the
    /// ISO's label if it is valid and not empty, else ``fallback``.
    public static func resolve(requested: String?, isoLabel: String) -> String {
        if let requested {
            return requested
        }
        if !isoLabel.isEmpty, isValid(isoLabel) {
            return isoLabel
        }
        return fallback
    }

    /// The GPT partition name for `label`: at most 36 UTF-16 code units, cut at a character
    /// boundary.
    static func partitionName(for label: String) -> String {
        var result = ""
        var count = 0
        for character in label {
            let length = String(character).utf16.count
            guard count + length <= 36 else {
                break
            }
            result.append(character)
            count += length
        }
        return result
    }
}
