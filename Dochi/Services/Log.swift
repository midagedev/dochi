import os

enum Log {
    static let app     = Logger(subsystem: "com.dochi.app", category: "App")
    static let llm     = Logger(subsystem: "com.dochi.app", category: "LLM")
    static let stt     = Logger(subsystem: "com.dochi.app", category: "STT")
    static let tts     = Logger(subsystem: "com.dochi.app", category: "TTS")
    static let mcp     = Logger(subsystem: "com.dochi.app", category: "MCP")
    static let tool    = Logger(subsystem: "com.dochi.app", category: "Tool")
    static let storage = Logger(subsystem: "com.dochi.app", category: "Storage")
    static let cloud   = Logger(subsystem: "com.dochi.app", category: "Cloud")
    static let telegram = Logger(subsystem: "com.dochi.app", category: "Telegram")
}

// MARK: - Telegram Service (temporarily inlined; move to its own file with XcodeGen inclusion later)

import Foundation
import CryptoKit

final class TelegramService: @unchecked Sendable {
    private let session: URLSession
    private let conversationService: ConversationServiceProtocol
    private let onConversationsChanged: (() -> Void)?

    struct DMEvent {
        let chatId: Int64
        let username: String?
        let text: String
    }

    var onDM: ((DMEvent) -> Void)?

    private var token: String = ""
    private var isRunning = false
    var running: Bool { isRunning }
    private var pollingTask: Task<Void, Never>?
    private var lastUpdateId: Int64 = 0
    var lastUpdateCheckpoint: Int64 { lastUpdateId }
    private let defaults = UserDefaults.standard
    private var processedMessageKeys = Set<String>()
    private(set) var lastErrorMessage: String?
    private(set) var lastDMAt: Date?
    private var offsetDefaultsKey: String { "telegram.lastUpdateId" } // fallback
    private func perTokenOffsetKey(_ token: String) -> String {
        guard let data = token.data(using: .utf8) else { return offsetDefaultsKey }
        let digest = SHA256.hash(data: data)
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
        return "telegram.lastUpdateId.\(hex.prefix(16))"
    }

