import Darwin
import Foundation
import Network
import os

struct MCPSocketAddress {
    let directory: URL

    static var current: Self {
        let development = Bundle.main.bundleIdentifier != "com.goodfeels.magpie"
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return Self(directory: home.appendingPathComponent(development ? ".magpie-mcp-dev" : ".magpie-mcp"))
    }

    var path: String { directory.appendingPathComponent("mcp").path }
    var endpoint: NWEndpoint { .unix(path: path) }

    func prepareDirectory() throws {
        if mkdir(directory.path, S_IRWXU) != 0 && errno != EEXIST {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard isPrivate else { throw POSIXError(.EACCES) }
        let address = sockaddr_un()
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw POSIXError(.ENAMETOOLONG)
        }
    }

    var isPrivate: Bool {
        var info = stat()
        return lstat(directory.path, &info) == 0
            && (info.st_mode & S_IFMT) == S_IFDIR
            && info.st_uid == geteuid()
            && (info.st_mode & 0o077) == 0
    }
}

/// Holds an exclusive lock while a listener owns the socket pathname.
/// A subsequent launch can safely remove the socket left by a crash.
private final class MCPSocketLease {
    private let descriptor: Int32
    private let path: String

    init(address: MCPSocketAddress) throws {
        try address.prepareDirectory()
        let lock = open(address.directory.appendingPathComponent("lock").path, O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_RDWR, S_IRUSR | S_IWUSR)
        guard lock >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        if flock(lock, LOCK_EX | LOCK_NB) != 0 {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            close(lock)
            throw POSIXError(code)
        }
        var info = stat()
        if lstat(address.path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFSOCK,
                  info.st_uid == geteuid(),
                  unlink(address.path) == 0 else {
                close(lock)
                throw POSIXError(.EACCES)
            }
        }
        descriptor = lock
        path = address.path
    }

    deinit {
        unlink(path)
        close(descriptor)
    }
}

private enum MCPWire {
    static let requestLimit = 64 * 1024
    static let replyLimit = 128 * 1024

    /// One newline-delimited message per Unix connection. An empty reply
    /// acknowledges a notification without producing anything on stdio.
    static func receiveLine(
        on connection: NWConnection,
        limit: Int,
        pending: Data = Data(),
        completion: @escaping @Sendable (Data?) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { chunk, _, _, error in
            guard error == nil, let chunk, !chunk.isEmpty else { completion(nil); return }
            var bytes = pending
            if let newline = chunk.firstIndex(of: 10) {
                bytes.append(contentsOf: chunk[..<newline])
                completion(bytes.count <= limit ? bytes : nil)
            } else if bytes.count + chunk.count <= limit {
                bytes.append(chunk)
                receiveLine(on: connection, limit: limit, pending: bytes, completion: completion)
            } else {
                completion(nil)
            }
        }
    }
}

final class MCPLocalServer {
    private let queue = DispatchQueue(label: "com.goodfeels.magpie.mcp")
    private let listener: NWListener
    // Accessed only on the listener queue.
    private var connections: [UUID: NWConnection] = [:]

    init(
        address: MCPSocketAddress,
        onState: @escaping @Sendable (NWListener.State) -> Void,
        respond: @escaping @Sendable (Data) async -> Data?
    ) throws {
        let lease = try MCPSocketLease(address: address)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = address.endpoint
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [lease] state in
            onState(state)
            withExtendedLifetime(lease) {}
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.accept(connection, respond: respond)
        }
        listener.start(queue: queue)
    }

    deinit { listener.cancel() }

    private func accept(_ connection: NWConnection, respond: @escaping @Sendable (Data) async -> Data?) {
        guard connections.count < 16 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in self?.close(id) }
        connection.start(queue: queue)
        MCPWire.receiveLine(on: connection, limit: MCPWire.requestLimit) { [weak self] request in
            guard let request else { self?.close(id); return }
            Task {
                let response = await respond(request)
                self?.send(response ?? Data(), to: id)
            }
        }
    }

    private func send(_ response: Data, to id: UUID) {
        queue.async { [weak self] in
            guard let self, let connection = self.connections[id] else { return }
            connection.send(
                content: response + Data([10]),
                contentContext: .finalMessage,
                completion: .contentProcessed { [weak self] error in
                    guard error == nil else { self?.close(id); return }
                    // Leave the socket open for the peer to drain the reply and disconnect.
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] _, _, _, _ in
                        self?.close(id)
                    }
                }
            )
        }
    }

    private func close(_ id: UUID) {
        connections.removeValue(forKey: id)?.cancel()
    }
}

enum MCPStdioBridge {
    static func run(address: MCPSocketAddress = .current) {
        let transportQueue = DispatchQueue(label: "com.goodfeels.magpie.mcp.stdio")
        // fgets keeps reads bounded even if a client never sends a newline.
        var buffer = [CChar](repeating: 0, count: MCPWire.requestLimit + 2)
        while fgets(&buffer, Int32(buffer.count), stdin) != nil {
            let length = strlen(buffer)
            guard length > 0, buffer[length - 1] == 10 else {
                FileHandle.standardError.write(Data("Magpie MCP received an oversized or incomplete request.\n".utf8))
                return
            }
            let request = Data(buffer.prefix(length - 1).map { UInt8(bitPattern: $0) })
            let response = exchange(request, address: address, queue: transportQueue)
                ?? MCPProtocol.respond(to: request)
            if let response, !response.isEmpty {
                do {
                    try FileHandle.standardOutput.write(contentsOf: response + Data([10]))
                } catch {
                    return
                }
            }
        }
    }

    private static func exchange(_ request: Data, address: MCPSocketAddress, queue: DispatchQueue) -> Data? {
        var info = stat()
        guard address.isPrivate, lstat(address.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFSOCK, info.st_uid == geteuid() else {
            return nil
        }
        let connection = NWConnection(to: address.endpoint, using: .tcp)
        let group = DispatchGroup()
        let reply = OSAllocatedUnfairLock(initialState: (finished: false, body: Data?.none))
        group.enter()
        let finish: @Sendable (Data?) -> Void = { response in
            let completed = reply.withLock { result in
                guard !result.finished else { return false }
                result = (true, response)
                return true
            }
            guard completed else { return }
            connection.stateUpdateHandler = nil
            connection.cancel()
            group.leave()
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: request + Data([10]), completion: .contentProcessed { error in
                    guard error == nil else { finish(nil); return }
                    MCPWire.receiveLine(on: connection, limit: MCPWire.replyLimit, completion: finish)
                })
            case .failed, .waiting, .cancelled:
                finish(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
        if group.wait(timeout: .now() + 6) == .timedOut {
            queue.sync { finish(nil) }
        }
        return reply.withLock { $0.body }
    }
}
