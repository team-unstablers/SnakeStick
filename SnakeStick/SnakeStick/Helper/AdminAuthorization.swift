// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Security
import SnakeStickCore

/// The app's side of P10: asks for an administrator once per write and hands the daemon an
/// external form of the authorization.
///
/// The `AuthorizationRef` is freed on deinit; keep the instance until the daemon has accepted the
/// job, because the external form is only valid while the reference lives (C25).
nonisolated final class AdminAuthorization: @unchecked Sendable {
    // Unchecked: both members are immutable after init; Authorization Services refs are
    // thread-safe to pass around.
    let reference: AuthorizationRef
    let externalForm: Data

    enum Failure: Error {
        case cancelled
        case denied(OSStatus)
    }

    private init(reference: AuthorizationRef, externalForm: Data) {
        self.reference = reference
        self.externalForm = externalForm
    }

    deinit {
        AuthorizationFree(reference, [.destroyRights])
    }

    /// Shows the system authentication dialog for ``HelperConstants/authorizationRight`` with
    /// `prompt`. Blocks while the dialog is up; call it off the main thread.
    static func request(prompt: String) throws -> AdminAuthorization {
        var created: AuthorizationRef?
        var status = AuthorizationCreate(nil, nil, [], &created)
        guard status == errAuthorizationSuccess, let reference = created else {
            throw Failure.denied(status)
        }
        status = HelperConstants.authorizationRight.withCString { name in
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
                            return AuthorizationCopyRights(reference, &rights, &environment, [.interactionAllowed, .extendRights, .preAuthorize], nil)
                        }
                    }
                }
            }
        }
        guard status == errAuthorizationSuccess else {
            AuthorizationFree(reference, [])
            throw status == errAuthorizationCanceled ? Failure.cancelled : Failure.denied(status)
        }
        var form = AuthorizationExternalForm()
        status = AuthorizationMakeExternalForm(reference, &form)
        guard status == errAuthorizationSuccess else {
            AuthorizationFree(reference, [.destroyRights])
            throw Failure.denied(status)
        }
        let data = withUnsafeBytes(of: &form) { Data($0) }
        return AdminAuthorization(reference: reference, externalForm: data)
    }
}
