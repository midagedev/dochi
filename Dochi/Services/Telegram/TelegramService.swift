import CryptoKit
import Foundation
import Network
import os

// MARK: - Models

struct TelegramUser: Codable, Sendable {
    let id: Int64
    let isBot: Bool
    let firstName: String
    let username: String?

    enum CodingKeys: String, CodingKey {
        case id
        case isBot = "is_bot"
        case firstName = "first_name"
        case username
    }
}

struct TelegramUpdate: Sendable {
    let updateId: Int64
    let chatId: Int64
    let senderId: Int64
    let senderUsername: String?
    let text: String
}

// MARK: - Error

enum TelegramError: Error, LocalizedError {
    case invalidToken
    case networkError(String)
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            "유효하지 않은 Telegram 봇 토큰"
        case .networkError(let message):
            "네트워크 오류: \(message)"
        case .apiError(let code, let description):
            "Telegram API 오류 (\(code)): \(description)"
        }
    }
}

// MARK: - API Response Models

private struct TelegramResponse<T: Decodable>: Decodable {
    let ok: Bool
    let result: T?
    let errorCode: Int?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case result
        case errorCode = "error_code"
        case description
    }
}

struct APIUpdate: Decodable {
    let updateId: Int64
    let message: APIMessage?

    enum CodingKeys: String, CodingKey {
        case updateId = "update_id"
        case message
    }
}

struct APIMessage: Decodable {
    let messageId: Int64
    let from: APIUser?
    let chat: APIChat
    let text: String?

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case from
        case chat
        case text
    }
}

struct APIUser: Decodable {
    let id: Int64
    let isBot: Bool
    let firstName: String
    let username: String?

    enum CodingKeys: String, CodingKey {
        case id
        case isBot = "is_bot"
        case firstName = "first_name"
        case username
    }
}

struct APIChat: Decodable {
    let id: Int64
    let type: String
}

private struct APISendMessageResult: Decodable {
    let messageId: Int64

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
    }
}

private struct WebhookInfoResult: Decodable {
    let url: String
    let hasCustomCertificate: Bool
    let pendingUpdateCount: Int
    let lastErrorDate: Int?
    let lastErrorMessage: String?

    enum CodingKeys: String, CodingKey {
        case url
        case hasCustomCertificate = "has_custom_certificate"
        case pendingUpdateCount = "pending_update_count"
        case lastErrorDate = "last_error_date"
        case lastErrorMessage = "last_error_message"
    }
}

// MARK: - Constants

private enum TelegramConstants {
    static let baseURL = "https://api.telegram.org/bot"
    static let pollTimeout = 30
    static let reconnectDelay: UInt64 = 5_000_000_000 // 5초 (nanoseconds)
}

// MARK: - TelegramService

@MainActor
final class TelegramService: TelegramServiceProtocol {

    // MARK: - Properties

    private(set) var isPolling = false
    private(set) var isWebhookActive = false
    var onMessage: (@MainActor @Sendable (TelegramUpdate) -> Void)?

    private var token: String?
    private var pollingTask: Task<Void, Never>?
    private var lastUpdateId: Int64?
    private var webhookListener: NWListener?

    private let session: URLSession

