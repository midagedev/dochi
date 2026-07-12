import Foundation

/// Connection to the optional `dochi-hermes-bridge` (see `HermesBridge/`).
///
/// Plain WebSocket is deliberately restricted to loopback. A bridge reached
/// over a LAN or the internet must be placed behind TLS and configured with a
/// `wss://` endpoint.
enum HermesBridgeError: LocalizedError {
    case notConnected
    case backend(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Hermes 에이전트에 연결되어 있지 않습니다."
        case .backend(let message): return message
        case .decoding: return "Hermes 응답을 해석할 수 없습니다."
        }
    }
}

enum HermesBridgeEndpointError: LocalizedError, Equatable {
    case invalidHost
    case invalidPort
    case unsupportedScheme
    case insecureRemoteEndpoint
    case unsupportedURLComponents

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            "Hermes 브리지 주소가 올바르지 않습니다. 호스트 또는 wss:// 주소를 입력해 주세요."
        case .invalidPort:
            "Hermes 브리지 포트는 1에서 65535 사이여야 합니다."
        case .unsupportedScheme:
            "Hermes 브리지는 ws:// 또는 wss:// 주소만 지원합니다."
        case .insecureRemoteEndpoint:
            "외부 Hermes 브리지는 wss:// TLS 연결만 허용합니다. ws://는 이 Mac의 loopback 주소에서만 사용할 수 있어요."
        case .unsupportedURLComponents:
            "Hermes 브리지 주소에는 사용자 정보, 경로, 포트, 쿼리 또는 fragment를 포함할 수 없습니다. 포트는 별도 입력란을 사용해 주세요."
        }
    }
}

/// Validated, canonical WebSocket endpoint used by the Hermes client.
struct HermesBridgeEndpoint: Sendable, Equatable {
    let url: URL
    let host: String
    let port: Int

    init(host rawValue: String, port: Int) throws {
        guard (1...65_535).contains(port) else {
            throw HermesBridgeEndpointError.invalidPort
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HermesBridgeEndpointError.invalidHost }

        let hasExplicitScheme = trimmed.contains("://")
        let candidate: String
        if hasExplicitScheme {
            candidate = trimmed
        } else {
            guard !trimmed.contains(where: { $0.isWhitespace }),
                  !trimmed.contains("/"),
                  !trimmed.contains("@"),
                  !trimmed.contains("?"),
                  !trimmed.contains("#") else {
                throw HermesBridgeEndpointError.invalidHost
            }
            let normalized = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            let scheme = Self.isLoopback(normalized) ? "ws" : "wss"
            let authority = normalized.contains(":") ? "[\(normalized)]" : normalized
            candidate = "\(scheme)://\(authority)"
        }

        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              let parsedHost = components.host?.lowercased(),
              !parsedHost.isEmpty else {
            throw HermesBridgeEndpointError.invalidHost
        }
        guard scheme == "ws" || scheme == "wss" else {
            throw HermesBridgeEndpointError.unsupportedScheme
        }
        guard components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/" else {
            throw HermesBridgeEndpointError.unsupportedURLComponents
        }
        guard scheme == "wss" || Self.isLoopback(parsedHost) else {
            throw HermesBridgeEndpointError.insecureRemoteEndpoint
        }

        components.scheme = scheme
        components.host = parsedHost
        components.port = port
        components.path = ""
        guard let url = components.url else { throw HermesBridgeEndpointError.invalidHost }
        self.url = url
        self.host = parsedHost
        self.port = port
    }

    static func isLoopback(_ host: String) -> Bool {
        let normalized = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if normalized == "localhost" || normalized.hasSuffix(".localhost") || normalized == "::1" {
            return true
        }
        let octets = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4,
              octets.first == "127",
              octets.allSatisfy({ part in
                  guard let value = Int(part) else { return false }
                  return (0...255).contains(value)
              }) else { return false }
        return true
    }
}

/// Tiny state machine that makes connection ownership explicit. Every socket
/// callback carries the generation returned by `beginConnection`; callbacks
/// from an older socket can therefore never mutate a newer connection.
struct HermesConnectionGeneration: Sendable, Equatable {
    private(set) var value: UInt64 = 0
    private(set) var reconnectAllowed = false

    mutating func beginConnection() -> UInt64 {
        value &+= 1
        reconnectAllowed = true
        return value
    }

    mutating func disconnect() {
        value &+= 1
        reconnectAllowed = false
    }

    func accepts(_ candidate: UInt64) -> Bool {
        candidate == value
    }

    func mayReconnect(after candidate: UInt64) -> Bool {
        reconnectAllowed && accepts(candidate)
    }
}

// MARK: - Implementation

@MainActor
@Observable
final class HermesAgentBridge: AgentBackendProtocol {
    private(set) var connectionState: AgentBackendConnectionState = .disconnected {
        didSet {
            if oldValue != connectionState {
                onConnectionStateChanged?(connectionState)
            }
        }
    }

