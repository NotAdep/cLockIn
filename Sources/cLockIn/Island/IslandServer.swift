import CLockInCore
import Foundation
import Network

/// Listens on 127.0.0.1 for other apps' notch content and hands each request to the hub.
@MainActor
final class IslandServer {
    private let hub: IslandHub
    private var listener: NWListener?
    private(set) var port: UInt16 = IslandAPI.defaultPort
    /// If the usual port is taken, a few after it are tried.
    private static let portAttempts: UInt16 = 5

    init(hub: IslandHub) {
        self.hub = hub
    }

    var isRunning: Bool { listener != nil }

    func start() {
        guard listener == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        guard let listener = try? NWListener(using: parameters) else { return }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.listenerChanged(state) }
        }
        self.listener = listener
        listener.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        if let file = IslandAPI.discoveryFile { try? FileManager.default.removeItem(at: file) }
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            hub.port = port
            writeDiscoveryFile()
        case .failed:
            listener?.cancel()
            listener = nil
            if port < IslandAPI.defaultPort + Self.portAttempts {
                port += 1
                start()
            }
        default:
            break
        }
    }

    /// Tells clients which port to use: ~/Library/Application Support/cLockIn/island.json.
    private func writeDiscoveryFile() {
        guard let file = IslandAPI.discoveryFile else { return }
        let info: [String: Any] = ["port": Int(port), "version": IslandAPI.version, "pid": Int(getpid())]
        guard let data = try? JSONSerialization.data(withJSONObject: info) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    // MARK: Connections

    private func accept(_ connection: NWConnection) {
        // The listener is loopback-only already; this is a second check.
        if case .hostPort(let host, _) = connection.endpoint {
            let address = "\(host)".split(separator: "%").first.map(String.init) ?? ""
            guard ["127.0.0.1", "::1"].contains(address) else {
                connection.cancel()
                return
            }
        }
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
        // Nothing a client sends should take long; don't let a stalled connection linger.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak connection] in connection?.cancel() }
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else {
                    connection.cancel()
                    return
                }
                var buffer = buffer
                if let data { buffer.append(data) }
                switch IslandHTTP.parse(buffer) {
                case .incomplete:
                    if isComplete || error != nil { connection.cancel() } else { self.receive(on: connection, buffer: buffer) }
                case .invalid(let reason):
                    self.reply(connection, status: 400, body: Data(#"{"error":"\#(reason)"}"#.utf8))
                case .request(let request):
                    let (status, body) = self.hub.handle(request)
                    self.reply(connection, status: status, body: body)
                }
            }
        }
    }

    private func reply(_ connection: NWConnection, status: Int, body: Data) {
        connection.send(content: IslandHTTP.response(status: status, body: body), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