    // MARK: - Init

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = TimeInterval(TelegramConstants.pollTimeout + 10)
        self.session = URLSession(configuration: config)
    }

    // MARK: - Polling

    func startPolling(token: String) {
        guard !isPolling else {
            Log.telegram.warning("폴링이 이미 실행 중")
            return
        }

        self.token = token
        isPolling = true
        lastUpdateId = Self.loadOffset(for: token)

        let offsetStr = lastUpdateId.map(String.init) ?? "nil"
        Log.telegram.info("Telegram 폴링 시작 (offset: \(offsetStr))")

        pollingTask = Task.detached { [weak self] in
            await self?.pollLoop()
        }
    }

    func stopPolling() {
        guard isPolling else { return }

        Log.telegram.info("Telegram 폴링 중지")
        isPolling = false
        pollingTask?.cancel()
        pollingTask = nil
        token = nil
    }

    // MARK: - API Methods

    func sendMessage(chatId: Int64, text: String) async throws -> Int64 {
        guard let token else { throw TelegramError.invalidToken }

        let params: [String: Any] = [
            "chat_id": chatId,
            "text": text,
            "parse_mode": "Markdown"
        ]

        let result: APISendMessageResult = try await callAPI(
            token: token,
            method: "sendMessage",
            params: params
        )

        Log.telegram.debug("메시지 전송 완료: chatId=\(chatId), messageId=\(result.messageId)")
        return result.messageId
    }

    func editMessage(chatId: Int64, messageId: Int64, text: String) async throws {
        guard let token else { throw TelegramError.invalidToken }

        let params: [String: Any] = [
            "chat_id": chatId,
            "message_id": messageId,
            "text": text,
            "parse_mode": "Markdown"
        ]

        let _: APISendMessageResult = try await callAPI(
            token: token,
            method: "editMessageText",
            params: params
        )

        Log.telegram.debug("메시지 수정 완료: chatId=\(chatId), messageId=\(messageId)")
    }

    func sendChatAction(chatId: Int64, action: String) async throws {
        guard let token else { throw TelegramError.invalidToken }

        let params: [String: Any] = [
            "chat_id": chatId,
            "action": action
        ]

        struct BoolResult: Decodable {
            // sendChatAction returns true on success, wrapped in TelegramResponse
        }

        let _: Bool = try await callAPI(
            token: token,
            method: "sendChatAction",
            params: params
        )
    }

    func sendPhoto(chatId: Int64, filePath: String, caption: String?) async throws -> Int64 {
        guard let token else { throw TelegramError.invalidToken }

        let result: APISendMessageResult = try await uploadFile(
            token: token,
            method: "sendPhoto",
            chatId: chatId,
            fieldName: "photo",
            filePath: filePath,
            caption: caption
        )

        Log.telegram.debug("사진 전송 완료: chatId=\(chatId), messageId=\(result.messageId)")
        return result.messageId
    }

    func sendMediaGroup(chatId: Int64, items: [TelegramMediaItem]) async throws {
        guard let token else { throw TelegramError.invalidToken }
        guard !items.isEmpty else { return }

        // Telegram limits media groups to 2-10 items
        let limited = Array(items.prefix(10))

        // If only 1 item, use sendPhoto instead
        if limited.count == 1 {
            _ = try await sendPhoto(chatId: chatId, filePath: limited[0].filePath, caption: limited[0].caption)
            return
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let urlString = "\(TelegramConstants.baseURL)\(token)/sendMediaGroup"
        guard let url = URL(string: urlString) else {
            throw TelegramError.invalidToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        var mediaArray: [[String: Any]] = []

        for (index, item) in limited.enumerated() {
            let fieldName = "photo\(index)"
            mediaArray.append({
                var m: [String: Any] = [
                    "type": "photo",
                    "media": "attach://\(fieldName)",
                ]
                if let caption = item.caption {
                    m["caption"] = caption
                }
                return m
            }())

            // Attach file data
            guard let fileData = FileManager.default.contents(atPath: item.filePath) else {
                Log.telegram.warning("미디어 그룹: 파일 읽기 실패 \(item.filePath)")
                continue
            }
            let fileName = (item.filePath as NSString).lastPathComponent
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
        }

        // Add chat_id field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(chatId)\r\n".data(using: .utf8)!)

        // Add media JSON array field
        let mediaJSON = try JSONSerialization.data(withJSONObject: mediaArray)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"media\"\r\n\r\n".data(using: .utf8)!)
        body.append(mediaJSON)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            Log.telegram.error("미디어 그룹 전송 실패: \(errorBody)")
            throw TelegramError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0, errorBody)
        }

        Log.telegram.info("미디어 그룹 전송 완료: chatId=\(chatId), \(limited.count)장")
    }

    // MARK: - Private: File Upload

    private nonisolated func uploadFile(
        token: String,
        method: String,
        chatId: Int64,
        fieldName: String,
        filePath: String,
        caption: String?
    ) async throws -> APISendMessageResult {
        let boundary = "Boundary-\(UUID().uuidString)"
        let urlString = "\(TelegramConstants.baseURL)\(token)/\(method)"
        guard let url = URL(string: urlString) else {
            throw TelegramError.invalidToken
        }

        guard let fileData = FileManager.default.contents(atPath: filePath) else {
            throw TelegramError.networkError("파일을 읽을 수 없습니다: \(filePath)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // chat_id field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(chatId)\r\n".data(using: .utf8)!)

        // File field
        let fileName = (filePath as NSString).lastPathComponent
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        // Caption field (optional)
        if let caption, !caption.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"caption\"\r\n\r\n".data(using: .utf8)!)
            body.append(caption.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TelegramError.networkError("잘못된 HTTP 응답")
        }

        let decoded: TelegramResponse<APISendMessageResult>
        do {
            decoded = try JSONDecoder().decode(TelegramResponse<APISendMessageResult>.self, from: data)
        } catch {
            throw TelegramError.networkError("JSON 파싱 실패: \(error.localizedDescription)")
        }

        guard decoded.ok, let result = decoded.result else {
            let code = decoded.errorCode ?? httpResponse.statusCode
            let desc = decoded.description ?? "알 수 없는 오류"
            throw TelegramError.apiError(code, desc)
        }

        return result
    }

    func getMe(token: String) async throws -> TelegramUser {
        let apiUser: APIUser = try await callAPI(
            token: token,
            method: "getMe",
            params: nil
        )

        Log.telegram.info("봇 정보 확인: \(apiUser.firstName) (@\(apiUser.username ?? "없음"))")

        return TelegramUser(
            id: apiUser.id,
            isBot: apiUser.isBot,
            firstName: apiUser.firstName,
            username: apiUser.username
        )
    }

    // MARK: - Webhook API

    func setWebhook(token: String, url: String) async throws {
        let params: [String: Any] = [
            "url": url,
            "allowed_updates": ["message"],
        ]
        let _: Bool = try await callAPI(token: token, method: "setWebhook", params: params)
        Log.telegram.info("웹훅 설정 완료: \(url)")
    }

    func deleteWebhook(token: String) async throws {
        let _: Bool = try await callAPI(token: token, method: "deleteWebhook", params: nil)
        Log.telegram.info("웹훅 삭제 완료")
    }

    func getWebhookInfo(token: String) async throws -> TelegramWebhookInfo {
        let info: WebhookInfoResult = try await callAPI(token: token, method: "getWebhookInfo", params: nil)
        return TelegramWebhookInfo(
            url: info.url,
            hasCustomCertificate: info.hasCustomCertificate,
            pendingUpdateCount: info.pendingUpdateCount,
            lastErrorDate: info.lastErrorDate,
            lastErrorMessage: info.lastErrorMessage
        )
    }

    // MARK: - Webhook Server

    func startWebhook(token: String, url: String, port: UInt16) async throws {
        guard !isWebhookActive else {
            Log.telegram.warning("웹훅 서버가 이미 실행 중")
            return
        }

        // Stop polling if active
        if isPolling { stopPolling() }

        self.token = token

        // Set webhook on Telegram's side
        try await setWebhook(token: token, url: url)

        // Start local HTTP listener
        let params = NWParameters.tcp
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        self.webhookListener = listener

        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    Log.telegram.info("웹훅 서버 시작: 포트 \(port)")
                    self?.isWebhookActive = true
                case .failed(let error):
                    Log.telegram.error("웹훅 서버 실패: \(error.localizedDescription)")
                    self?.isWebhookActive = false
                case .cancelled:
                    Log.telegram.info("웹훅 서버 중지")
                    self?.isWebhookActive = false
                default:
                    break
                }
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleWebhookConnection(connection)
        }

        listener.start(queue: .global(qos: .userInteractive))
        isWebhookActive = true
    }

    func stopWebhook() async throws {
        webhookListener?.cancel()
        webhookListener = nil
        isWebhookActive = false

        if let token {
            try await deleteWebhook(token: token)
        }

        Log.telegram.info("웹훅 중지 완료")
    }

    private nonisolated func handleWebhookConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInteractive))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            defer {
                // Send 200 OK response
                let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }

            guard let data, error == nil else {
                Log.telegram.warning("웹훅 연결 오류: \(error?.localizedDescription ?? "데이터 없음")")
                return
            }

            // Parse HTTP body from raw TCP data
            guard let bodyData = Self.extractHTTPBody(from: data) else {
                return
            }

            // Decode Telegram update
            let decoder = JSONDecoder()
            guard let apiUpdate = try? decoder.decode(APIUpdate.self, from: bodyData) else {
                Log.telegram.warning("웹훅 JSON 파싱 실패")
                return
            }

            Task { @MainActor in
                self?.handleUpdate(apiUpdate)
            }
        }
    }

    /// Extracts the HTTP body from raw TCP data by finding the \r\n\r\n separator.
    nonisolated static func extractHTTPBody(from data: Data) -> Data? {
        let separator = "\r\n\r\n".data(using: .utf8)!
        guard let range = data.range(of: separator) else { return nil }
        let body = data[range.upperBound...]
        return body.isEmpty ? nil : Data(body)
    }

    // MARK: - Private: Poll Loop

    private nonisolated func pollLoop() async {
        while !Task.isCancelled {
            let shouldContinue = await self.isPolling
            guard shouldContinue else { break }

            do {
                let updates = try await fetchUpdates()
                for update in updates {
                    await handleUpdate(update)
                }
            } catch is CancellationError {
                break
            } catch {
                Log.telegram.error("폴링 오류: \(error.localizedDescription)")

                let stillPolling = await self.isPolling
                guard stillPolling else { break }
                Log.telegram.info("5초 후 재연결 시도")

                do {
                    try await Task.sleep(nanoseconds: TelegramConstants.reconnectDelay)
                } catch {
                    break
                }
            }
        }

        Log.telegram.info("폴링 루프 종료")
        await MainActor.run { [weak self] in
            self?.isPolling = false
        }
    }

    private nonisolated func fetchUpdates() async throws -> [APIUpdate] {
        let token = await self.token
        guard let token else {
            throw TelegramError.invalidToken
        }

        var params: [String: Any] = [
            "timeout": TelegramConstants.pollTimeout,
            "allowed_updates": ["message"]
        ]

        let currentOffset = await self.lastUpdateId
        if let currentOffset {
            params["offset"] = currentOffset + 1
        }

        let updates: [APIUpdate] = try await callAPI(
            token: token,
            method: "getUpdates",
            params: params
        )

        return updates
    }

    @MainActor
    private func handleUpdate(_ apiUpdate: APIUpdate) {
        // offset 갱신 및 영속화
        lastUpdateId = apiUpdate.updateId
        if let token {
            Self.saveOffset(apiUpdate.updateId, for: token)
        }

        // 텍스트 메시지만 처리 (DM)
        guard let message = apiUpdate.message,
              let text = message.text,
              message.chat.type == "private" else {
            return
        }

        // 봇 메시지 무시
        if message.from?.isBot == true {
            return
        }

        let update = TelegramUpdate(
            updateId: apiUpdate.updateId,
            chatId: message.chat.id,
            senderId: message.from?.id ?? 0,
            senderUsername: message.from?.username,
            text: text
        )

        Log.telegram.info("DM 수신: updateId=\(update.updateId), from=\(update.senderUsername ?? "알 수 없음")")
        onMessage?(update)
    }

    // MARK: - Private: API Call

    private nonisolated func callAPI<T: Decodable>(
        token: String,
        method: String,
        params: [String: Any]?
    ) async throws -> T {
        let urlString = "\(TelegramConstants.baseURL)\(token)/\(method)"
        guard let url = URL(string: urlString) else {
            throw TelegramError.invalidToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let params {
            request.httpBody = try JSONSerialization.data(withJSONObject: params)
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TelegramError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TelegramError.networkError("잘못된 HTTP 응답")
        }

        let decoded: TelegramResponse<T>
        do {
            decoded = try JSONDecoder().decode(TelegramResponse<T>.self, from: data)
        } catch {
            throw TelegramError.networkError("JSON 파싱 실패: \(error.localizedDescription)")
        }

        guard decoded.ok, let result = decoded.result else {
            let code = decoded.errorCode ?? httpResponse.statusCode
            let desc = decoded.description ?? "알 수 없는 오류"

            if code == 401 {
                throw TelegramError.invalidToken
            }
            throw TelegramError.apiError(code, desc)
        }

        return result
    }

    // MARK: - Offset Persistence

    private static func offsetKey(for token: String) -> String {
        let hash = SHA256.hash(data: Data(token.utf8))
        let prefix = hash.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "telegram_offset_\(prefix)"
    }

    private static func loadOffset(for token: String) -> Int64? {
        let key = offsetKey(for: token)
        let value = UserDefaults.standard.object(forKey: key) as? Int64
        if let value {
            Log.telegram.debug("Loaded persisted offset \(value) for token")
        }
        return value
    }

    private static func saveOffset(_ offset: Int64, for token: String) {
        let key = offsetKey(for: token)
        UserDefaults.standard.set(offset, forKey: key)
    }
}
