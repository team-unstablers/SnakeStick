// SPDX-License-Identifier: LGPL-3.0-or-later

import CWIMLib
import Testing

/// Smoke test for the vendored libwim build: the library links and reports the pinned version.
@Test func versionString() {
    #expect(String(cString: wimlib_get_version_string()) == "1.14.5")
    #expect(wimlib_get_version() == (1 << 20) | (14 << 10) | 5)
}