    @ObservationIgnored var onProactiveMessage: (@MainActor (String) -> Void)?
    @ObservationIgnored var onConnectionStateChanged: (@MainActor (AgentBackendConnectionState) -> Void)?

    private var endpoint: HermesBridgeEndpoint?
    private var endpointError: HermesBridgeEndpointError?
    private let tokenProvider: () -> String?
    private let clientVersion: String

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var receiveLoop: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private var connectionGeneration = HermesConnectionGeneration()

    /// correlation_id -> stream continuation for the in-flight request.
    private var continuations: [String: AsyncThrowingStream<DochiAgentEvent, Error>.Continuation] = [:]
    /// Accumulated text per request, so `done` can carry the full message even
    /// if the backend omits it.
    private var accumulated: [String: String] = [:]

    init(
        host: String = "127.0.0.1",
        port: Int = 8765,
        clientVersion: String = "2.0.0",
        tokenProvider: @escaping () -> String? = HermesAgentBridge.defaultTokenProvider
    ) {
        self.clientVersion = clientVersion
        self.tokenProvider = tokenProvider
        do {
            endpoint = try HermesBridgeEndpoint(host: host, port: port)
        } catch let error as HermesBridgeEndpointError {
            endpoint = nil
            endpointError = error
            connectionState = .failed(error.localizedDescription)
        } catch {
            endpoint = nil
            endpointError = .invalidHost
            connectionState = .failed(HermesBridgeEndpointError.invalidHost.localizedDescription)
        }
    }

    /// Reads the shared token written by the bridge to `~/.hermes/dochi_bridge_token`.
    nonisolated static func defaultTokenProvider() -> String? {
        if let env = ProcessInfo.processInfo.environment["DOCHI_BRIDGE_TOKEN"], !env.isEmpty {
            return env
        }
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes/dochi_bridge_token")
        guard let raw = try? String(contentsOf: path, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: Connection lifecycle

    func connect() {
        guard task == nil else { return }
        guard let endpoint else {
            connectionState = .failed(
                (endpointError ?? .invalidHost).localizedDescription
            )
            return
        }

        reconnectTask?.cancel()
        reconnectTask = nil
        let generation = connectionGeneration.beginConnection()
        connectionState = .connecting
        Log.app.info("Hermes bridge connecting to \(endpoint.url.absoluteString)")

        let session = URLSession(configuration: .ephemeral)
        let socket = session.webSocketTask(with: endpoint.url)
        self.session = session
        task = socket
        socket.resume()

        sendHello(using: socket, generation: generation)
        startReceiveLoop(using: socket, generation: generation)
    }

    func disconnect() {
        connectionGeneration.disconnect()
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveLoop?.cancel()
        receiveLoop = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        reconnectAttempts = 0
        failAllInFlight(HermesBridgeError.notConnected)
        connectionState = .disconnected
    }

    func reconfigure(host: String, port: Int) {
        disconnect()
        do {
            endpoint = try HermesBridgeEndpoint(host: host, port: port)
            endpointError = nil
            connect()
        } catch let error as HermesBridgeEndpointError {
            endpoint = nil
            endpointError = error
            connectionState = .failed(error.localizedDescription)
        } catch {
            endpoint = nil
            endpointError = .invalidHost
            connectionState = .failed(HermesBridgeEndpointError.invalidHost.localizedDescription)
        }
    }

    private func sendHello(using socket: URLSessionWebSocketTask, generation: UInt64) {
        let hello: [String: Any] = [
            "type": "hello",
            "token": tokenProvider() ?? "",
            "client": "dochi",
            "version": clientVersion,
        ]
        sendFrame(hello, using: socket, generation: generation)
    }

    private func startReceiveLoop(using socket: URLSessionWebSocketTask, generation: UInt64) {
        receiveLoop?.cancel()
        receiveLoop = Task { [weak self] in
            while let self, !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    guard self.connectionGeneration.accepts(generation), self.task === socket else {
                        return
                    }
                    self.handle(message: message, generation: generation)
                } catch {
                    self.handleSocketFailure(error, socket: socket, generation: generation)
                    return
                }
            }
        }
    }

    private func handleSocketFailure(
        _ error: Error,
        socket: URLSessionWebSocketTask,
        generation: UInt64
    ) {
        guard connectionGeneration.accepts(generation), task === socket else {
            return
        }
        Log.app.error("Hermes bridge socket error: \(error.localizedDescription)")
        receiveLoop?.cancel()
        receiveLoop = nil
        task = nil
        session?.invalidateAndCancel()
        session = nil
        failAllInFlight(HermesBridgeError.backend(error.localizedDescription))
        connectionState = .failed(error.localizedDescription)
        scheduleReconnect(after: generation)
    }

