// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The connection between the app and `snakestick ipc` (stage 20, decision 4).
///
/// The app listens on a Unix domain stream socket in a directory only its user can enter, and
/// starts `snakestick ipc --socket PATH` as root through `do shell script … with administrator
/// privileges`. The tool connects, reads one ``AppMessage/start(_:)``, and sends the pipeline's
/// events until the last one (`finished` or `failed`); then it closes the connection and exits.
/// Both directions carry one JSON object per line.
///
/// Cancelling: the app sends ``AppMessage/cancel``, or closes its end (quitting, crashing). The
/// tool cancels the pipeline either way, and sends `failed` of kind `.cancelled` after cleanup.
public enum IPC {
    /// App → tool.
    ///
    /// On the wire: `{"start":{…InstallerRequest…}}` or `{"cancel":{}}`.
    public enum AppMessage: Sendable, Equatable, Codable {
        /// Exactly once, as the first message.
        case start(InstallerRequest)
        /// At any time. A second one changes nothing.
        case cancel

        private enum CodingKeys: String, CodingKey {
            case start
            case cancel
        }

        private struct Empty: Codable {}

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let request = try container.decodeIfPresent(InstallerRequest.self, forKey: .start) {
                self = .start(request)
            } else if container.contains(.cancel) {
                self = .cancel
            } else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "neither start nor cancel"))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .start(let request):
                try container.encode(request, forKey: .start)
            case .cancel:
                try container.encode(Empty(), forKey: .cancel)
            }
        }
    }

    /// Tool → app: `{"event":{…InstallerEvent…}}`. The last one is `finished` or `failed`.
    public struct ToolMessage: Sendable, Equatable, Codable {
        public var event: InstallerEvent

        public init(event: InstallerEvent) {
            self.event = event
        }
    }

    /// `message` as one line: compact JSON and a newline. JSON escapes the control characters in
    /// strings, so a log line with `\n` in it stays on one line.
    public static func line(_ message: some Encodable) throws -> Data {
        var data = try JSONEncoder().encode(message)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    /// The message in `line` (with or without its newline).
    public static func decode<T: Decodable>(_ type: T.Type, line: Data) throws -> T {
        try JSONDecoder().decode(type, from: line)
    }

    /// The longest socket path `bind` and `connect` take: `sun_path` holds 104 bytes with the
    /// terminating NUL. A longer path is refused rather than truncated.
    public static let maximumPathLength = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1

    public struct SocketError: Error, CustomStringConvertible {
        public var operation: String
        public var path: String?
        public var errno: Int32?

        public var description: String {
            var text = operation
            if let path {
                text += " (\(path))"
            }
            if let errno {
                text += ": \(String(cString: strerror(errno)))"
            }
            return text
        }
    }

    // MARK: - Sockets

    /// A connected stream socket.
    ///
    /// ``send(_:)`` may be called from any thread; ``receive(_:)`` from one reader at a time.
    /// Writing to a connection the other side has closed throws (`EPIPE`) instead of raising
    /// SIGPIPE (`SO_NOSIGPIPE`), so neither side dies when the other goes away first.
    public final class Connection: @unchecked Sendable {
        // Unchecked: `fd` is immutable; writes are serialized by `writeLock`; `buffer` belongs
        // to the single reader.
        private let fd: Int32
        private let writeLock = NSLock()
        private var buffer: [UInt8] = []

        init(fd: Int32) {
            self.fd = fd
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            IPC.closeOnExec(fd)
        }

        deinit {
            Darwin.close(fd)
        }

        /// Connects to the socket at `path`.
        public static func connect(to path: String) throws -> Connection {
            var address = try IPC.address(for: path)
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else {
                throw SocketError(operation: "socket", errno: Darwin.errno)
            }
            let status = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard status == 0 else {
                let code = Darwin.errno
                Darwin.close(fd)
                throw SocketError(operation: "connect", path: path, errno: code)
            }
            return Connection(fd: fd)
        }

        /// Sends `message` as one line. Returns once every byte is with the kernel.
        public func send(_ message: some Encodable) throws {
            let data = try IPC.line(message)
            try writeLock.withLock {
                try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                    var offset = 0
                    while offset < bytes.count {
                        let written = write(fd, bytes.baseAddress! + offset, bytes.count - offset)
                        if written < 0 {
                            if Darwin.errno == EINTR {
                                continue
                            }
                            throw SocketError(operation: "write", errno: Darwin.errno)
                        }
                        offset += written
                    }
                }
            }
        }

        /// The next message, or nil when the other side has closed its end (or
        /// ``shutdown()`` was called). Blocks until a whole line has arrived.
        public func receive<T: Decodable>(_ type: T.Type) throws -> T? {
            guard let line = try readLine() else {
                return nil
            }
            return try IPC.decode(type, line: line)
        }

        /// The next line without its newline, or nil at the end of the stream. A partial last
        /// line is dropped.
        public func readLine() throws -> Data? {
            while true {
                if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = Data(buffer[..<newline])
                    buffer.removeSubrange(...newline)
                    return line
                }
                var chunk = [UInt8](repeating: 0, count: 16 << 10)
                let count = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
                if count < 0 {
                    if Darwin.errno == EINTR {
                        continue
                    }
                    // ECONNRESET and the like: the other side is gone, as at EOF.
                    if [ECONNRESET, ENOTCONN, EBADF].contains(Darwin.errno) {
                        return nil
                    }
                    throw SocketError(operation: "read", errno: Darwin.errno)
                }
                if count == 0 {
                    return nil
                }
                buffer.append(contentsOf: chunk[..<count])
            }
        }

        /// Ends both directions: a reader blocked in ``receive(_:)`` gets nil, the other side
        /// gets EOF after everything already sent. The descriptor is closed on deinit.
        public func shutdown() {
            _ = Darwin.shutdown(fd, SHUT_RDWR)
        }

        /// Ends the sending direction only: the other side reads what was sent, then EOF.
        public func finishSending() {
            _ = Darwin.shutdown(fd, SHUT_WR)
        }
    }

    /// The app's end: a socket bound in a new directory (mode 0700) under `parent`.
    ///
    /// The directory and socket names are short, because the whole path has to fit in
    /// ``maximumPathLength`` bytes and `NSTemporaryDirectory()` alone takes about 50.
    public final class Listener: @unchecked Sendable {
        // Unchecked: `fd` is only closed by `close()`, guarded by `lock`.
        public let directory: URL
        public let socketPath: String
        private let lock = NSLock()
        private var fd: Int32

        public init(parent: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)) throws {
            var template = Array(parent.appendingPathComponent("ss.XXXXXX").path.utf8CString)
            guard let created = template.withUnsafeMutableBufferPointer({ mkdtemp($0.baseAddress!) }) else {
                throw SocketError(operation: "mkdtemp", path: parent.path, errno: Darwin.errno)
            }
            let directory = String(cString: created)
            self.directory = URL(fileURLWithPath: directory, isDirectory: true)
            socketPath = directory + "/s"
            fd = -1
            do {
                // mkdtemp already makes it 0700; set it anyway so that the umask plays no part.
                guard chmod(directory, 0o700) == 0 else {
                    throw SocketError(operation: "chmod", path: directory, errno: Darwin.errno)
                }
                var address = try IPC.address(for: socketPath)
                let fd = socket(AF_UNIX, SOCK_STREAM, 0)
                guard fd >= 0 else {
                    throw SocketError(operation: "socket", errno: Darwin.errno)
                }
                self.fd = fd
                IPC.closeOnExec(fd)
                let status = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
                guard status == 0 else {
                    throw SocketError(operation: "bind", path: socketPath, errno: Darwin.errno)
                }
                guard listen(fd, 1) == 0 else {
                    throw SocketError(operation: "listen", path: socketPath, errno: Darwin.errno)
                }
            } catch {
                close()
                throw error
            }
        }

        deinit {
            close()
        }

        /// Waits for one connection. Returns nil once `shouldStop` returns true; it is asked
        /// every `pollInterval` seconds, so that a peer that never connects (the authentication
        /// was cancelled, the tool died) does not leave this waiting forever.
        public func accept(pollInterval: TimeInterval = 0.1, shouldStop: () -> Bool) throws -> Connection? {
            let listening = lock.withLock { fd }
            guard listening >= 0 else {
                return nil
            }
            while !shouldStop() {
                var entry = pollfd(fd: listening, events: Int16(POLLIN), revents: 0)
                let ready = poll(&entry, 1, Int32(pollInterval * 1000))
                if ready < 0 {
                    if Darwin.errno == EINTR {
                        continue
                    }
                    throw SocketError(operation: "poll", path: socketPath, errno: Darwin.errno)
                }
                guard ready > 0 else {
                    continue
                }
                if entry.revents & Int16(POLLNVAL) != 0 {
                    // close() ran meanwhile.
                    return nil
                }
                let connected = Darwin.accept(listening, nil, nil)
                if connected < 0 {
                    if [EINTR, EAGAIN, ECONNABORTED].contains(Darwin.errno) {
                        continue
                    }
                    throw SocketError(operation: "accept", path: socketPath, errno: Darwin.errno)
                }
                return Connection(fd: connected)
            }
            return nil
        }

        /// Closes the listening socket and removes the socket file and the directory. Accepted
        /// connections stay open. Safe to call more than once.
        public func close() {
            let listening: Int32 = lock.withLock {
                defer { fd = -1 }
                return fd
            }
            if listening >= 0 {
                Darwin.close(listening)
            }
            unlink(socketPath)
            rmdir(directory.path)
        }
    }

    /// Keeps `fd` out of the processes started meanwhile (osascript, hdiutil, diskutil): a child
    /// holding the connection would delay the EOF the other side waits for.
    private static func closeOnExec(_ fd: Int32) {
        _ = fcntl(fd, F_SETFD, fcntl(fd, F_GETFD) | FD_CLOEXEC)
    }

    private static func address(for path: String) throws -> sockaddr_un {
        let bytes = Array(path.utf8)
        guard bytes.count <= maximumPathLength else {
            throw SocketError(operation: "socket path longer than \(maximumPathLength) bytes", path: path)
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        return address
    }
}
