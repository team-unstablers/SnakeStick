// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Names shared by the app and its root helper daemon (decision 19, P9, P10, P18).
public enum HelperConstants {
    /// The launchd Mach service the daemon listens on.
    public static let machServiceName = "pl.unstabler.aislop.SnakeStick.helper"
    /// `Contents/Library/LaunchDaemons/<this>` in the app bundle, for `SMAppService.daemon(plistName:)`.
    public static let launchdPlistName = "pl.unstabler.aislop.SnakeStick.helper.plist"
    /// The only client the daemon accepts (together with the daemon's own Team ID).
    public static let appBundleIdentifier = "pl.unstabler.aislop.SnakeStick"
    /// The daemon's code signing identifier; the app accepts only this peer.
    public static let helperBundleIdentifier = "pl.unstabler.aislop.SnakeStick.helper"
    /// The Authorization Services right checked for every write.
    public static let authorizationRight = "pl.unstabler.aislop.SnakeStick.write"
    /// Bumped whenever ``HelperRequest`` or ``HelperReply`` change shape.
    public static let protocolVersion = 2
    /// The `rejected` reason when the user dismissed the authentication dialog.
    public static let authorizationCancelled = "authorization cancelled"
}

/// App → daemon. The daemon runs one job at a time (`code#xpc`).
public enum HelperRequest: Sendable, Codable, Equatable {
    /// Starts the pipeline for a `.device` target. `authorization` is an
    /// `AuthorizationExternalForm` (32 bytes) of an authorization the app created without asking
    /// for anything; the daemon acquires ``HelperConstants/authorizationRight`` through it, which
    /// shows the authentication dialog in the user's session with `prompt` (localized by the app).
    ///
    /// Not as P10 planned: the app asking and the daemon only checking does not work, because
    /// `authenticate-admin` credentials have a timeout of 0 and cannot be reused (2026-09-30).
    case start(InstallerRequest, authorization: Data, prompt: String)
    case cancel
    case version
}

/// Daemon → app: replies to ``HelperRequest``, and the job's events as separate messages.
public enum HelperReply: Sendable, Codable, Equatable {
    case accepted
    /// Authorization failed, a job is running, the versions differ, or the target is not
    /// eligible (the daemon checks P8 again, C21).
    case rejected(reason: String)
    case event(InstallerEvent)
    case version(HelperVersion)
}

public struct HelperVersion: Sendable, Codable, Equatable, CustomStringConvertible {
    /// `CFBundleShortVersionString` compiled into the daemon.
    public var marketing: String
    /// `CFBundleVersion` compiled into the daemon.
    public var build: String
    public var protocolVersion: Int

    public init(marketing: String, build: String, protocolVersion: Int = HelperConstants.protocolVersion) {
        self.marketing = marketing
        self.build = build
        self.protocolVersion = protocolVersion
    }

    public var description: String {
        "\(marketing) (\(build)), protocol \(protocolVersion)"
    }
}
