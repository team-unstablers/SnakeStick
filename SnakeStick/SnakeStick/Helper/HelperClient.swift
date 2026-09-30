// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import ServiceManagement
import SnakeStickCore
import XPC

/// The app's connection to the root helper daemon (§12, P18): registration with SMAppService,
/// the XPC session, and the requests of `code#xpc`. Events of a running job arrive through
/// ``onEvent``; a lost connection through ``onDisconnect``.
@MainActor
final class HelperClient {
    enum Registration: Equatable {
        case enabled
        /// The user has to allow the daemon in System Settings > General > Login Items.
        case requiresApproval
        case failed(String)
    }

    enum ClientError: Error, CustomStringConvertible {
        case unexpectedReply(String)
        case versionMismatch(helper: HelperVersion, app: HelperVersion)

        var description: String {
            switch self {
            case .unexpectedReply(let reply): "unexpected reply from the helper: \(reply)"
            case .versionMismatch(let helper, let app): "the helper is version \(helper), the app \(app)"
            }
        }
    }

    var onEvent: ((InstallerEvent) -> Void)?
    var onDisconnect: ((String) -> Void)?

    private let service = SMAppService.daemon(plistName: HelperConstants.launchdPlistName)
    private var session: XPCSession?

    /// The version this app expects the daemon to report.
    static let appVersion = HelperVersion(
        marketing: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
        build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    )

    /// Registers the daemon if it is not yet, and reports whether it can be used.
    func ensureRegistered() -> Registration {
        switch service.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            do {
                try service.register()
            } catch {
                if service.status == .requiresApproval {
                    return .requiresApproval
                }
                return .failed(error.localizedDescription)
            }
            return service.status == .enabled ? .enabled : (service.status == .requiresApproval ? .requiresApproval : .failed("status \(service.status.rawValue)"))
        @unknown default:
            return .failed("status \(service.status.rawValue)")
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Unregisters and registers again, so that launchd starts the daemon binary in this app
    /// (after an update left an older daemon running).
    func reregister() async -> Registration {
        session?.cancel(reason: "re-registering")
        session = nil
        try? await service.unregister()
        return ensureRegistered()
    }

    /// Asks the daemon for its version and compares it with the app's.
    func checkVersion() async throws {
        let reply = try await send(.version)
        guard case .version(let version) = reply else {
            throw ClientError.unexpectedReply("\(reply)")
        }
        guard version == Self.appVersion else {
            throw ClientError.versionMismatch(helper: version, app: Self.appVersion)
        }
    }

    /// Starts a job. `.accepted` or `.rejected(reason:)`.
    func start(_ request: InstallerRequest, authorization: AdminAuthorization) async throws -> HelperReply {
        let reply = try await send(.start(request, authorization: authorization.externalForm))
        // `authorization` stays alive until the daemon has answered (C25).
        withExtendedLifetime(authorization) {}
        return reply
    }

    func cancel() async throws {
        _ = try await send(.cancel)
    }

    // MARK: - Session

    private func connect() throws -> XPCSession {
        if let session {
            return session
        }
        // Only the daemon signed by the same team, with its own identifier, is accepted.
        let session = try XPCSession(
            machService: HelperConstants.machServiceName,
            requirement: .isFromSameTeam(andMatchesSigningIdentifier: HelperConstants.helperBundleIdentifier),
            incomingMessageHandler: { [weak self] (message: HelperReply) -> (any Encodable)? in
                Task { @MainActor in self?.receive(message) }
                return nil
            },
            cancellationHandler: { [weak self] error in
                Task { @MainActor in self?.sessionEnded(error) }
            }
        )
        self.session = session
        return session
    }

    private func send(_ request: HelperRequest) async throws -> HelperReply {
        let session = try connect()
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try session.send(request) { (result: Result<HelperReply, any Error>) in
                    continuation.resume(with: result)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func receive(_ message: HelperReply) {
        if case .event(let event) = message {
            onEvent?(event)
        }
    }

    private func sessionEnded(_ error: XPCRichError) {
        session = nil
        onDisconnect?(String(describing: error))
    }
}
