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

/// All listener/connection/frame state is confined to queue. One immutable latest JPEG and one
/// write in flight per client: a client that is behind loses frames rather than collecting them.
/// What it can still accumulate is the socket send buffer, since `.contentProcessed` fires when the
/// transport takes the bytes, not when the peer reads them; once that buffer fills, the write stalls
/// and `writeTimeout` drops the client.
///
/// Connections are persistent. A viewer either holds one multipart/x-mixed-replace stream or
/// reuses one kept-alive connection for its polls; the previous one-connection-per-frame
/// behaviour created thousands of short-lived inbound flows per minute, and each of those made
/// the kernel re-run its network policy hooks for this process.
public final class HTTPServer: @unchecked Sendable {
    /// Seconds a fresh connection may stay open before its first complete request arrives.
    private static let firstRequestTimeout = 10.0
    /// Seconds a kept-alive connection may stay idle between requests.
    private static let idleTimeout = 20.0
    /// Seconds a write may stay unfinished before the peer counts as stalled. A viewer that stops
    /// draining its stream would otherwise queue frames into the socket buffer indefinitely.
    private static let writeTimeout = 10.0
    /// Simultaneous sockets, not viewers. A viewer holds two: its stream and its heartbeat.
    private static let connectionLimit = 256
    /// Sockets one peer may hold. Streams have no natural deadline, so without this one LAN host
    /// could open the whole table and lock everybody else out.
    private static let perPeerLimit = 24

    private final class Client {
        let connection: NWConnection
        let peer: String
        /// Cancelled, but the socket may still be alive: it keeps its place in the table until the
        /// connection actually reports `.cancelled`, so a stalled peer cannot buy new slots by
        /// stalling. Nothing is sent to it any more.
        var closing = false
        /// Receiving frames as multipart parts rather than answering discrete requests.
        var streaming = false
        /// A write is in flight; the next frame is dropped rather than queued behind it in the app.
        var busy = false
        var deadline: DispatchWorkItem?
        init(_ connection: NWConnection, peer: String) { self.connection = connection; self.peer = peer }
    }

    private let queue = DispatchQueue(label: "ScreenTask.http")
    private var listener: NWListener?
    private var clients: [UUID: Client] = [:]
    private var frame: Data?
    private var router: Router
    private let address: String
    private let mask: String
    private let publicAccess: Bool
    private let onFailure: ((Error) -> Void)?

    public init(address: String, mask: String, publicAccess: Bool, router: Router, onFailure: ((Error) -> Void)? = nil) {
        self.address = address; self.mask = mask; self.publicAccess = publicAccess; self.router = router; self.onFailure = onFailure
    }

    public func publish(_ jpeg: Data) {
        queue.async {
            self.frame = jpeg
            guard self.clients.values.contains(where: { $0.streaming && !$0.busy && !$0.closing }) else { return }
            let part = MJPEG.part(jpeg)
            for (id, client) in self.clients where client.streaming && !client.busy && !client.closing {
                client.busy = true
                self.write(part, to: id) { [weak self] in self?.clients[id]?.busy = false }
            }
        }
    }

