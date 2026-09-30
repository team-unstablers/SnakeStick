// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// Errors thrown by ``NTFSVolume``.
public enum NTFS3GError: Error, Equatable {
    /// The path is not an absolute NTFS path: it must start with `/`, use `/` as the separator,
    /// and contain no empty, `.` or `..` components. Only `/` itself may end with `/`.
    case invalidPath(String)

    /// The name (or volume label) cannot be used on Windows: it contains a forbidden character
    /// (`"*/:<>?\|` or a control character), ends with a dot or a space, is a reserved DOS
    /// device name such as `CON` or `NUL` (file and directory names only), or is too long.
    case invalidName(String)

    /// The path, or the component of it named here, does not exist.
    case notFound(String)

    /// An item with this name, or with a name that differs only in case, already exists.
    case alreadyExists(String)

    /// The path, or the component of it named here, is not a directory.
    case notADirectory(String)

    /// The operation needs a file, but the path names a directory.
    case isADirectory(String)

    /// The directory cannot be removed because it has entries.
    case directoryNotEmpty(String)

    /// The host item is neither a regular file nor a directory (a symbolic link, FIFO, socket or
    /// device).
    case unsupportedFileType(URL)

    /// The volume was opened with ``NTFSVolume/Mode/readOnly``.
    case readOnlyVolume

    /// ``NTFSVolume/close()`` has already been called.
    case volumeClosed

    /// mkntfs exited with a non-zero status.
    case formatFailed(status: Int32)

    /// A system or libntfs-3g call failed with `errno`.
    case posix(operation: String, path: String?, errno: Int32)
}

extension NTFS3GError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidPath(let path):
            "invalid NTFS path: \(path)"
        case .invalidName(let name):
            "name not allowed on Windows: \(name)"
        case .notFound(let path):
            "no such file or directory: \(path)"
        case .alreadyExists(let path):
            "already exists: \(path)"
        case .notADirectory(let path):
            "not a directory: \(path)"
        case .isADirectory(let path):
            "is a directory: \(path)"
        case .directoryNotEmpty(let path):
            "directory not empty: \(path)"
        case .unsupportedFileType(let url):
            "not a regular file or directory: \(url.path)"
        case .readOnlyVolume:
            "the volume is mounted read-only"
        case .volumeClosed:
            "the volume is closed"
        case .formatFailed(let status):
            "mkntfs failed with status \(status)"
        case .posix(let operation, let path, let code):
            "\(operation)\(path.map { " \($0)" } ?? ""): \(String(cString: strerror(code)))"
        }
    }
}
