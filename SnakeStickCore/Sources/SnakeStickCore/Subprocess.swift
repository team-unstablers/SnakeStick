// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Runs an external tool and collects its output. Used for `hdiutil`, `diskutil` and
/// `newfs_msdos`; every run is logged with its exit status (P17).
struct Subprocess {
    struct Output {
        var status: Int32
        var stdout: Data
        var stderr: Data

        var stdoutText: String {
            String(decoding: stdout, as: UTF8.self)
        }

        var stderrText: String {
            String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    let log: @Sendable (String) -> Void

    /// Runs `executable` with `arguments` and waits for it. Never throws for a non-zero exit
    /// status; only when the process cannot be started.
    func run(_ executable: String, _ arguments: [String]) throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let commandLine = ([executable] + arguments).map(Self.quoted).joined(separator: " ")
        try process.run()
        // Drain both pipes concurrently so that a chatty tool cannot block on a full pipe.
        let stderrData = LockedData()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            stderrData.set(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        let output = Output(status: process.terminationStatus, stdout: stdoutData, stderr: stderrData.get())
        var line = "$ \(commandLine) -> \(output.status)"
        if output.status != 0, !output.stderrText.isEmpty {
            line += ": \(output.stderrText)"
        }
        log(line)
        return output
    }

    private static func quoted(_ argument: String) -> String {
        guard argument.isEmpty || argument.contains(where: { " \"'$\\".contains($0) }) else {
            return argument
        }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ value: Data) {
        lock.withLock { data = value }
    }

    func get() -> Data {
        lock.withLock { data }
    }
}