    private func scheduleReconnect(after generation: UInt64) {
        guard connectionGeneration.mayReconnect(after: generation) else { return }
        reconnectTask?.cancel()
        reconnectAttempts += 1
        let delay = min(30, Int(pow(2.0, Double(min(reconnectAttempts, 5)))))
        reconnectTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self,
                  self.connectionGeneration.mayReconnect(after: generation),
                  self.task == nil else { return }
            self.reconnectTask = nil
            self.connect()
        }
    }

    // MARK: Sending

    func send(text: String, conversationId: String, user: String?) -> AsyncThrowingStream<DochiAgentEvent, Error> {
        AsyncThrowingStream { continuation in
            guard case .connected = connectionState,
                  let socket = task else {
                continuation.finish(throwing: HermesBridgeError.notConnected)
                return
            }
            let generation = connectionGeneration.value
            let correlationId = UUID().uuidString
            continuations[correlationId] = continuation
            accumulated[correlationId] = ""

            continuation.onTermination = { [weak self] termination in
                Task { @MainActor in
                    guard let self else { return }
                    if case .cancelled = termination, self.continuations[correlationId] != nil {
                        self.sendFrame([
                            "type": "cancel",
                            "correlation_id": correlationId,
                        ])
                    }
                    self.continuations[correlationId] = nil
                    self.accumulated[correlationId] = nil
                }
            }

            sendFrame([
                "type": "user_message",
                "correlation_id": correlationId,
                "conversation_id": conversationId,
                "user": user as Any,
                "text": text,
            ], using: socket, generation: generation)
        }
    }

    private func sendFrame(_ object: [String: Any]) {
        guard let socket = task else { return }
        sendFrame(object, using: socket, generation: connectionGeneration.value)
    }

    private func sendFrame(
        _ object: [String: Any],
        using socket: URLSessionWebSocketTask,
        generation: UInt64
    ) {
        guard connectionGeneration.accepts(generation), task === socket else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8) else {
            Log.app.error("Hermes bridge: failed to encode frame")
            return
        }
        socket.send(.string(json)) { error in
            if let error {
                Task { @MainActor [weak self, weak socket] in
                    guard let self, let socket else { return }
                    self.handleSocketFailure(error, socket: socket, generation: generation)
                }
            }
        }
    }

    // MARK: Receiving

    private func handle(message: URLSessionWebSocketTask.Message, generation: UInt64) {
        guard connectionGeneration.accepts(generation) else { return }
        let text: String
        switch message {
        case .string(let value):
            text = value
        case .data(let data):
            text = String(data: data, encoding: .utf8) ?? ""
        @unknown default:
            return
        }
        guard let data = text.data(using: .utf8),
              let frame = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = frame["type"] as? String else {
            Log.app.warning("Hermes bridge: undecodable frame")
            return
        }
        route(type: type, frame: frame)
    }

    private func route(type: String, frame: [String: Any]) {
        switch type {
        case "ready":
            reconnectAttempts = 0
            connectionState = .connected(name: frame["persona"] as? String)
            Log.app.info("Hermes bridge connected (persona=\(frame["persona"] as? String ?? "nil"))")

        case "delta":
            guard let cid = frame["correlation_id"] as? String,
                  let chunk = frame["text"] as? String else { return }
            accumulated[cid, default: ""] += chunk
            continuations[cid]?.yield(.delta(chunk))

        case "tool":
            guard let cid = frame["correlation_id"] as? String,
                  let name = frame["name"] as? String else { return }
            let summary = frame["summary"] as? String
            let phase = frame["phase"] as? String ?? "start"
            if phase == "end" {
                let isError = frame["is_error"] as? Bool ?? false
                continuations[cid]?.yield(.toolFinished(name: name, isError: isError, summary: summary))
            } else {
                continuations[cid]?.yield(.toolStarted(name: name, summary: summary))
            }

        case "done":
            guard let cid = frame["correlation_id"] as? String else { return }
            let full = (frame["text"] as? String) ?? accumulated[cid] ?? ""
            let messageId = frame["message_id"] as? String
            continuations[cid]?.yield(.done(text: full, messageId: messageId))
            continuations[cid]?.finish()
            continuations[cid] = nil
            accumulated[cid] = nil

        case "error":
            let message = frame["message"] as? String ?? "Hermes 오류"
            if let cid = frame["correlation_id"] as? String, let cont = continuations[cid] {
                cont.finish(throwing: HermesBridgeError.backend(message))
                continuations[cid] = nil
                accumulated[cid] = nil
            } else {
                Log.app.error("Hermes bridge error (unattributed): \(message)")
            }

        case "proactive":
            if let text = frame["text"] as? String, !text.isEmpty {
                onProactiveMessage?(text)
            }

        case "pong":
            break

        default:
            Log.app.debug("Hermes bridge: ignoring frame type \(type)")
        }
    }

    private func failAllInFlight(_ error: Error) {
        for (_, continuation) in continuations {
            continuation.finish(throwing: error)
        }
        continuations.removeAll()
        accumulated.removeAll()
    }
}
