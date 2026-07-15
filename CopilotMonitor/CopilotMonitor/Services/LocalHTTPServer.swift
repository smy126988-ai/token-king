import Foundation
import Network
import os.log

/// Loopback-only HTTP server exposing the current widget snapshot.
///
/// The widget extension prefers this channel over the raw file read: the
/// server reads `SharedPaths.snapshotURL` fresh on every request, so the
/// widget never hits `NSFileCoordinator` stalls and always sees the writer's
/// latest flush. Binding is restricted to the loopback interface via
/// `NWParameters.requiredInterfaceType = .loopback`, so nothing off-machine
/// can reach it.
///
/// Failure philosophy: this server is an *optimisation*, not a hard
/// dependency. Any failure (port busy, listener denied, file missing) is
/// logged and the widget silently falls back to the file channel.
final class LocalHTTPServer {

    private let logger = Logger(subsystem: "com.tokenking", category: "widget.httpserver")
    private let queue = DispatchQueue(label: "com.tokenking.local-http-server")
    private var listener: NWListener?

    /// Maximum request head we bother parsing (GET requests are tiny).
    private static let maxRequestBytes = 16 * 1024

    // MARK: - Lifecycle

    /// Starts listening on `SharedPaths.localSnapshotPort`. Calling `start()`
    /// on a running server replaces the existing listener.
    func start() {
        stop()
        guard let port = NWEndpoint.Port(rawValue: SharedPaths.localSnapshotPort) else {
            logger.error("snapshot server: invalid port \(SharedPaths.localSnapshotPort, privacy: .public)")
            return
        }
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        do {
            let newListener = try NWListener(using: params, on: port)
            newListener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.logger.info("snapshot server listening on 127.0.0.1:\(SharedPaths.localSnapshotPort, privacy: .public)")
                case .failed(let error):
                    self?.logger.error("snapshot server failed: \(error.localizedDescription, privacy: .public); widget will use file fallback")
                default:
                    break
                }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }
            newListener.start(queue: queue)
            listener = newListener
        } catch {
            logger.error("snapshot server start failed: \(error.localizedDescription, privacy: .public); widget will use file fallback")
        }
    }

    /// Stops the listener. Safe to call when not running.
    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    /// Accumulate bytes until the HTTP request head (`\r\n\r\n`) arrives,
    /// then respond. GET requests have no body, so the head is all we need.
    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxRequestBytes) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var accumulated = buffer
            if let data {
                accumulated.append(data)
            }
            if let headEnd = accumulated.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(bytes: accumulated[..<headEnd.lowerBound], encoding: .utf8) ?? ""
                self.respond(on: connection, requestHead: head)
                return
            }
            if isComplete || error != nil || accumulated.count > Self.maxRequestBytes {
                connection.cancel()
                return
            }
            self.receiveRequest(on: connection, buffer: accumulated)
        }
    }

    /// Route the request and write a complete HTTP/1.1 response, then close.
    private func respond(on connection: NWConnection, requestHead: String) {
        let requestLine = requestHead.split(separator: "\r\n").first.map(String.init) ?? ""
        let parts = requestLine.split(separator: " ")
        let method = parts.first.map(String.init) ?? ""
        let path = parts.count > 1 ? String(parts[1]) : ""

        let status: String
        let body: Data
        if method == "GET", path == "/snapshot" {
            if let data = try? Data(contentsOf: SharedPaths.snapshotURL) {
                status = "200 OK"
                body = data
            } else {
                // Snapshot not written yet — the widget falls back to its own
                // file path, which will report `noFile` and render the
                // placeholder state.
                status = "503 Service Unavailable"
                body = Data()
            }
        } else {
            status = "404 Not Found"
            body = Data()
        }

        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n"
        head += "\r\n"
        var response = Data(head.utf8)
        response.append(body)

        connection.send(content: response, completion: .contentProcessed { [weak connection] _ in
            connection?.cancel()
        })
    }
}