    public func start(port: UInt16) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let options = NWProtocolTCP.Options()
                    // A phone that sleeps or leaves Wi-Fi sends no FIN; probes reclaim its stream slot.
                    options.enableKeepalive = true
                    options.keepaliveIdle = 30
                    options.keepaliveInterval = 10
                    options.keepaliveCount = 3
                    // Cancelling a connection whose peer stopped reading cannot even emit a FIN: the
                    // socket sits in the persist state holding undelivered frames. These let the
                    // kernel drop it instead of leaking the socket and its buffer.
                    options.persistTimeout = 30
                    options.connectionDropTime = 30
                    let parameters = NWParameters(tls: nil, tcp: options)
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
        for client in clients.values { client.deadline?.cancel(); client.connection.cancel() }
        clients.removeAll(); frame = nil
    }

    private func accept(_ connection: NWConnection) {
        guard case .hostPort(let host, _) = connection.endpoint,
              LANScope.allows(peer: "\(host)", address: address, mask: mask, publicAccess: publicAccess) else {
            connection.cancel(); return
        }
        let peer = "\(host)"
        guard clients.count < Self.connectionLimit,
              clients.values.filter({ $0.peer == peer }).count < Self.perPeerLimit else { connection.cancel(); return }
        let id = UUID()
        clients[id] = Client(connection, peer: peer)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed: self?.close(id)
            case .cancelled: self?.forget(id)
            default: break
            }
        }
        connection.start(queue: queue)
        arm(id, seconds: Self.firstRequestTimeout)
        receive(id, buffered: Data())
    }

    /// Schedules the connection to be dropped unless something resets the timer first. A write that
    /// runs out of time is reset rather than closed: its peer is not reading, so a graceful close
    /// would sit in the send queue behind the frames it never took.
    private func arm(_ id: UUID, seconds: Double, forceful: Bool = false) {
        guard let client = clients[id], !client.closing else { return }
        client.deadline?.cancel()
        let work = DispatchWorkItem { [weak self] in forceful ? self?.drop(id) : self?.close(id) }
        client.deadline = work
        queue.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func disarm(_ id: UUID) {
        clients[id]?.deadline?.cancel()
        clients[id]?.deadline = nil
    }

    /// Ends a connection after its response is delivered. The entry stays in the table until the
    /// connection reports `.cancelled`, so a peer cannot buy new slots by leaving sockets behind.
    private func close(_ id: UUID) { finish(id, forceful: false) }

    /// Resets a connection whose peer stopped reading, discarding whatever it never took.
    private func drop(_ id: UUID) { finish(id, forceful: true) }

    private func finish(_ id: UUID, forceful: Bool) {
        guard let client = clients[id], !client.closing else { return }
        client.closing = true
        client.deadline?.cancel(); client.deadline = nil
        if forceful { client.connection.forceCancel() } else { client.connection.cancel() }
    }

    private func forget(_ id: UUID) {
        clients.removeValue(forKey: id)?.deadline?.cancel()
    }

    private func receive(_ id: UUID, buffered: Data) {
        guard let client = clients[id], !client.closing else { return }
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] bytes, _, complete, error in
            guard let self, let client = self.clients[id], !client.closing else { return }
            var data = buffered
            if let bytes { data.append(bytes) }
            if data.count > 16384 { self.respond(HTTPResponse(431), to: id, keepAlive: false); return }
            guard let end = data.range(of: Data("\r\n\r\n".utf8)) else {
                if complete || error != nil { self.close(id) } else { self.receive(id, buffered: data) }
                return
            }
            // Request pipelining is not supported: anything past the header terminator is a
            // request body or a pipelined request, and either way the stream is no longer framed.
            guard end.upperBound == data.endIndex, let request = HTTPRequest(Data(data[..<end.upperBound])) else {
                self.respond(HTTPResponse(400), to: id, keepAlive: false); return
            }
            self.handle(request, id: id)
        }
    }

    private func handle(_ request: HTTPRequest, id: UUID) {
        let response = router.response(to: request, jpeg: frame)
        let headOnly = request.method == "HEAD"
        guard response.streaming, !headOnly else {
            let wantsClose = (request.headers["connection"] ?? "").lowercased().contains("close")
                // No route takes a body. An unread body would be parsed as the next request, so close.
                || request.headers["content-length"].flatMap(Int.init).map { $0 > 0 } == true
                || request.headers["transfer-encoding"] != nil
            // A streaming response has no Content-Length, so a HEAD of it cannot be kept alive.
            respond(response, to: id, headOnly: headOnly, keepAlive: !wantsClose && !response.streaming)
            return
        }
        guard let client = clients[id] else { return }
        client.streaming = true
        client.busy = true
        // The stream ends only when the connection closes, so it is never kept alive for reuse.
        disarm(id)
        var payload = response.encoded()
        if let frame { payload.append(MJPEG.part(frame)) }
        write(payload, to: id) { [weak self] in self?.clients[id]?.busy = false }
    }

    private func respond(_ response: HTTPResponse, to id: UUID, headOnly: Bool = false, keepAlive: Bool) {
        write(response.encoded(headOnly: headOnly, keepAlive: keepAlive), to: id) { [weak self] in
            guard let self else { return }
            guard keepAlive else { self.close(id); return }
            self.arm(id, seconds: Self.idleTimeout)
            self.receive(id, buffered: Data())
        }
    }

    /// Completion handlers arrive on `queue`, the queue every connection was started on. The deadline
    /// covers the write itself: `.contentProcessed` only means the transport took the bytes, so a peer
    /// that never drains stalls here once its socket buffer fills, and then this closes it.
    private func write(_ data: Data, to id: UUID, then finish: @escaping () -> Void) {
        guard let client = clients[id], !client.closing else { return }
        arm(id, seconds: Self.writeTimeout, forceful: true)
        client.connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self, let client = self.clients[id], !client.closing else { return }
            self.disarm(id)
            if error != nil { self.close(id) } else { finish() }
        })
    }
}
