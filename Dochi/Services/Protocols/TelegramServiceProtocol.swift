import Foundation

@MainActor
protocol TelegramServiceProtocol {
    var isPolling: Bool { get }
    func startPolling(token: String)
    func stopPolling()
    func sendMessage(chatId: Int64, text: String) async throws -> Int64
    func editMessage(chatId: Int64, messageId: Int64, text: String) async throws
    func getMe(token: String) async throws -> TelegramUser
    var onMessage: (@MainActor @Sendable (TelegramUpdate) -> Void)? { get set }
}
