import XCTest
@testable import Dochi

@MainActor
final class TelegramStreamingTests: XCTestCase {

    // MARK: - sendChatAction

    func testSendChatActionTracked() async throws {
        let tg = MockTelegramService()
        try await tg.sendChatAction(chatId: 123, action: "typing")
        XCTAssertEqual(tg.chatActions.count, 1)
        XCTAssertEqual(tg.chatActions[0].chatId, 123)
        XCTAssertEqual(tg.chatActions[0].action, "typing")
    }

    // MARK: - ShellPermissionConfig (reuse for quick smoke)

    func testTelegramStreamRepliesDefaultTrue() {
        let settings = AppSettings()
        XCTAssertTrue(settings.telegramStreamReplies)
    }

    // MARK: - Mock message tracking

    func testMockSendMessageReturnsIncrementingIds() async throws {
        let tg = MockTelegramService()
        let id1 = try await tg.sendMessage(chatId: 1, text: "a")
        let id2 = try await tg.sendMessage(chatId: 1, text: "b")
        XCTAssertEqual(id2, id1 + 1)
        XCTAssertEqual(tg.sentMessages.count, 2)
    }

    func testMockEditMessageTracked() async throws {
        let tg = MockTelegramService()
        try await tg.editMessage(chatId: 1, messageId: 100, text: "edited")
        XCTAssertEqual(tg.editedMessages.count, 1)
        XCTAssertEqual(tg.editedMessages[0].text, "edited")
    }

    func testMockGetMeReturnsBotUser() async throws {
        let tg = MockTelegramService()
        let user = try await tg.getMe(token: "test")
        XCTAssertTrue(user.isBot)
        XCTAssertEqual(user.firstName, "TestBot")
    }

    // MARK: - Protocol conformance

    func testMockConformsToProtocol() {
        let tg: TelegramServiceProtocol = MockTelegramService()
        XCTAssertFalse(tg.isPolling)
    }
}
