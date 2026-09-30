// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Security

/// The app's side of the authorization (decision 19): an authorization created in the user's
/// session without asking for anything, handed to the daemon as an external form. The daemon
/// acquires the write right through it, which shows the administrator dialog here.
///
/// The `AuthorizationRef` is freed on deinit; keep the instance until the daemon has answered,
/// because the external form is only valid while the reference lives (C25).
nonisolated final class AdminAuthorization: @unchecked Sendable {
    // Unchecked: both members are immutable after init; Authorization Services refs may be
    // passed between threads.
    let reference: AuthorizationRef
    let externalForm: Data

    struct Failure: Error, CustomStringConvertible {
        let status: OSStatus

        var description: String {
            "Authorization Services error \(status)"
        }
    }

    private init(reference: AuthorizationRef, externalForm: Data) {
        self.reference = reference
        self.externalForm = externalForm
    }

    deinit {
        AuthorizationFree(reference, [.destroyRights])
    }

    static func create() throws -> AdminAuthorization {
        var created: AuthorizationRef?
        var status = AuthorizationCreate(nil, nil, [], &created)
        guard status == errAuthorizationSuccess, let reference = created else {
            throw Failure(status: status)
        }
        var form = AuthorizationExternalForm()
        status = AuthorizationMakeExternalForm(reference, &form)
        guard status == errAuthorizationSuccess else {
            AuthorizationFree(reference, [])
            throw Failure(status: status)
        }
        let data = withUnsafeBytes(of: &form) { Data($0) }
        return AdminAuthorization(reference: reference, externalForm: data)
    }
}
