// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import snakestick
@testable import SnakeStickCore

/// §1: the messages and their lines.
struct IPCMessageTests {
    @Test func appMessagesRoundTrip() throws {
        let messages: [IPC.AppMessage] = [
            .start(InstallerRequest(
                isoPath: "/Users/a b/윈도 'x'.iso",
                target: .image(path: "/tmp/out.img", size: 8_000_000_000),
                options: .init(volumeLabel: "WIN", verifyAfterWrite: false, useCA2023Bootloaders: true)
            )),
            .start(InstallerRequest(isoPath: "/tmp/w.iso", target: .device(bsdName: "disk4"))),
            .cancel,
        ]
        for message in messages {
            let line = try IPC.line(message)
            #expect(try IPC.decode(IPC.AppMessage.self, line: line) == message)
        }
        #expect(String(decoding: try IPC.line(IPC.AppMessage.cancel), as: UTF8.self) == "{\"cancel\":{}}\n")
        #expect(String(decoding: try IPC.line(messages[1]), as: UTF8.self).hasPrefix("{\"start\":{"))
    }

    @Test func toolMessagesRoundTrip() throws {
        let events: [InstallerEvent] = [
            .progress(.init(phase: .copyFiles, fraction: 0.5, detail: "/sources/설치.wim", estimatedRemaining: 12)),
            .log("first line\nsecond line\r\n\tthird \u{1B}[K"),
            .finished(.init(elapsed: 3.5, verified: true)),
            .failed(.init(phase: .verify, kind: .verificationFailed, message: "x", targetModified: true, path: "/a", errno: EPERM)),
        ]
        for event in events {
            let line = try IPC.line(IPC.ToolMessage(event: event))
            #expect(try IPC.decode(IPC.ToolMessage.self, line: line).event == event)
            #expect(String(decoding: try IPC.line(IPC.ToolMessage(event: event)), as: UTF8.self).hasPrefix("{\"event\":{"))
        }
    }

    /// A log line with newlines in it is still one line on the wire.
    @Test func oneLinePerMessage() throws {
        let line = try IPC.line(IPC.ToolMessage(event: .log("a\nb\nc\u{2028}d\u{0085}e")))
        #expect(line.last == UInt8(ascii: "\n"))
        #expect(line.filter { $0 == UInt8(ascii: "\n") }.count == 1)
        #expect(line.filter { $0 == UInt8(ascii: "\r") }.isEmpty)
    }

    @Test(arguments: ["", "{}", "{\"stop\":{}}", "not json", "{\"start\":{\"isoPath\":1}}"])
    func malformedAppMessages(text: String) {
        #expect(throws: (any Error).self) { try IPC.decode(IPC.AppMessage.self, line: Data(text.utf8)) }
    }

    @Test func ipcArguments() throws {
        #expect(try Arguments.parse(["ipc", "--socket", "/tmp/a b/s"]) == .ipc(socket: "/tmp/a b/s"))
        #expect(try Arguments.parse(["ipc", "--socket=/tmp/s"]) == .ipc(socket: "/tmp/s"))
        #expect(!Arguments.usage.contains("ipc"))
    }

    @Test(arguments: [
        ["ipc"], ["ipc", "--socket"], ["ipc", "--socket", "/tmp/s", "extra"], ["ipc", "--yes", "--socket", "/tmp/s"],
        ["ipc", "/tmp/s"], ["make", "--socket", "/tmp/s", "win.iso", "disk4"],
    ])
    func ipcUsageErrors(arguments: [String]) async {
        #expect(throws: UsageError.self) { try Arguments.parse(arguments) }
        #expect(await SnakeStickCLI.run(arguments) == .usage)
    }
}

