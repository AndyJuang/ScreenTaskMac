// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Network

private final class StartupContinuation: @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    @discardableResult
    func resume(_ result: Result<Void, Error>) -> Bool {
        guard let continuation else { return false }
        self.continuation = nil
        continuation.resume(with: result)
        return true
    }
}

/// All listener/connection/frame state is confined to queue. One immutable latest JPEG,
/// no per-client frame queue, and bounded request lifetime limit slow-reader memory use.
public final class HTTPServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ScreenTask.http")
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var frame: Data?
    private var router: Router
    private let address: String
    private let mask: String
    private let publicAccess: Bool
    private let onFailure: ((Error) -> Void)?

    public init(address: String, mask: String, publicAccess: Bool, router: Router, onFailure: ((Error) -> Void)? = nil) {
        self.address = address; self.mask = mask; self.publicAccess = publicAccess; self.router = router; self.onFailure = onFailure
    }
    public func publish(_ jpeg: Data) { queue.async { self.frame = jpeg } }
    public func start(port: UInt16) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let parameters = NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(self.address), port: NWEndpoint.Port(rawValue: port)!)
                    let listener = try NWListener(using: parameters)
                    self.listener = listener
                    let startup = StartupContinuation(continuation)
                    listener.stateUpdateHandler = { [weak self] state in
                        switch state {
                        case .ready:
                            startup.resume(.success(()))
                        case .failed(let error):
                            if !startup.resume(.failure(error)) { self?.onFailure?(error) }
                            self?.stopOnQueue()
                        case .cancelled:
                            startup.resume(.failure(CancellationError()))
                        default: break
                        }
                    }
                    listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                    listener.start(queue: self.queue)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    public func stop() { queue.sync { stopOnQueue() } }
    private func stopOnQueue() {
        listener?.cancel(); listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll(); frame = nil
    }
    private func accept(_ connection: NWConnection) {
        guard case .hostPort(let host, _) = connection.endpoint,
              LANScope.allows(peer: "\(host)", address: address, mask: mask, publicAccess: publicAccess) else {
            connection.cancel(); return
        }
        // Concurrent viewers are not licensed/capped. This cap is on simultaneous in-flight sockets only.
        guard connections.count < 256 else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.close(id) }
            if case .cancelled = state { self?.connections.removeValue(forKey: id) }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 10) { [weak self] in self?.close(id) }
        receive(connection, id: id, buffered: Data())
    }
    private func close(_ id: UUID) { connections.removeValue(forKey: id)?.cancel() }
    private func receive(_ connection: NWConnection, id: UUID, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] bytes, _, complete, error in
            guard let self, self.connections[id] != nil else { return }
            var data = buffered; if let bytes { data.append(bytes) }
            if data.count > 16384 { self.send(HTTPResponse(431), to: connection, id: id); return }
            if let end = data.range(of: Data("\r\n\r\n".utf8)) {
                guard let request = HTTPRequest(Data(data[..<end.upperBound])) else {
                    self.send(HTTPResponse(400), to: connection, id: id); return
                }
                self.send(self.router.response(to: request, jpeg: self.frame), to: connection, id: id, headOnly: request.method == "HEAD")
            } else if complete || error != nil { self.close(id) }
            else { self.receive(connection, id: id, buffered: data) }
        }
    }
    private func send(_ response: HTTPResponse, to connection: NWConnection, id: UUID, headOnly: Bool = false) {
        connection.send(content: response.encoded(headOnly: headOnly), completion: .contentProcessed { [weak self] _ in self?.close(id) })
    }
}
