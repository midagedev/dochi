import Foundation

/// Connection to the local `dochi-hermes-bridge` (see `HermesBridge/`).
///
/// Dochi owns voice + avatar; Hermes owns reasoning + memory + tools. This is
/// the seam that replaced the in-app LLM loop: transcribed text goes out, a
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

    private var endpoint: URL
    private let tokenProvider: () -> String?
    private let clientVersion: String

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var receiveLoop: Task<Void, Never>?
    private var reconnectAttempts = 0

    /// correlation_id → stream continuation for the in-flight request.
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
        self.endpoint = URL(string: "ws://\(host):\(port)")!
        self.clientVersion = clientVersion
        self.tokenProvider = tokenProvider
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
        connectionState = .connecting
        Log.app.info("Hermes bridge connecting to \(self.endpoint.absoluteString)")

        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: endpoint)
        self.session = session
        self.task = task
        task.resume()

        sendHello()
        startReceiveLoop()
    }

    func disconnect() {
        receiveLoop?.cancel()
        receiveLoop = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        failAllInFlight(HermesBridgeError.notConnected)
        connectionState = .disconnected
    }

    func reconfigure(host: String, port: Int) {
        let newEndpoint = URL(string: "ws://\(host):\(port)") ?? endpoint
        disconnect()
        endpoint = newEndpoint
        reconnectAttempts = 0
        connect()
    }

    private func sendHello() {
        let hello: [String: Any] = [
            "type": "hello",
            "token": tokenProvider() ?? "",
            "client": "dochi",
            "version": clientVersion,
        ]
        sendFrame(hello)
    }

    private func startReceiveLoop() {
        receiveLoop = Task { [weak self] in
            while let self, let task = self.task, !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    await self.handle(message: message)
                } catch {
                    await self.handleSocketFailure(error)
                    return
                }
            }
        }
    }

    private func handleSocketFailure(_ error: Error) {
        guard task != nil else { return }  // intentional disconnect
        Log.app.error("Hermes bridge socket error: \(error.localizedDescription)")
        task = nil
        session?.invalidateAndCancel()
        session = nil
        failAllInFlight(HermesBridgeError.backend(error.localizedDescription))
        connectionState = .failed(error.localizedDescription)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectAttempts += 1
        let delay = min(30, Int(pow(2.0, Double(min(reconnectAttempts, 5)))))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.task == nil else { return }
            self.connect()
        }
    }

    // MARK: Sending

    func send(text: String, conversationId: String, user: String?) -> AsyncThrowingStream<DochiAgentEvent, Error> {
        AsyncThrowingStream { continuation in
            guard case .connected = connectionState else {
                continuation.finish(throwing: HermesBridgeError.notConnected)
                return
            }
            let correlationId = UUID().uuidString
            continuations[correlationId] = continuation
            accumulated[correlationId] = ""

            continuation.onTermination = { [weak self] termination in
                Task { @MainActor in
                    guard let self else { return }
                    if case .cancelled = termination, self.continuations[correlationId] != nil {
                        self.sendFrame(["type": "cancel", "correlation_id": correlationId])
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
            ])
        }
    }

    private func sendFrame(_ object: [String: Any]) {
        guard let task else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8) else {
            Log.app.error("Hermes bridge: failed to encode frame")
            return
        }
        task.send(.string(json)) { error in
            if let error {
                Task { @MainActor [weak self] in
                    self?.handleSocketFailure(error)
                }
            }
        }
    }

    // MARK: Receiving

    private func handle(message: URLSessionWebSocketTask.Message) async {
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
