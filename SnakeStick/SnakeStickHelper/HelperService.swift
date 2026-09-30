// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import os
import SnakeStickCore
import XPC

/// The daemon's state: at most one job, and when it was last busy (for the idle exit).
final class HelperService: @unchecked Sendable {
    // Unchecked: `job`, `jobSession` and `lastActivity` are only touched with `lock` held.
    private let lock = NSLock()
    private var job: Task<Void, Never>?
    private var jobSession: XPCSession?
    private var lastActivity = Date()
    let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    /// The version compiled into this executable (its embedded Info.plist), not the app's.
    ///
    /// The path comes from dyld: under launchd's `BundleProgram`, `argv[0]` did not lead to the
    /// file (the version read as "?"), and `Bundle.main` is the enclosing app, not this tool.
    static let version: HelperVersion = {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size) + 1)
        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
            return HelperVersion(marketing: "?", build: "?")
        }
        let executable = URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath()
        let info = CFBundleCopyInfoDictionaryForURL(executable as CFURL) as? [String: Any] ?? [:]
        return HelperVersion(
            marketing: info["CFBundleShortVersionString"] as? String ?? "?",
            build: info["CFBundleVersion"] as? String ?? "?"
        )
    }()

    private var sessionCount = 0

    /// Counts a connection from the app.
    func sessionStarted() {
        lock.withLock { sessionCount += 1 }
    }

    /// Seconds since the last job ended or request arrived; 0 while a job runs.
    var idleSeconds: TimeInterval {
        lock.withLock { job == nil ? Date().timeIntervalSince(lastActivity) : 0 }
    }

    func handle(_ request: HelperRequest, from session: XPCSession) -> HelperReply {
        lock.withLock { lastActivity = Date() }
        switch request {
        case .version:
            return .version(Self.version)
        case .cancel:
            let running = lock.withLock { job }
            running?.cancel()
            logger.log("cancel requested; \(running == nil ? "no job" : "cancelling the job", privacy: .public)")
            return .accepted
        case .start(let installerRequest, let authorization):
            return start(installerRequest, authorization: authorization, session: session)
        }
    }

    /// The app went away. A job it started is cancelled rather than left writing with nobody
    /// watching. Without connections and a job, the daemon exits, so that the next connection
    /// gets the executable currently in the app (after an update, or a rebuild while developing).
    func sessionEnded(_ session: XPCSession) {
        let (running, idle): (Task<Void, Never>?, Bool) = lock.withLock {
            sessionCount -= 1
            return (jobSession === session ? job : nil, sessionCount <= 0 && job == nil)
        }
        if let running {
            logger.log("the app disconnected; cancelling its job")
            running.cancel()
        }
        if idle {
            exitSoon()
        }
    }

    private func exitSoon() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [self] in
            let stillIdle = lock.withLock { sessionCount <= 0 && job == nil }
            if stillIdle {
                logger.log("no connections and no job; exiting")
                exit(EXIT_SUCCESS)
            }
        }
    }

    private func start(_ request: InstallerRequest, authorization: Data, session: XPCSession) -> HelperReply {
        guard HelperAuthorization.verify(authorization) else {
            logger.error("start rejected: authorization failed")
            return .rejected(reason: "The administrator authorization is not valid.")
        }
        // The app is not trusted with the target (C21): only whole disks, checked against P8 here.
        guard case .device(let bsdName) = request.target else {
            return .rejected(reason: "The helper only writes to disks.")
        }
        guard DiskCandidate.isWholeDiskName(bsdName) else {
            return .rejected(reason: "\(bsdName) is not a whole-disk name.")
        }
        do {
            guard let disk = try listWholeDisks().first(where: { $0.bsdName == bsdName }) else {
                return .rejected(reason: "\(bsdName) was not found.")
            }
            guard disk.isEligible else {
                return .rejected(reason: "\(bsdName) cannot be written: \(disk.ineligibleReason ?? "not eligible").")
            }
        } catch {
            return .rejected(reason: "The disks cannot be listed: \(error)")
        }

        return lock.withLock {
            guard job == nil else {
                return .rejected(reason: "Another write is in progress.")
            }
            logger.log("starting a job for \(bsdName, privacy: .public) from \(request.isoPath, privacy: .public)")
            jobSession = session
            job = Task.detached { [self] in
                do {
                    _ = try await runInstaller(request) { event in
                        try? session.send(HelperReply.event(event))
                    }
                    logger.log("job finished")
                } catch {
                    logger.log("job ended: \(String(describing: error), privacy: .public)")
                }
                let idle = lock.withLock {
                    job = nil
                    jobSession = nil
                    lastActivity = Date()
                    return sessionCount <= 0
                }
                if idle {
                    exitSoon()
                }
            }
            return .accepted
        }
    }
}

/// One connection from the app.
struct HelperSessionHandler: XPCPeerHandler {
    let session: XPCSession
    let service: HelperService

    func handleIncomingRequest(_ request: HelperRequest) -> (any Encodable)? {
        service.handle(request, from: session)
    }

    func handleCancellation(error: XPCRichError) {
        service.sessionEnded(session)
    }
}
