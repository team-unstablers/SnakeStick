// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SnakeStickCore

/// `snakestick ipc --socket PATH`: one job for the app (stage 20, `IPC`).
///
/// The app runs this as root through `do shell script … with administrator privileges`. The
/// request arrives as the first message on the socket, not in argv (P1). Events go back over the
/// socket; people-readable text only to stderr.
extension SnakeStickCLI {
    static func ipc(socketPath: String) async -> ExitCode {
        // `do shell script` keeps the tool's stdout in memory until it exits, so nothing is
        // written there. Pointing it at stderr also catches what libntfs-3g or wimlib print.
        fflush(stdout)
        dup2(STDERR_FILENO, STDOUT_FILENO)
        // The socket has SO_NOSIGPIPE; this covers any other descriptor. A write to a closed peer
        // must fail, not kill the tool before the pipeline has cleaned up.
        signal(SIGPIPE, SIG_IGN)

        let connection: IPC.Connection
        do {
            connection = try IPC.Connection.connect(to: socketPath)
        } catch {
            Console.error("snakestick: cannot connect to the app: \(error)")
            return .io
        }
        // Everything is with the kernel once send returns; the app reads it, then EOF.
        defer { connection.finishSending() }

        let sink = EventSink(connection: connection)
        let request: InstallerRequest
        do {
            guard let first = try connection.receive(IPC.AppMessage.self) else {
                Console.error("snakestick: the app closed the connection before sending a request")
                return .usage
            }
            guard case .start(let started) = first else {
                return sink.reject("The first message was not a start request.")
            }
            request = started
        } catch {
            return sink.reject("The first message could not be read: \(error)")
        }

        let job = Task {
            await runJob(request, sink: sink)
        }
        // A cancel message, or the app's end closing (quit, crash), cancels the job (P3). The
        // closure is @Sendable so that it is not main-actor isolated: it runs on its own thread,
        // and an isolated closure there would fail the runtime isolation check (F11).
        let reader = Thread { @Sendable in
            while true {
                let message: IPC.AppMessage?
                do {
                    message = try connection.receive(IPC.AppMessage.self)
                } catch is DecodingError {
                    continue
                } catch {
                    message = nil
                }
                // Another start is ignored; nil (EOF, a read error) and cancel end the job.
                guard case .start = message else {
                    break
                }
            }
            job.cancel()
        }
        reader.name = "snakestick ipc reader"
        reader.start()
        return await job.value
    }

    private static func runJob(_ request: InstallerRequest, sink: EventSink) async -> ExitCode {
        // The pipeline checks root and the disk again itself; checking here first gives the
        // refusals, messages and exit codes of make (P8). Image targets need neither.
        if case .device(let disk) = request.target {
            let refusal: InstallerError?
            switch await checkDevice(isoPath: request.isoPath, disk: disk) {
            case .success:
                refusal = nil
            case .failure(.rootRequired):
                refusal = InstallerError(phase: .prepareTarget, kind: .rootRequired, message: "Writing to a disk needs root privileges (root required).")
            case .failure(.rejected(let kind, let message)):
                refusal = InstallerError(phase: .prepareTarget, kind: kind, message: message, path: "/dev/\(disk)")
            case .failure(.error(let error)):
                refusal = installerError(error)
            }
            if let refusal {
                sink.send(.failed(refusal))
                // The exit codes of make: 77 without root, 69 for a disk that is gone,
                // not eligible or too small.
                return report(refusal)
            }
        }

        switch await runPipeline(request, events: { sink.send($0) }) {
        case .finished:
            return .success
        case .cancelled:
            Console.error("snakestick: cancelled. The target was left as it is and cannot be booted; write it again to use it.")
            return .interrupted
        case .failed(let error):
            // The pipeline sends `failed` itself; this covers an error from outside it.
            if !sink.terminated {
                sink.send(.failed(installerError(error)))
            }
            return report(error)
        }
    }

    private static func installerError(_ error: any Error) -> InstallerError {
        error as? InstallerError ?? InstallerError(phase: .openISO, kind: .other, message: "\(error)")
    }
}

/// Sends events to the app and remembers whether the last one has gone out. Called from the
/// pipeline's thread and from `ipc`. Once a send fails (the app is gone), later events are
/// dropped; the reader sees the same EOF and cancels the job.
final class EventSink: @unchecked Sendable {
    // Unchecked: `terminated` and `broken` are only touched with `lock` held.
    private let connection: IPC.Connection
    private let lock = NSLock()
    private var broken = false
    private(set) var terminated: Bool {
        get { lock.withLock { _terminated } }
        set { lock.withLock { _terminated = newValue } }
    }
    private var _terminated = false

    init(connection: IPC.Connection) {
        self.connection = connection
    }

    func send(_ event: InstallerEvent) {
        let skip: Bool = lock.withLock {
            switch event {
            case .finished, .failed: _terminated = true
            default: break
            }
            return broken
        }
        guard !skip else {
            return
        }
        do {
            try connection.send(IPC.ToolMessage(event: event))
        } catch {
            lock.withLock { broken = true }
            Console.error("snakestick: the app is gone (\(error)); the job is cancelled")
        }
    }

    /// Answers a request that cannot be run: a `failed` event of kind `.usage`, nothing opened.
    func reject(_ message: String) -> ExitCode {
        let error = InstallerError(phase: .openISO, kind: .usage, message: message)
        send(.failed(error))
        Console.error("snakestick: \(message)")
        return .usage
    }
}