/// §1: the socket code shared by the app and the tool.
struct IPCSocketTests {
    @Test func listenerDirectoryIsPrivateAndRemoved() throws {
        let parent = try ShortDirectory()
        let listener = try IPC.Listener(parent: parent.url)
        let attributes = try FileManager.default.attributesOfItem(atPath: listener.directory.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect(listener.socketPath.hasPrefix(parent.url.path))
        #expect(FileManager.default.fileExists(atPath: listener.socketPath))
        listener.close()
        listener.close()
        #expect(!FileManager.default.fileExists(atPath: listener.directory.path))
    }

    @Test func tooLongPathIsRefused() throws {
        let parent = try ShortDirectory()
        let deep = parent.url.appendingPathComponent(String(repeating: "d", count: 90))
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        #expect(throws: IPC.SocketError.self) { try IPC.Listener(parent: deep) }
        // Nothing is left behind.
        #expect(try FileManager.default.contentsOfDirectory(atPath: deep.path).isEmpty)
        #expect(throws: IPC.SocketError.self) { try IPC.Connection.connect(to: deep.path + "/" + String(repeating: "s", count: 20)) }
    }

    @Test func acceptStopsWhenAsked() throws {
        let parent = try ShortDirectory()
        let listener = try IPC.Listener(parent: parent.url)
        let start = Date()
        #expect(try listener.accept(pollInterval: 0.05) { Date().timeIntervalSince(start) > 0.3 } == nil)
    }

    @Test func messagesTravelBothWays() throws {
        let parent = try ShortDirectory()
        let listener = try IPC.Listener(parent: parent.url)
        let client = try IPC.Connection.connect(to: listener.socketPath)
        let server = try #require(try listener.accept { false })
        listener.close()

        try server.send(IPC.AppMessage.cancel)
        #expect(try client.receive(IPC.AppMessage.self) == .cancel)
        // More than the socket buffer holds, so the sender blocks until the reader catches up.
        let events = (0 ..< 500).map { InstallerEvent.log("line \($0)\nwith 한글") }
        Thread { @Sendable in
            for event in events {
                try? client.send(IPC.ToolMessage(event: event))
            }
            client.finishSending()
        }.start()
        var received: [InstallerEvent] = []
        while let message = try server.receive(IPC.ToolMessage.self) {
            received.append(message.event)
        }
        #expect(received == events)
    }

    /// Writing to a closed peer throws instead of raising SIGPIPE, which would end this process.
    @Test func sendingToAClosedPeerThrows() throws {
        let parent = try ShortDirectory()
        let listener = try IPC.Listener(parent: parent.url)
        var client: IPC.Connection? = try IPC.Connection.connect(to: listener.socketPath)
        let server = try #require(try listener.accept { false })
        client?.shutdown()
        client = nil
        #expect(try server.receive(IPC.ToolMessage.self) == nil)
        #expect(throws: IPC.SocketError.self) {
            for _ in 0 ..< 100 {
                try server.send(IPC.AppMessage.cancel)
            }
        }
    }
}

/// code#ipc-mode: the built tool, refusing what it must not run. No image is attached.
struct IPCRefusalTests {
    @Test func missingSocket() throws {
        let parent = try ShortDirectory()
        let result = try runProcess(snakestickBinary, ["ipc", "--socket", parent.url.appendingPathComponent("none/s").path])
        #expect(result.status == ExitCode.io.rawValue)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("cannot connect"))
    }

    @Test func firstMessageMustBeStart() throws {
        let run = try IPCRun()
        let connection = try run.accept()
        try connection.send(IPC.AppMessage.cancel)
        let events = try run.events(from: connection)
        let result = try run.wait()
        #expect(result.status == ExitCode.usage.rawValue)
        #expect(result.stdout.isEmpty)
        #expect(events.count == 1)
        guard case .failed(let error) = events.last else {
            Issue.record("no failed event: \(events)")
            return
        }
        #expect(error.kind == .usage)
    }

    @Test func malformedFirstLine() throws {
        let run = try IPCRun()
        let connection = try run.accept()
        try connection.send(["start": "nonsense"])
        let events = try run.events(from: connection)
        #expect(try run.wait().status == ExitCode.usage.rawValue)
        guard case .failed(let error) = events.last else {
            Issue.record("no failed event: \(events)")
            return
        }
        #expect(error.kind == .usage)
    }

