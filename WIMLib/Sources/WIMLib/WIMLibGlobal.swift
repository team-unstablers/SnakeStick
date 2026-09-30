// SPDX-License-Identifier: LGPL-3.0-or-later

internal import CWIMLib

/// Process-wide libwim setup.
enum WIMLibGlobal {
    /// Placeholder until the Swift API lands; replaced in the next step.
    static var versionString: String {
        String(cString: wimlib_get_version_string())
    }
}
