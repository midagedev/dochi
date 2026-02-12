import Foundation
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

private struct APIUpdate: Decodable {
    let updateId: Int64
    let message: APIMessage?

    enum CodingKeys: String, CodingKey {
        case updateId = "update_id"
        case message
    }
}

private struct APIMessage: Decodable {
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

private struct APIUser: Decodable {
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

private struct APIChat: Decodable {
    let id: Int64
    let type: String
}

private struct APISendMessageResult: Decodable {
    let messageId: Int64

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
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
    var onMessage: (@MainActor @Sendable (TelegramUpdate) -> Void)?

    private var token: String?
    private var pollingTask: Task<Void, Never>?
    private var lastUpdateId: Int64?

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
        lastUpdateId = nil

        Log.telegram.info("Telegram 폴링 시작")

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
        // offset 갱신
        lastUpdateId = apiUpdate.updateId

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
}
