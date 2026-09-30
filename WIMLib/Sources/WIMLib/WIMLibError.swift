// SPDX-License-Identifier: LGPL-2.1-or-later

import Foundation

/// Errors thrown by ``WIMFile``.
public enum WIMLibError: Error, Equatable {
    /// A wimlib call failed. `code` is wimlib's `enum wimlib_error_code` value (for example
    /// `WIMLIB_ERR_PATH_DOES_NOT_EXIST`) and `message` is wimlib's description of it.
    case wimlib(code: Int32, message: String)

    /// A system call made by this package failed with `errno`.
    case posix(operation: String, path: String?, errno: Int32)

    /// ``WIMFile/close()`` has already been called.
    case closed
}

extension WIMLibError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .wimlib(let code, let message):
            "wimlib error \(code): \(message)"
        case .posix(let operation, let path, let code):
            "\(operation)\(path.map { " \($0)" } ?? ""): \(String(cString: strerror(code)))"
        case .closed:
            "the WIM file is closed"
        }
    }
}
