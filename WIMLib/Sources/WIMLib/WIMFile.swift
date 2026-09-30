// SPDX-License-Identifier: LGPL-3.0-or-later

internal import CWIMLib
import Foundation

/// A WIM file opened for reading through wimlib.
///
/// Paths inside an image are absolute, such as `/Windows/Boot/EFI_EX`. Both `/` and `\` are
/// accepted as separators, and names are matched ignoring case, as Windows does.
///
/// All methods block on file I/O. The class is not `Sendable`: wimlib allows different WIM
/// files to be used from different threads, but not one WIM file from several threads at
/// once. Create it, use it and close it from one task.
public final class WIMFile {
    /// The path the file was opened from.
    public let path: String

    private var handle: OpaquePointer?

    /// Opens the WIM file at `path`. The file's integrity table, if any, is not checked.
    public init(path: String) throws {
        try WIMLibGlobal.initialize()
        var wim: OpaquePointer?
        let status = try withCString(path) { (cPath) throws(WIMLibError) -> Int32 in
            wimlib_open_wim(cPath, 0, &wim)
        }
        try WIMLibGlobal.check(status)
        guard let wim else {
            throw WIMLibGlobal.error(WIMLIB_ERR_NOMEM)
        }
        self.path = path
        handle = wim
    }

    deinit {
        close()
    }

    /// Releases the WIM file. Calling it again does nothing. Every other method throws
    /// ``WIMLibError/closed`` afterwards.
    public func close() {
        guard let handle else {
            return
        }
        self.handle = nil
        wimlib_free(handle)
    }

    /// The images in the file, in index order (the first has index 1).
    public var images: [WIMImage] {
        get throws {
            let wim = try requireOpen()
            var info = wimlib_wim_info()
            try WIMLibGlobal.check(wimlib_get_wim_info(wim, &info))
            return (0..<Int(info.image_count)).map { offset in
                let index = offset + 1
                return WIMImage(index: index) { name in
                    Self.property(name, ofImage: index, in: wim)
                }
            }
        }
    }

    /// The text of an element in an image's XML metadata, or `nil` if there is no such element.
    ///
    /// `name` is a path of element names below the image's `IMAGE` element, separated by `/`,
    /// such as `WINDOWS/VERSION/BUILD`. A bracketed 1-based number selects one of several
    /// elements with the same name, as in `WINDOWS/LANGUAGES/LANGUAGE[2]`. Element names are
    /// case-sensitive.
    public func property(_ name: String, ofImage index: Int) throws -> String? {
        let wim = try requireOpen()
        let image = try imageNumber(index, in: wim)
        return try withCString(name) { (cName) throws(WIMLibError) -> String? in
            wimlib_get_image_property(wim, image, cName).map { String(cString: $0) }
        }
    }

    /// Extracts files and directories from image `index` into `directory`.
    ///
    /// Each path is placed directly in `directory`, without the directories above it: the
    /// file `/Windows/Boot/EFI_EX/bootmgfw_EX.efi` is extracted to
    /// `directory/bootmgfw_EX.efi`, and the directory `/Windows/Boot/EFI_EX` to
    /// `directory/EFI_EX`, with everything below it. Existing files are replaced. Access
    /// control lists are not extracted.
    ///
    /// `directory` must exist. If any path does not exist in the image, nothing is extracted
    /// and the error is `WIMLIB_ERR_PATH_DOES_NOT_EXIST`.
    public func extract(paths: [String], fromImage index: Int, to directory: URL) throws {
        let wim = try requireOpen()
        let image = try imageNumber(index, in: wim)
        guard directory.isFileURL else {
            throw WIMLibError.posix(operation: "extract", path: directory.absoluteString, errno: EINVAL)
        }
        let target = Self.fileSystemPath(directory)
        // wimlib creates a missing target directory (one level) instead of failing.
        var info = stat()
        guard stat(target, &info) == 0 else {
            throw WIMLibError.posix(operation: "stat", path: target, errno: errno)
        }
        guard info.st_mode & S_IFMT == S_IFDIR else {
            throw WIMLibError.posix(operation: "extract", path: target, errno: ENOTDIR)
        }

        let flags = Int32(WIMLIB_EXTRACT_FLAG_NO_ACLS | WIMLIB_EXTRACT_FLAG_NO_PRESERVE_DIR_STRUCTURE)
        let wimPaths = paths.map { $0.replacingOccurrences(of: "\\", with: "/") }
        let status = try withCString(target) { (cTarget) throws(WIMLibError) -> Int32 in
            try withCStrings(wimPaths) { (cPaths) throws(WIMLibError) -> Int32 in
                wimlib_extract_paths(wim, image, cTarget, cPaths, cPaths.count, flags)
            }
        }
        try WIMLibGlobal.check(status)
    }