    init(conversationService: ConversationServiceProtocol, onConversationsChanged: (() -> Void)? = nil) {
        self.conversationService = conversationService
        self.onConversationsChanged = onConversationsChanged
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    func start(token: String) {
        guard !token.isEmpty else { return }
        if isRunning && self.token == token { return }
        stop()
        self.token = token
        let key = perTokenOffsetKey(token)
        if let saved = defaults.object(forKey: key) as? Int64 {
            lastUpdateId = saved
        } else if let savedNum = defaults.object(forKey: key) as? NSNumber {
            lastUpdateId = savedNum.int64Value
        }
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

    private func baseURL(_ method: String) -> URL { URL(string: "https://api.telegram.org/bot\(token)/\(method)")! }

    private func pollLoop() async {
        while isRunning && !Task.isCancelled {
            do {
                var comps = URLComponents(url: baseURL("getUpdates"), resolvingAgainstBaseURL: false)!
                var q: [URLQueryItem] = []
                q.append(URLQueryItem(name: "timeout", value: "50"))
                q.append(URLQueryItem(name: "limit", value: "50"))
                if lastUpdateId > 0 { q.append(URLQueryItem(name: "offset", value: String(lastUpdateId + 1))) }
                q.append(URLQueryItem(name: "allowed_updates", value: "[\"message\"]"))
                comps.queryItems = q
                let url = comps.url!
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                let updates = try JSONDecoder().decode(UpdatesResponse.self, from: data)
                if updates.ok {
                    for update in updates.result {
                        lastUpdateId = max(lastUpdateId, update.update_id)
                        if let msg = update.message, msg.chat.type == "private", let text = msg.text {
                            let key = "\(msg.chat.id):\(msg.message_id)"
                            if processedMessageKeys.contains(key) { continue }
                            processedMessageKeys.insert(key)
                            if processedMessageKeys.count > 1000 {
                                let excess = processedMessageKeys.count - 1000
                                for _ in 0..<excess { if let first = processedMessageKeys.first { processedMessageKeys.remove(first) } }
                            }
                            lastDMAt = Date()
                            if let onDM { onDM(DMEvent(chatId: msg.chat.id, username: msg.from?.username, text: text)) }
                        }
                    }
                    let offKey = perTokenOffsetKey(token)
                    defaults.set(NSNumber(value: lastUpdateId), forKey: offKey)
                }
            } catch {
                lastErrorMessage = error.localizedDescription
                Log.telegram.warning("Polling error: \(error.localizedDescription, privacy: .public)")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
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
                lastErrorMessage = "sendMessage HTTP 실패"
                Log.telegram.warning("sendMessage HTTP 실패")
                return nil
            }
            if let res = try? JSONDecoder().decode(SendMessageResponse.self, from: data), res.ok {
                return res.result.message_id
            }
        } catch {
            lastErrorMessage = error.localizedDescription
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
                lastErrorMessage = "editMessageText HTTP 실패"
                Log.telegram.warning("editMessageText HTTP 실패")
                return
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            Log.telegram.warning("editMessageText 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    func sendPhoto(chatId: Int64, url: URL) async {
        if url.isFileURL {
            await sendLocalPhotoMultipart(chatId: chatId, fileURL: url)
            return
        }
        var request = URLRequest(url: baseURL("sendPhoto"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "chat_id": chatId,
            "photo": url.absoluteString
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                lastErrorMessage = "sendPhoto HTTP 실패(원격 URL)"
                Log.telegram.warning("sendPhoto HTTP 실패(원격 URL)")
                return
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            Log.telegram.warning("sendPhoto 실패(원격 URL): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func sendLocalPhotoMultipart(chatId: Int64, fileURL: URL) async {
        guard let data = try? Data(contentsOf: fileURL) else {
            lastErrorMessage = "sendPhoto: 파일 읽기 실패"
            Log.telegram.warning("sendPhoto: 로컬 파일을 읽을 수 없습니다: \(fileURL.path, privacy: .public)")
            return
        }
        let boundary = "----DochiBoundary_\(UUID().uuidString)"
        var request = URLRequest(url: baseURL("sendPhoto"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ string: String) { body.append(string.data(using: .utf8)!) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n")
        append("\(chatId)\r\n")
        append("--\(boundary)\r\n")
        let filename = fileURL.lastPathComponent
        let mime = filename.lowercased().hasSuffix(".png") ? "image/png" : "image/jpeg"
        append("Content-Disposition: form-data; name=\"photo\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mime)\r\n\r\n")
        body.append(data)
        append("\r\n")
        append("--\(boundary)--\r\n")
        request.httpBody = body

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                lastErrorMessage = "sendPhoto HTTP 실패(로컬 업로드)"
                Log.telegram.warning("sendPhoto HTTP 실패(로컬 업로드)")
                return
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            Log.telegram.warning("sendPhoto 실패(로컬 업로드): \(error.localizedDescription, privacy: .public)")
        }
    }

    func sendChatAction(chatId: Int64, action: String = "typing") async {
        var request = URLRequest(url: baseURL("sendChatAction"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "chat_id": chatId,
            "action": action
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                lastErrorMessage = "sendChatAction 실패"
                Log.telegram.warning("sendChatAction 실패: action=\(action)")
                return
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            Log.telegram.warning("sendChatAction 에러: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private struct GetMeResponse: Decodable { let ok: Bool; let result: TGUser }
private struct UpdatesResponse: Decodable { let ok: Bool; let result: [TGUpdate] }
private struct SendMessageResponse: Decodable { let ok: Bool; let result: TGMessage }
private struct TGUpdate: Decodable { let update_id: Int64; let message: TGMessage? }
private struct TGMessage: Decodable { let message_id: Int; let from: TGUser?; let chat: TGChat; let text: String? }
private struct TGUser: Decodable { let id: Int64; let is_bot: Bool; let first_name: String; let username: String? }
private struct TGChat: Decodable { let id: Int64; let type: String }
