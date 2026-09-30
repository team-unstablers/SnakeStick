// SPDX-License-Identifier: LGPL-2.1-or-later

internal import CWIMLib
import Foundation

/// Process-wide libwim setup and error conversion.
enum WIMLibGlobal {
    /// The result of `wimlib_global_init`, run once per process on first use.
    ///
    /// wimlib documents `wimlib_global_init` and `wimlib_set_print_errors` as global state that
    /// may only change while no other thread is in the library. The lazy initializer of a
    /// static property runs exactly once, and every other caller waits for it, so it is the
    /// serialization point: nothing in this package calls wimlib before `initialize()`.
    ///
    /// Paths inside images are looked up case-insensitively, as on Windows. wimlib's default on
    /// UNIX-like systems is case-sensitive.
    private static let initializationStatus: Int32 = {
        let status = wimlib_global_init(Int32(WIMLIB_INIT_FLAG_DEFAULT_CASE_INSENSITIVE))
        // Errors are reported through WIMLibError; wimlib would otherwise print them to stderr.
        _ = wimlib_set_print_errors(false)
        return status
    }()

    static func initialize() throws(WIMLibError) {
        try check(initializationStatus)
    }

    static func check(_ status: Int32) throws(WIMLibError) {
        guard status == 0 else {
            throw error(status)
        }
    }

    static func error(_ status: Int32) -> WIMLibError {
        let code = wimlib_error_code(rawValue: .init(truncatingIfNeeded: status))
        let message = wimlib_get_error_string(code).map { String(cString: $0) } ?? "unknown error"
        return .wimlib(code: status, message: message)
    }

    static func error(_ code: wimlib_error_code) -> WIMLibError {
        error(Int32(truncatingIfNeeded: code.rawValue))
    }
}

/// Calls `body` with a NUL-terminated copy of each string, kept alive for the duration of the
/// call. Strings containing NUL are rejected, since C would silently truncate them.
func withCStrings<Result>(
    _ strings: [String],
    _ body: ([UnsafePointer<CChar>?]) throws(WIMLibError) -> Result
) throws(WIMLibError) -> Result {
    guard !strings.contains(where: { $0.utf8.contains(0) }) else {
        throw WIMLibGlobal.error(WIMLIB_ERR_INVALID_PARAM)
    }
    let copies = strings.map { strdup($0) }
    defer { copies.forEach { free($0) } }
    guard !copies.contains(nil) else {
        throw WIMLibGlobal.error(WIMLIB_ERR_NOMEM)
    }
    return try body(copies.map { UnsafePointer($0) })
}

/// Calls `body` with a NUL-terminated copy of `string`. See ``withCStrings(_:_:)``.
func withCString<Result>(
    _ string: String,
    _ body: (UnsafePointer<CChar>) throws(WIMLibError) -> Result
) throws(WIMLibError) -> Result {
    try withCStrings([string]) { (pointers) throws(WIMLibError) -> Result in
        try body(pointers[0]!)
    }
}
