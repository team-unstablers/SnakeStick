// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SnakeStickCore

/// Progress and log output on stderr. On a terminal the progress is one line rewritten in place;
/// otherwise each step is printed once. Called from the pipeline's thread.
final class Console: @unchecked Sendable {
    // Unchecked: every mutable member is only touched with `lock` held.
    private let lock = NSLock()
    private let verbose: Bool
    private let interactive = isatty(STDERR_FILENO) != 0
    private var lineIsOpen = false
    private var lastPhase: Phase?

    init(verbose: Bool) {
        self.verbose = verbose
    }

    static func error(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    func handle(_ event: InstallerEvent) {
        lock.withLock {
            switch event {
            case .progress(let progress):
                show(progress)
            case .log(let line):
                if verbose {
                    clearLine()
                    Self.error(line)
                }
            case .finished, .failed:
                break
            }
        }
    }

    func note(_ text: String) {
        lock.withLock {
            clearLine()
            Self.error(text)
        }
    }

    func finishLine() {
        lock.withLock {
            if lineIsOpen {
                FileHandle.standardError.write(Data("\n".utf8))
                lineIsOpen = false
            }
        }
    }

    private func show(_ progress: InstallerProgress) {
        let head = "[\(progress.phase.rawValue)/8] \(progress.phase.title)"
        guard interactive else {
            if lastPhase != progress.phase {
                lastPhase = progress.phase
                Self.error(head)
            }
            return
        }
        var line = "\(head)  \(Int((progress.fraction * 100).rounded(.down)))%"
        if let remaining = progress.estimatedRemaining {
            line += "  about \(max(1, Int((remaining / 60).rounded(.up)))) min left"
        }
        if let detail = progress.detail, !detail.isEmpty {
            line += "  \(detail)"
        }
        let width = Self.terminalWidth()
        if line.count > width - 1 {
            line = String(line.prefix(width - 2)) + "…"
        }
        FileHandle.standardError.write(Data(("\r\u{1B}[K" + line).utf8))
        lineIsOpen = true
    }

    private func clearLine() {
        if lineIsOpen {
            FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
            lineIsOpen = false
        }
    }

    private static func terminalWidth() -> Int {
        var size = winsize()
        guard ioctl(STDERR_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 20 else {
            return 100
        }
        return Int(size.ws_col)
    }
}
