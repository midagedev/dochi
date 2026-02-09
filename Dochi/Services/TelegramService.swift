import Foundation

// Lightweight Telegram Bot long-polling service
// - Starts a getUpdates loop when enabled and token present
// - Saves incoming DM messages to ConversationService
// - Sends a simple ACK reply to confirm connectivity (MVP)

final class TelegramService {
    private let session: URLSession
    private let conversationService: ConversationServiceProtocol
    private let onConversationsChanged: (() -> Void)?

    struct DMEvent {
        let chatId: Int64
        let username: String?
        let text: String
    }

    // If set, DM events are delegated to the app layer (ViewModel)
    // Otherwise, the service falls back to simple ACK + local logging.
    var onDM: ((DMEvent) -> Void)?

    private var token: String = ""
    private var isRunning = false
    private var pollingTask: Task<Void, Never>?
    private var lastUpdateId: Int64 = 0

    init(conversationService: ConversationServiceProtocol, onConversationsChanged: (() -> Void)? = nil) {
        self.conversationService = conversationService
        self.onConversationsChanged = onConversationsChanged
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    // MARK: - Control

    func start(token: String) {
        guard !token.isEmpty else { return }
        stop()
        self.token = token
        isRunning = true
        pollingTask = Task { [weak self] in
            await self?.pollLoop()
        }
        Log.telegram.info("Telegram polling started")
    }

    func stop() {
        isRunning = false
        pollingTask?.cancel()
        pollingTask = nil
        Log.telegram.info("Telegram polling stopped")
    }

    // MARK: - API

    func getMe(token: String) async throws -> String {
        let url = URL(string: "https://api.telegram.org/bot\(token)/getMe")!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "Telegram", code: 1, userInfo: [NSLocalizedDescriptionKey: "getMe 실패"])
        }
        let res = try JSONDecoder().decode(GetMeResponse.self, from: data)
        guard res.ok else { throw NSError(domain: "Telegram", code: 2, userInfo: [NSLocalizedDescriptionKey: "응답 ok=false"]) }
        return res.result.username ?? res.result.first_name
    }

    // MARK: - Polling

    private func baseURL(_ method: String) -> URL { URL(string: "https://api.telegram.org/bot\(token)/\(method)")! }

    private func pollLoop() async {
        while isRunning && !Task.isCancelled {
            do {
                var comps = URLComponents(url: baseURL("getUpdates"), resolvingAgainstBaseURL: false)!
                comps.queryItems = [
                    URLQueryItem(name: "timeout", value: "50"),
                    URLQueryItem(name: "offset", value: lastUpdateId == 0 ? nil : String(lastUpdateId + 1))
                ]
                let url = comps.url!
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                let updates = try JSONDecoder().decode(UpdatesResponse.self, from: data)
                if updates.ok {
                    for update in updates.result {
                        lastUpdateId = max(lastUpdateId, update.update_id)
                        if let msg = update.message, msg.chat.type == "private", let text = msg.text {
                            if let onDM {
                                onDM(DMEvent(chatId: msg.chat.id, username: msg.from?.username, text: text))
                            } else {
                                await handleIncomingDM(chatId: msg.chat.id, username: msg.from?.username, text: text)
                            }
                        }
                    }
                }
            } catch {
                Log.telegram.warning("Polling error: \(error.localizedDescription, privacy: .public)")
                // brief backoff
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    @MainActor
    private func handleIncomingDM(chatId: Int64, username: String?, text: String) async {
        Log.telegram.info("DM from \(username ?? String(chatId), privacy: .public): \(text, privacy: .public)")
        let userKey = "tg:\(chatId)"
        let existing = conversationService.list().first { $0.userId == userKey }
        var conv = existing ?? Conversation(
            title: "Telegram DM \(username ?? String(chatId))",
            messages: [],
            userId: userKey
        )
        conv.messages.append(Message(role: .user, content: text))

        // MVP: simple acknowledgment
        let reply = "메시지 받았어요: \(text)"
        conv.messages.append(Message(role: .assistant, content: reply))
        conv.updatedAt = Date()
        conversationService.save(conv)
        onConversationsChanged?()

        Task.detached { [token] in
            await self.sendMessage(chatId: chatId, text: reply)
        }
    }

    @discardableResult
    func sendMessage(chatId: Int64, text: String) async -> Int? {
        var request = URLRequest(url: baseURL("sendMessage"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["chat_id": chatId, "text": text]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                Log.telegram.warning("sendMessage HTTP 실패")
                return nil
            }
            if let res = try? JSONDecoder().decode(SendMessageResponse.self, from: data), res.ok {
                return res.result.message_id
            }
        } catch {
            Log.telegram.warning("sendMessage 실패: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    func editMessageText(chatId: Int64, messageId: Int, text: String) async {
        var request = URLRequest(url: baseURL("editMessageText"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "chat_id": chatId,
            "message_id": messageId,
            "text": text
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                Log.telegram.warning("editMessageText HTTP 실패")
                return
            }
        } catch {
            Log.telegram.warning("editMessageText 실패: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Models

private struct GetMeResponse: Decodable {
    let ok: Bool
    let result: TGUser
}

private struct UpdatesResponse: Decodable {
    let ok: Bool
    let result: [TGUpdate]
}

private struct TGUpdate: Decodable {
    let update_id: Int64
    let message: TGMessage?
}

private struct TGMessage: Decodable {
    let message_id: Int
    let from: TGUser?
    let chat: TGChat
    let text: String?
}

private struct TGUser: Decodable {
    let id: Int64
    let is_bot: Bool
    let first_name: String
    let username: String?
}

private struct TGChat: Decodable {
    let id: Int64
    let type: String
}

private struct SendMessageResponse: Decodable {
    let ok: Bool
    let result: TGMessage
}
