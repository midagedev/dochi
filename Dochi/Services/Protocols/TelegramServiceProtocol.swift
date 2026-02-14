import Foundation

/// An image to send in a Telegram media group.
struct TelegramMediaItem: Sendable {
    let filePath: String
    let caption: String?
}

@MainActor
protocol TelegramServiceProtocol {
    var isPolling: Bool { get }
    func startPolling(token: String)
    func stopPolling()
    func sendMessage(chatId: Int64, text: String) async throws -> Int64
    func editMessage(chatId: Int64, messageId: Int64, text: String) async throws
    func sendChatAction(chatId: Int64, action: String) async throws
    func sendPhoto(chatId: Int64, filePath: String, caption: String?) async throws -> Int64
    func sendMediaGroup(chatId: Int64, items: [TelegramMediaItem]) async throws
    func getMe(token: String) async throws -> TelegramUser
    var onMessage: (@MainActor @Sendable (TelegramUpdate) -> Void)? { get set }
}