    /// Writes a new WIM file at `path` holding one image captured from `directory`.
    ///
    /// This is meant for tests and fixtures, not for making Windows images. `properties` are
    /// set on the image in the XML metadata, with keys in the syntax of
    /// ``property(_:ofImage:)``, such as `["WINDOWS/ARCH": "9"]`. An existing file at `path`
    /// is replaced.
    public static func create(
        from directory: URL,
        to path: String,
        compression: WIMCompression = .lzx,
        imageName: String,
        properties: [String: String] = [:]
    ) throws {
        try WIMLibGlobal.initialize()
        guard directory.isFileURL else {
            throw WIMLibError.posix(operation: "create", path: directory.absoluteString, errno: EINVAL)
        }
        let source = fileSystemPath(directory)
        let type = switch compression {
        case .none: WIMLIB_COMPRESSION_TYPE_NONE
        case .xpress: WIMLIB_COMPRESSION_TYPE_XPRESS
        case .lzx: WIMLIB_COMPRESSION_TYPE_LZX
        }

        var created: OpaquePointer?
        try WIMLibGlobal.check(wimlib_create_new_wim(type, &created))
        guard let wim = created else {
            throw WIMLibGlobal.error(WIMLIB_ERR_NOMEM)
        }
        defer { wimlib_free(wim) }

        let status = try withCStrings([source, imageName]) { (strings) throws(WIMLibError) -> Int32 in
            wimlib_add_image(wim, strings[0], strings[1], nil, 0)
        }
        try WIMLibGlobal.check(status)

        for (name, value) in properties.sorted(by: { $0.key < $1.key }) {
            let status = try withCStrings([name, value]) { (strings) throws(WIMLibError) -> Int32 in
                wimlib_set_image_property(wim, 1, strings[0], strings[1])
            }
            try WIMLibGlobal.check(status)
        }

        let writeStatus = try withCString(path) { (cPath) throws(WIMLibError) -> Int32 in
            wimlib_write(wim, cPath, WIMLIB_ALL_IMAGES, 0, 0)
        }
        try WIMLibGlobal.check(writeStatus)
    }

    /// The version of the linked wimlib, such as `1.14.5`.
    public static var wimlibVersion: String {
        String(cString: wimlib_get_version_string())
    }

    private func requireOpen() throws(WIMLibError) -> OpaquePointer {
        guard let handle else {
            throw .closed
        }
        return handle
    }

    /// Checks that `index` names an image of `wim`; wimlib's lookups would return nothing or
    /// act on all images for some out-of-range values.
    private func imageNumber(_ index: Int, in wim: OpaquePointer) throws(WIMLibError) -> Int32 {
        var info = wimlib_wim_info()
        try WIMLibGlobal.check(wimlib_get_wim_info(wim, &info))
        guard index >= 1, index <= Int(info.image_count) else {
            throw WIMLibGlobal.error(WIMLIB_ERR_INVALID_IMAGE)
        }
        return Int32(index)
    }

    /// The path of a file URL, without the trailing slash that directory URLs carry.
    private static func fileSystemPath(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    private static func property(_ name: String, ofImage index: Int, in wim: OpaquePointer) -> String? {
        // The returned string is only valid until the next wimlib call, so copy it at once.
        wimlib_get_image_property(wim, Int32(index), name).map { String(cString: $0) }
    }
}
