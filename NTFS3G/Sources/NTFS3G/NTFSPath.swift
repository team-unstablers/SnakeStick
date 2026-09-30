// SPDX-License-Identifier: GPL-2.0-or-later

internal import CNTFS3G
import Foundation

/// An absolute path inside an NTFS volume, split into components.
///
/// Paths start with `/` and use `/` as the separator. Empty, `.` and `..` components are
/// rejected, as is a trailing `/` on anything but the root.
///
/// Components are normalized to Unicode NFC, the form Windows produces, and are then stored and
/// looked up byte for byte. NTFS itself does not normalize, and macOS's NTFS driver (FSKit)
/// cannot open items whose names are stored decomposed (NFD), which is how Foundation and many
/// macOS tools spell names on the host.
struct NTFSPath {
    let components: [String]

    static let root = NTFSPath(components: [])

    private init(components: [String]) {
        self.components = components
    }

    init(_ string: String) throws(NTFS3GError) {
        // Work on UTF-8 bytes: String's Character view would merge "/" with a following
        // combining mark into a single grapheme cluster.
        let slash = UInt8(ascii: "/")
        let bytes = Array(string.utf8)
        guard bytes.first == slash else {
            throw .invalidPath(string)
        }
        if bytes.count == 1 {
            self.init(components: [])
            return
        }
        var components: [String] = []
        for part in bytes.dropFirst().split(separator: slash, omittingEmptySubsequences: false) {
            guard !part.isEmpty, !part.elementsEqual(".".utf8), !part.elementsEqual("..".utf8) else {
                throw .invalidPath(string)
            }
            components.append(Self.normalized(String(decoding: part, as: UTF8.self)))
        }
        self.init(components: components)
    }

    /// `name` in Unicode NFC.
    static func normalized(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping
    }

    var isRoot: Bool {
        components.isEmpty
    }

    /// The last component. `nil` for the root.
    var name: String? {
        components.last
    }

    /// The parent directory. The root is its own parent.
    var parent: NTFSPath {
        NTFSPath(components: Array(components.dropLast()))
    }

    /// This path with `name`, normalized to NFC, appended.
    func appending(_ name: String) -> NTFSPath {
        NTFSPath(components: components + [Self.normalized(name)])
    }

    /// The path made of the first `count` components.
    func prefix(_ count: Int) -> NTFSPath {
        NTFSPath(components: Array(components.prefix(count)))
    }

    var string: String {
        "/" + components.joined(separator: "/")
    }
}

/// A file name converted to NTFS's UTF-16 with `ntfs_mbstoucs`.
///
/// The conversion is locale-independent as long as `ntfs_set_char_encoding` is never called,
/// which this package does not do.
struct NTFSName: ~Copyable {
    /// The longest name NTFS stores, in UTF-16 code units.
    static let maximumLength = 255

    let string: String
    let characters: UnsafeMutablePointer<ntfschar>
    let length: Int

    /// Converts `string`, which must be 1 to `maximumLength` UTF-16 code units long and must not
    /// contain NUL. Throws `.invalidName` otherwise.
    init(_ string: String, maximumLength: Int = NTFSName.maximumLength) throws(NTFS3GError) {
        // ntfs_mbstoucs takes a C string and would silently stop at an embedded NUL.
        guard !string.isEmpty, !string.utf8.contains(0) else {
            throw .invalidName(string)
        }
        var characters: UnsafeMutablePointer<ntfschar>?
        let length = ntfs_mbstoucs(string, &characters)
        guard length > 0, let characters else {
            let code = errno
            ntfs_ucsfree(characters)
            if code == EILSEQ || code == ENAMETOOLONG {
                throw .invalidName(string)
            }
            throw .posix(operation: "ntfs_mbstoucs", path: string, errno: code)
        }
        guard length <= maximumLength else {
            ntfs_ucsfree(characters)
            throw .invalidName(string)
        }
        self.string = string
        self.characters = characters
        self.length = Int(length)
    }

    deinit {
        ntfs_ucsfree(characters)
    }
}
