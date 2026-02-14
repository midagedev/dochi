import Foundation
import os

/// Slack bot service using Web API + Socket Mode.
@MainActor
final class SlackService: SlackServiceProtocol {
    private(set) var isConnected = false
    var onMessage: (@MainActor @Sendable (SlackMessage) -> Void)?

    private var botToken: String?
    private var appToken: String?
    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTask: Task<Void, Never>?
    private var botUserId: String?

    init() {}

    // MARK: - Connection

    func connect(botToken: String, appToken: String) async throws {
        self.botToken = botToken
        self.appToken = appToken

        // Get WebSocket URL via apps.connections.open
        let wsURL = try await openConnection(appToken: appToken)

        // Identify bot user
        let botUser = try await authTest(botToken: botToken)
        botUserId = botUser.id
        Log.cloud.info("Slack bot connected: \(botUser.name) (\(botUser.id))")

        // Connect WebSocket
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: wsURL)
        webSocketTask?.resume()
        isConnected = true

        startReceiving()
        startPing()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        pingTask?.cancel()
        pingTask = nil
        isConnected = false
        Log.cloud.info("Slack bot disconnected")
    }

    // MARK: - Messaging

    func sendMessage(channelId: String, text: String, threadTs: String?) async throws -> String {
        guard let botToken else { throw SlackError.notConnected }

        var body: [String: Any] = [
            "channel": channelId,
            "text": text,
        ]
        if let threadTs {
            body["thread_ts"] = threadTs
        }

        let result = try await apiCall("chat.postMessage", body: body, token: botToken)
        guard let ts = result["ts"] as? String else {
            throw SlackError.invalidResponse
        }
        return ts
    }

    func updateMessage(channelId: String, ts: String, text: String) async throws {
        guard let botToken else { throw SlackError.notConnected }

        let body: [String: Any] = [
            "channel": channelId,
            "ts": ts,
            "text": text,
        ]
        _ = try await apiCall("chat.update", body: body, token: botToken)
    }

    func sendTyping(channelId: String) async throws {
        // Slack doesn't have a direct typing indicator API for bots in the same way.
        // We can use chat.postMessage with a "typing..." placeholder, but that's noisy.
        // For Socket Mode, we skip this.
        Log.cloud.debug("Slack typing indicator skipped (not supported for bots)")
    }

    func authTest(botToken: String) async throws -> SlackUser {
        let result = try await apiCall("auth.test", body: [:], token: botToken)
        guard let userId = result["user_id"] as? String,
              let userName = result["user"] as? String else {
            throw SlackError.invalidResponse
        }
        let isBot = result["bot_id"] != nil
        return SlackUser(id: userId, name: userName, isBot: isBot)
    }

    // MARK: - Socket Mode

    private func openConnection(appToken: String) async throws -> URL {
        let result = try await apiCall("apps.connections.open", body: [:], token: appToken)
        guard let urlStr = result["url"] as? String, let url = URL(string: urlStr) else {
            throw SlackError.invalidResponse
        }
        return url
    }

    private func startReceiving() {
        guard let ws = webSocketTask else { return }
        ws.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self?.handleWebSocketMessage(message)
                    self?.startReceiving() // continue listening
                case .failure(let error):
                    Log.cloud.error("Slack WebSocket error: \(error.localizedDescription)")
                    self?.isConnected = false
                }
            }
        }
    }

    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let type = json["type"] as? String

        // Acknowledge envelope
        if let envelopeId = json["envelope_id"] as? String {
            acknowledgeEnvelope(envelopeId)
        }

        // Handle events_api type
        if type == "events_api",
           let payload = json["payload"] as? [String: Any],
           let event = payload["event"] as? [String: Any] {
            handleEvent(event)
        }
    }

    private func handleEvent(_ event: [String: Any]) {
        guard let eventType = event["type"] as? String else { return }

        switch eventType {
        case "message":
            // Skip bot's own messages
            if let botId = event["bot_id"] as? String, !botId.isEmpty { return }
            if let subtype = event["subtype"] as? String, subtype == "bot_message" { return }

            guard let channelId = event["channel"] as? String,
                  let text = event["text"] as? String,
                  let ts = event["ts"] as? String else { return }

            let userId = event["user"] as? String
            let threadTs = event["thread_ts"] as? String
            let isMention = botUserId.map { text.contains("<@\($0)>") } ?? false

            let slackMessage = SlackMessage(
                channelId: channelId,
                userId: userId,
                text: Self.cleanMentions(text),
                threadTs: threadTs,
                ts: ts,
                isMention: isMention
            )

            Log.cloud.debug("Slack message from \(userId ?? "unknown") in \(channelId)")
            onMessage?(slackMessage)

        case "app_mention":
            guard let channelId = event["channel"] as? String,
                  let text = event["text"] as? String,
                  let ts = event["ts"] as? String else { return }

            let userId = event["user"] as? String
            let threadTs = event["thread_ts"] as? String

            let slackMessage = SlackMessage(
                channelId: channelId,
                userId: userId,
                text: Self.cleanMentions(text),
                threadTs: threadTs,
                ts: ts,
                isMention: true
            )

            Log.cloud.debug("Slack mention from \(userId ?? "unknown") in \(channelId)")
            onMessage?(slackMessage)

        default:
            break
        }
    }

    private func acknowledgeEnvelope(_ envelopeId: String) {
        let ack: [String: Any] = ["envelope_id": envelopeId]
        guard let data = try? JSONSerialization.data(withJSONObject: ack),
              let str = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(str)) { error in
            if let error {
                Log.cloud.warning("Slack ack failed: \(error.localizedDescription)")
            }
        }
    }

    private func startPing() {
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                self?.webSocketTask?.sendPing { error in
                    if let error {
                        Log.cloud.warning("Slack ping failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    /// Remove <@U...> mention markers from text.
    nonisolated static func cleanMentions(_ text: String) -> String {
        // Replace <@UXXXXXX> patterns with empty string
        var result = text
        while let range = result.range(of: "<@[A-Z0-9]+>", options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private func apiCall(_ method: String, body: [String: Any], token: String) async throws -> [String: Any] {
        let url = URL(string: "https://slack.com/api/\(method)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        if !body.isEmpty {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SlackError.invalidResponse
        }
        guard json["ok"] as? Bool == true else {
            let errorStr = json["error"] as? String ?? "unknown"
            throw SlackError.apiError(errorStr)
        }
        return json
    }
}

// MARK: - Errors

enum SlackError: LocalizedError {
    case notConnected
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "슬랙에 연결되어 있지 않습니다."
        case .invalidResponse: "잘못된 API 응답입니다."
        case .apiError(let msg): "슬랙 API 오류: \(msg)"
        }
    }
}
