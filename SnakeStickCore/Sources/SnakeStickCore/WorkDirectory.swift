// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import os

/// `/tmp/snakestick-<uid>-<UUID>/` with `iso/`, `efi/` and `wim/` created on demand (P4).
/// Removed last during cleanup (§11).
final class WorkDirectory: Sendable {
    let url: URL
    private let log: @Sendable (String) -> Void

    init(log: @escaping @Sendable (String) -> Void) throws {
        url = URL(fileURLWithPath: "/tmp/snakestick-\(getuid())-\(UUID().uuidString)", isDirectory: true)
        self.log = log
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }

    func subdirectory(_ name: String) throws -> URL {
        let child = url.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        return child
    }

    /// Removes the directory. Anything still mounted below it is left alone (and logged),
    /// because removing a mount point's contents would delete files on that volume.
    func remove() {
        let mounted = Self.mountPoints().filter { $0.hasPrefix(url.path + "/") || $0 == url.path }
        guard mounted.isEmpty else {
            log("cleanup: not removing \(url.path); still mounted: \(mounted.joined(separator: ", "))")
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            log("cleanup: removing \(url.path) failed: \(error)")
        }
    }

    static func mountPoints() -> [String] {
        var buffer: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&buffer, MNT_NOWAIT)
        guard count > 0, let buffer else {
            return []
        }
        return (0 ..< Int(count)).map { index in
            withUnsafeBytes(of: buffer[index].f_mntonname) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        }
    }
}

/// Runs blocking work (hdiutil, libntfs-3g, wimlib) off the Swift concurrency pool.
enum Blocking {
    static func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let thread = Thread {
                continuation.resume(with: Result { try body() })
            }
            thread.name = "SnakeStickCore"
            thread.stackSize = 8 << 20
            thread.start()
        }
    }
}

/// A flag set when the task running the pipeline is cancelled, checked by the blocking code.
final class CancellationFlag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    func cancel() {
        state.withLock { $0 = true }
    }

    var isCancelled: Bool {
        state.withLock { $0 }
    }

    func check() throws {
        if isCancelled {
            throw CancellationError()
        }
    }
}

/// NTFS parameters shared by the size estimate and the format (C24).
enum NTFSLayout {
    static let clusterSize = 4096
}
