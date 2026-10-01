// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SnakeStickCore

/// Runs one write as root (stage 20, decision 1): the `snakestick` tool in the app bundle,
/// started through `osascript`'s `do shell script … with administrator privileges`, which asks
/// for an administrator every time. The tool reports over a Unix domain socket the app listens on
/// (`IPC`). Events arrive through ``onEvent``; a job that ends without a final event through
/// ``onEnded``.
///
/// The tool is run where it is in the bundle, without copying or checking its signature first;
/// a process running as the same user could replace it (decision 2).
@MainActor
final class InstallerRunner {
    enum EndReason: Equatable {
        /// The administrator dialog was dismissed (AppleScript error -128), or the job was
        /// cancelled before the tool connected.
        case authCancelled
        /// The tool connected but stopped without a final event.
        case lost(String)
        /// osascript failed before the tool connected.
        case osascriptFailed(String)
    }

    struct StartError: Error, CustomStringConvertible {
        var description: String
    }

    var onEvent: ((InstallerEvent) -> Void)?
    /// Called at most once per job, and never for a job that sent `finished` or `failed`.
    var onEnded: ((EndReason) -> Void)?

    private var job: Job?

    /// `Contents/Helpers/snakestick`. Not `Contents/MacOS`: on a case-insensitive volume that
    /// is the app's own executable, `SnakeStick` (F3).
    static var toolURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/snakestick")
    }

    /// The values come in as arguments, not through the script source, and `quoted form of`
    /// quotes them for the shell (P2). The request itself goes over the socket (P1).
    static let script = """
        on run argv
            set cli to item 1 of argv
            set sock to item 2 of argv
            set promptText to item 3 of argv
            do shell script (quoted form of cli) & " ipc --socket " & (quoted form of sock) ¬
                with prompt promptText with administrator privileges
        end run
        """

    /// Starts the job. The administrator dialog appears now; events follow once it is accepted.
    func start(_ request: InstallerRequest, prompt: String) throws {
        guard job == nil else {
            throw StartError(description: "a write is already running")
        }
        let listener = try IPC.Listener()
        // osascript's stderr carries AppleScript errors, and the tool's stderr when it exits
        // with a failure. A file rather than a pipe: nothing can block on it, and it can be read
        // as soon as osascript has exited.
        let errorLog = FileManager.default.temporaryDirectory.appendingPathComponent("snakestick-osascript-\(UUID().uuidString).log")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", Self.script, "--", Self.toolURL.path, listener.socketPath, prompt]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        do {
            guard FileManager.default.createFile(atPath: errorLog.path, contents: nil) else {
                throw StartError(description: "\(errorLog.path) cannot be created")
            }
            process.standardError = try FileHandle(forWritingTo: errorLog)
        } catch {
            listener.close()
            throw error
        }

        let job = Job(request: request, listener: listener, process: process, errorLog: errorLog)
        Self.watchExit(of: job) { [weak self] status, output in
            self?.osascriptEnded(job, status: status, output: output)
        }
        do {
            try process.run()
        } catch {
            listener.close()
            try? FileManager.default.removeItem(at: errorLog)
            throw error
        }
        self.job = job
        Self.acceptConnection(for: job) { [weak self] connection in
            self?.accepted(job, connection: connection)
        }
    }

    /// Asks the tool to stop. Before it has connected, osascript (and with it the administrator
    /// dialog) is terminated instead. Does nothing once the job has ended.
    func cancel() {
        guard let job, !job.terminated else {
            return
        }
        if let connection = job.connection {
            // SO_NOSIGPIPE: a tool that has just exited makes this fail, not end the app.
            try? connection.send(IPC.AppMessage.cancel)
        } else {
            job.cancelRequested = true
            job.process.terminate()
        }
    }

    // MARK: - Job steps (main actor)

    private func accepted(_ job: Job, connection: IPC.Connection?) {
        guard let connection else {
            // osascript ended first; osascriptEnded reports why.
            return
        }
        guard self.job === job, !job.cancelRequested else {
            // The tool gets EOF before a request and exits without doing anything.
            connection.shutdown()
            return
        }
        job.connection = connection
        do {
            try connection.send(IPC.AppMessage.start(job.request))
        } catch {
            end(job, .lost("the request could not be sent: \(error)"))
            return
        }
        let events = Self.readEvents(from: connection)
        Task { [weak self] in
            for await event in events {
                self?.received(event, in: job)
            }
            self?.connectionEnded(job)
        }
    }

    private func received(_ event: InstallerEvent, in job: Job) {
        guard self.job === job else {
            return
        }
        switch event {
        case .finished, .failed:
            // The last message; the tool closes the connection and exits after it.
            job.terminated = true
            self.job = nil
            job.connection?.shutdown()
            job.listener.close()
        case .progress, .log:
            break
        }
        onEvent?(event)
    }

    private func connectionEnded(_ job: Job) {
        guard self.job === job, !job.terminated else {
            return
        }
        let detail = job.osascriptOutput.map { "the tool stopped without a result: \($0)" } ?? "the tool stopped without a result"
        end(job, .lost(detail))
    }

    private func osascriptEnded(_ job: Job, status: Int32, output: String) {
        let detail = output.isEmpty ? "osascript exited with status \(status)" : output
        if status != 0 {
            job.osascriptOutput = detail
        }
        guard self.job === job, !job.terminated else {
            return
        }
        guard job.connection == nil else {
            // The connection's end decides: the last events may still be on their way.
            return
        }
        if job.cancelRequested || output.contains("(-128)") {
            end(job, .authCancelled)
        } else {
            end(job, .osascriptFailed(detail))
        }
    }

    private func end(_ job: Job, _ reason: EndReason) {
        if self.job === job {
            self.job = nil
        }
        job.connection?.shutdown()
        job.listener.close()
        onEnded?(reason)
    }

    // MARK: - Background work
    //
    // These run on their own threads. They are nonisolated and hand results to the main actor
    // explicitly: a main-actor closure called on another thread fails the runtime isolation
    // check and ends the process (F11).

    /// Waits for `job`'s connection, or for osascript to end without one.
    private nonisolated static func acceptConnection(
        for job: Job, then deliver: @escaping @MainActor @Sendable (IPC.Connection?) -> Void
    ) {
        let thread = Thread {
            let connection = try? job.listener.accept { job.osascriptExited }
            job.listener.close()
            Task { @MainActor in deliver(connection) }
        }
        thread.name = "SnakeStick accept"
        thread.start()
    }

    /// The tool's events in order, until the connection ends.
    private nonisolated static func readEvents(from connection: IPC.Connection) -> AsyncStream<InstallerEvent> {
        let (stream, continuation) = AsyncStream<InstallerEvent>.makeStream()
        let thread = Thread {
            while true {
                do {
                    guard let message = try connection.receive(IPC.ToolMessage.self) else {
                        break
                    }
                    continuation.yield(message.event)
                } catch is DecodingError {
                    continue
                } catch {
                    break
                }
            }
            continuation.finish()
        }
        thread.name = "SnakeStick events"
        thread.start()
        return stream
    }

    private nonisolated static func watchExit(
        of job: Job, then deliver: @escaping @MainActor @Sendable (Int32, String) -> Void
    ) {
        job.process.terminationHandler = { process in
            job.osascriptExited = true
            let output = (try? String(contentsOf: job.errorLog, encoding: .utf8)) ?? ""
            try? FileManager.default.removeItem(at: job.errorLog)
            let status = process.terminationStatus
            Task { @MainActor in deliver(status, output.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
    }
}

/// One write. `osascriptExited` is read by the accept thread; everything else is only touched
/// on the main actor.
private nonisolated final class Job: @unchecked Sendable {
    // Unchecked: see above; `osascriptExited` is guarded by `lock`.
    let request: InstallerRequest
    let listener: IPC.Listener
    let process: Process
    let errorLog: URL

    var connection: IPC.Connection?
    var terminated = false
    var cancelRequested = false
    /// What osascript printed when it failed (AppleScript errors, the tool's stderr).
    var osascriptOutput: String?

    private let lock = NSLock()
    private var exited = false

    var osascriptExited: Bool {
        get { lock.withLock { exited } }
        set { lock.withLock { exited = newValue } }
    }

    init(request: InstallerRequest, listener: IPC.Listener, process: Process, errorLog: URL) {
        self.request = request
        self.listener = listener
        self.process = process
        self.errorLog = errorLog
    }
}