    @Test func closedBeforeStart() throws {
        let run = try IPCRun()
        let connection = try run.accept()
        connection.shutdown()
        #expect(try run.wait().status == ExitCode.usage.rawValue)
    }

    /// P8: a disk needs root; without it the request is refused before anything is opened. The
    /// disk name is one that does not exist, and the root check comes before the disk lookup.
    @Test func deviceNeedsRoot() throws {
        try #require(getuid() != 0)
        let run = try IPCRun()
        let connection = try run.accept()
        try connection.send(IPC.AppMessage.start(InstallerRequest(isoPath: "/nonexistent/snakestick.iso", target: .device(bsdName: "disk999"))))
        let events = try run.events(from: connection)
        let result = try run.wait()
        #expect(result.status == ExitCode.noPermission.rawValue)
        #expect(result.stdout.isEmpty)
        #expect(events.count == 1)
        guard case .failed(let error) = events.last else {
            Issue.record("no failed event: \(events)")
            return
        }
        #expect(error.kind == .rootRequired)
    }
}

extension IntegrationTests {
    /// §2: the built tool as the app runs it, on fixture images. Paths with spaces, quotes and
    /// Hangul throughout.
    @Suite struct IPCMode {
        static let extraBytes: UInt64 = 64 << 20

        func request(_ scratch: ScratchDirectory) async throws -> (InstallerRequest, FixtureISO) {
            let fixture = try FixtureISO.make(in: scratch, name: "윈도 설치 'ipc'.iso", ca2023: false)
            let info = try await inspectISO(at: fixture.iso.path)
            let image = scratch.path("이미지 'ipc' 1.img")
            return (InstallerRequest(isoPath: fixture.iso.path, target: .image(path: image, size: info.requiredBytes + Self.extraBytes)), fixture)
        }

        @Test func imageRequestFinishes() async throws {
            let before = try attachedImageCount()
            let scratch = try ScratchDirectory()
            let (request, fixture) = try await request(scratch)
            let run = try IPCRun()
            let connection = try run.accept()
            try connection.send(IPC.AppMessage.start(request))
            let events = try run.events(from: connection)
            let result = try run.wait()
            // stdout goes to stderr in ipc mode; anything here came from the tool or the
            // libraries without being asked for.
            print("snakestick ipc stderr: \(result.stderr.debugDescription)")
            #expect(result.status == 0, "\(result.stderr)")
            #expect(result.reason == .exit)
            #expect(result.stdout.isEmpty, "\(result.stdout)")
            #expect(events.contains { if case .progress = $0 { true } else { false } })
            guard case .finished(let finished) = events.last else {
                Issue.record("the last event is not finished: \(String(describing: events.last))")
                return
            }
            #expect(finished.verified)
            #expect(!events.contains { if case .failed = $0 { true } else { false } })
            guard case .image(let image, _) = request.target else {
                return
            }
            try ImageChecks.check(image: image, fixture: fixture, label: FixtureISO.label, scratch: scratch)
            #expect(try attachedImageCount() == before)
            let work = try #require(workDirectory(in: events))
            #expect(!FileManager.default.fileExists(atPath: work))
        }

        @Test func cancelMessage() async throws {
            let before = try attachedImageCount()
            let scratch = try ScratchDirectory()
            let (request, _) = try await request(scratch)
            let run = try IPCRun()
            let connection = try run.accept()
            try connection.send(IPC.AppMessage.start(request))
            let events = try run.events(from: connection) { event, connection in
                if case .progress(let progress) = event, progress.phase == .prepareTarget {
                    try? connection.send(IPC.AppMessage.cancel)
                    try? connection.send(IPC.AppMessage.cancel)
                }
                return true
            }
            let result = try run.wait()
            // The exit code of make interrupted by Ctrl-C.
            #expect(result.status == ExitCode.interrupted.rawValue, "\(result.stderr)")
            #expect(result.reason == .exit)
            #expect(result.stdout.isEmpty)
            guard case .failed(let error) = events.last else {
                Issue.record("the last event is not failed: \(String(describing: events.last))")
                return
            }
            #expect(error.kind == .cancelled)
            #expect(try attachedImageCount() == before)
            let work = try #require(workDirectory(in: events))
            #expect(!FileManager.default.fileExists(atPath: work))
        }

