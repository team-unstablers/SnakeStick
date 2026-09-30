// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Security
import SnakeStickCore

/// The daemon's side of P10: the right in the policy database, and checking what the app sends.
enum HelperAuthorization {
    /// Adds ``HelperConstants/authorizationRight`` with the "authenticate as admin" rule if the
    /// policy database does not have it yet. Runs as root at startup.
    static func registerRightIfNeeded(log: (String) -> Void) {
        let right = HelperConstants.authorizationRight
        if AuthorizationRightGet(right, nil) == errAuthorizationSuccess {
            return
        }
        var reference: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &reference) == errAuthorizationSuccess, let reference else {
            log("authorization: AuthorizationCreate failed")
            return
        }
        defer { AuthorizationFree(reference, []) }
        let status = AuthorizationRightSet(
            reference, right, kAuthorizationRuleAuthenticateAsAdmin as CFString,
            "SnakeStick wants to erase a disk and write a Windows installer to it." as CFString, nil, nil
        )
        log("authorization: registering \(right): \(status == errAuthorizationSuccess ? "done" : "failed (\(status))")")
    }

    /// Whether `externalForm` is a live authorization that holds the right, without asking the
    /// user anything (the app already did).
    static func verify(_ externalForm: Data) -> Bool {
        guard externalForm.count == MemoryLayout<AuthorizationExternalForm>.size else {
            return false
        }
        var form = AuthorizationExternalForm()
        withUnsafeMutableBytes(of: &form) { _ = externalForm.copyBytes(to: $0) }
        var reference: AuthorizationRef?
        guard AuthorizationCreateFromExternalForm(&form, &reference) == errAuthorizationSuccess, let reference else {
            return false
        }
        defer { AuthorizationFree(reference, []) }
        return HelperConstants.authorizationRight.withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { itemPointer in
                var rights = AuthorizationRights(count: 1, items: itemPointer)
                return AuthorizationCopyRights(reference, &rights, nil, [.extendRights], nil) == errAuthorizationSuccess
            }
        }
    }
}
