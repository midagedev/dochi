import Foundation

/// An image to send in a Telegram media group.
struct TelegramMediaItem: Sendable {
    let filePath: String
    let caption: String?
}

/// Connection mode for Telegram bot.
enum TelegramConnectionMode: String, Codable, Sendable, CaseIterable {
    case polling
    case webhook

    var displayName: String {
        switch self {
        case .polling: "폴링"
        case .webhook: "웹훅"
        }
    }
}

/// Webhook configuration info returned by getWebhookInfo.
struct TelegramWebhookInfo: Sendable {
    let url: String
    let hasCustomCertificate: Bool
    let pendingUpdateCount: Int
    let lastErrorDate: Int?
    let lastErrorMessage: String?
}

@MainActor
protocol TelegramServiceProtocol {
    var isPolling: Bool { get }
    var isWebhookActive: Bool { get }
    func startPolling(token: String)
    func stopPolling()
    func startWebhook(token: String, url: String, port: UInt16) async throws
    func stopWebhook() async throws
    func setWebhook(token: String, url: String) async throws
    func deleteWebhook(token: String) async throws
    func getWebhookInfo(token: String) async throws -> TelegramWebhookInfo
    func sendMessage(chatId: Int64, text: String) async throws -> Int64
    func editMessage(chatId: Int64, messageId: Int64, text: String) async throws
    func sendChatAction(chatId: Int64, action: String) async throws
    func sendPhoto(chatId: Int64, filePath: String, caption: String?) async throws -> Int64
    func sendMediaGroup(chatId: Int64, items: [TelegramMediaItem]) async throws
    func getMe(token: String) async throws -> TelegramUser
    var onMessage: (@MainActor @Sendable (TelegramUpdate) -> Void)? { get set }
}