        /// The app quits or crashes: the tool cleans up and exits with a code, not SIGPIPE.
        @Test func appGoesAway() async throws {
            let before = try attachedImageCount()
            let scratch = try ScratchDirectory()
            let (request, _) = try await request(scratch)
            let run = try IPCRun()
            let connection = try run.accept()
            try connection.send(IPC.AppMessage.start(request))
            let events = try run.events(from: connection) { event, connection in
                if case .progress(let progress) = event, progress.phase == .prepareTarget {
                    connection.shutdown()
                    return false
                }
                return true
            }
            #expect(!events.contains { if case .finished = $0 { true } else { false } })
            let result = try run.wait()
            #expect(result.reason == .exit, "ended by signal \(result.status)")
            #expect(result.status == ExitCode.interrupted.rawValue, "\(result.stderr)")
            #expect(result.stdout.isEmpty)
            #expect(try attachedImageCount() == before)
            #expect(try !imageIsAttached(containing: scratch.url.lastPathComponent))
        }
    }
}

// MARK: - Harness

/// A directory with a short path (the socket path must fit in 104 bytes), with a space, a quote
/// and Hangul in its name. Removed at the end of the test.
final class ShortDirectory {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ss 테스트 '\(UUID().uuidString.prefix(4))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// The app's side for tests: listens, runs the built `snakestick ipc --socket`, reads events.
final class IPCRun {
    struct Result {
        var status: Int32
        var reason: Process.TerminationReason
        var stdout: String
        var stderr: String
    }

    let parent: ShortDirectory
    let listener: IPC.Listener
    let process = Process()
    private let stdout = LockedBox<Data>(Data())
    private let stderr = LockedBox<Data>(Data())
    private let drained = DispatchGroup()

    init() throws {
        parent = try ShortDirectory()
        listener = try IPC.Listener(parent: parent.url)
        process.executableURL = URL(fileURLWithPath: snakestickBinary)
        process.arguments = ["ipc", "--socket", listener.socketPath]
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        for (pipe, box) in [(out, stdout), (err, stderr)] {
            drained.enter()
            DispatchQueue.global().async { [drained] in
                box.value = pipe.fileHandleForReading.readDataToEndOfFile()
                drained.leave()
            }
        }
    }

    deinit {
        if process.isRunning {
            process.terminate()
        }
        listener.close()
    }

    /// The tool's connection; fails if it does not connect within 30 seconds.
    func accept() throws -> IPC.Connection {
        let deadline = Date().addingTimeInterval(30)
        let connection = try listener.accept { [process] in !process.isRunning || Date() > deadline }
        listener.close()
        guard let connection else {
            throw FixtureError("snakestick ipc did not connect")
        }
        return connection
    }

    /// Reads events until EOF, or until `handle` returns false.
    func events(
        from connection: IPC.Connection,
        handle: (InstallerEvent, IPC.Connection) -> Bool = { _, _ in true }
    ) throws -> [InstallerEvent] {
        var events: [InstallerEvent] = []
        while let message = try connection.receive(IPC.ToolMessage.self) {
            events.append(message.event)
            guard handle(message.event, connection) else {
                break
            }
        }
        return events
    }

    /// Waits up to two minutes for the tool to exit.
    func wait() throws -> Result {
        let deadline = Date().addingTimeInterval(120)
        while process.isRunning {
            guard Date() < deadline else {
                process.terminate()
                throw FixtureError("snakestick ipc did not exit")
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        drained.wait()
        return Result(
            status: process.terminationStatus,
            reason: process.terminationReason,
            stdout: String(decoding: stdout.value, as: UTF8.self),
            stderr: String(decoding: stderr.value, as: UTF8.self)
        )
    }
}
