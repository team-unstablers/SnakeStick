// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Security
import SnakeStickCore

/// The daemon's side of the authorization (decision 19): the right in the policy database, and
/// acquiring it through the authorization the app sent.
enum HelperAuthorization {
    enum Outcome {
        case granted
        case cancelled
        case denied(OSStatus)
    }

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

    /// Acquires the right through `externalForm`, an authorization the app created in the
    /// user's session. The system shows the administrator dialog there with `prompt`; this call
    /// blocks until the user answers.
    ///
    /// The app cannot ask first and hand over the result: `authenticate-admin` has a timeout of
    /// 0, so a credential it acquired is not valid for a second evaluation here.
    static func acquire(_ externalForm: Data, prompt: String) -> Outcome {
        guard externalForm.count == MemoryLayout<AuthorizationExternalForm>.size else {
            return .denied(errAuthorizationInvalidRef)
        }
        var form = AuthorizationExternalForm()
        withUnsafeMutableBytes(of: &form) { _ = externalForm.copyBytes(to: $0) }
        var reference: AuthorizationRef?
        let created = AuthorizationCreateFromExternalForm(&form, &reference)
        guard created == errAuthorizationSuccess, let reference else {
            return .denied(created)
        }
        defer { AuthorizationFree(reference, []) }
        let status = HelperConstants.authorizationRight.withCString { name in
            kAuthorizationEnvironmentPrompt.withCString { promptKey in
                prompt.withCString { promptText in
                    var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
                    var promptItem = AuthorizationItem(
                        name: promptKey, valueLength: strlen(promptText),
                        value: UnsafeMutableRawPointer(mutating: promptText), flags: 0
                    )
                    return withUnsafeMutablePointer(to: &item) { itemPointer in
                        withUnsafeMutablePointer(to: &promptItem) { promptPointer in
                            var rights = AuthorizationRights(count: 1, items: itemPointer)
                            var environment = AuthorizationEnvironment(count: 1, items: promptPointer)
                            return AuthorizationCopyRights(reference, &rights, &environment, [.extendRights, .interactionAllowed], nil)
                        }
                    }
                }
            }
        }
        switch status {
        case errAuthorizationSuccess: return .granted
        case errAuthorizationCanceled: return .cancelled
        default: return .denied(status)
        }
    }
}
