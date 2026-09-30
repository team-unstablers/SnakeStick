// SPDX-License-Identifier: GPL-3.0-or-later

// SnakeStickHelper: the root launchd daemon that runs the pipeline for the app (decision 19, §12).
// Registered by the app with SMAppService; launchd starts it on demand through its Mach service.

import Foundation
import os
import SnakeStickCore
import XPC

let logger = Logger(subsystem: HelperConstants.helperBundleIdentifier, category: "helper")
logger.log("starting, version \(HelperService.version.description, privacy: .public), uid \(getuid())")

HelperAuthorization.registerRightIfNeeded { logger.log("\($0, privacy: .public)") }

let service = HelperService(logger: logger)

// Only the app, signed by the same team as this daemon, may connect (P9, §12).
let listener: XPCListener
do {
    listener = try XPCListener(
        service: HelperConstants.machServiceName,
        requirement: .isFromSameTeam(andMatchesSigningIdentifier: HelperConstants.appBundleIdentifier)
    ) { request in
        request.accept { session in
            service.sessionStarted()
            return HelperSessionHandler(session: session, service: service)
        }
    }
} catch {
    logger.error("cannot listen on \(HelperConstants.machServiceName, privacy: .public): \(String(describing: error), privacy: .public)")
    exit(EXIT_FAILURE)
}

// Exit after five idle minutes; launchd starts the daemon again on the next connection.
//
// The handler must run on the main queue: top-level code in main.swift is main-actor isolated in
// Swift 6, so the closure is too, and on any other queue the runtime's isolation check traps
// (EXC_BREAKPOINT in _swift_task_checkIsolatedSwift). That killed the daemon a minute after every
// start, in the middle of a write (2026-09-30). dispatchMain() below services the main queue.
let idleTimer = DispatchSource.makeTimerSource(queue: .main)
idleTimer.schedule(deadline: .now() + 60, repeating: 60)
idleTimer.setEventHandler {
    if service.idleSeconds >= 300 {
        logger.log("idle for five minutes; exiting")
        exit(EXIT_SUCCESS)
    }
}
idleTimer.resume()

withExtendedLifetime(listener) {
    dispatchMain()
}
