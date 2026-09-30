// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Owns the model and routes closing the main window and quitting through 05 while a job runs
/// (`InstallerViewModel.allowsExit`).
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = InstallerViewModel()
    private var closeGuard: WindowCloseGuard?

    override init() {
        super.init()
        model.performExit = { [weak self] exit in
            switch exit {
            case .closeWindow:
                self?.closeGuard?.window?.performClose(nil)
            case .quit:
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.allowsExit(.quit) {
            return .terminateNow
        }
        // 05 is a sheet on the main window. `performExit` quits again once the job has ended.
        if let window = closeGuard?.window {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
        return .terminateCancel
    }

    /// Puts the guard in front of the main window's delegate. Called on every update of the
    /// window's content, since a new window, or SwiftUI setting its delegate again, drops it.
    func guardMainWindow(_ window: NSWindow) {
        if let closeGuard, window.delegate === closeGuard {
            return
        }
        closeGuard = WindowCloseGuard(window: window) { [weak self] in
            self?.model.allowsExit(.closeWindow) ?? true
        }
    }
}

/// Stands in as a window's delegate so that its close button and ⌘W can be refused. SwiftUI has no
/// hook for refusing a close (`windowDismissBehavior` only disables the button). Everything else
/// goes to SwiftUI's own delegate.
final class WindowCloseGuard: NSObject, NSWindowDelegate {
    private(set) weak var window: NSWindow?
    /// SwiftUI's delegate. The forwarding overrides read it; the runtime does not promise to call
    /// them on the main actor.
    nonisolated(unsafe) private weak var original: (any NSWindowDelegate)?
    private let allowsClose: () -> Bool

    /// `window.delegate` is weak: the caller keeps the guard.
    init(window: NSWindow, allowsClose: @escaping () -> Bool) {
        self.window = window
        self.original = window.delegate
        self.allowsClose = allowsClose
        super.init()
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard allowsClose() else {
            return false
        }
        return original?.windowShouldClose?(sender) ?? true
    }

    override nonisolated func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || original?.responds(to: aSelector) == true
    }

    override nonisolated func forwardingTarget(for aSelector: Selector!) -> Any? {
        original
    }
}

/// Hands the window its view is in to `found`, when the view joins it and on every update.
struct WindowAccessor: NSViewRepresentable {
    let found: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        WindowReportingView(found: found)
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? WindowReportingView)?.found = found
        if let window = view.window {
            found(window)
        }
    }
}

private final class WindowReportingView: NSView {
    var found: (NSWindow) -> Void

    init(found: @escaping (NSWindow) -> Void) {
        self.found = found
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            found(window)
        }
    }
}
