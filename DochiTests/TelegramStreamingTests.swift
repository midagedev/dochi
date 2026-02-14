import CryptoKit
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

    // MARK: - Offset persistence

    func testOffsetKeyDiffersByToken() {
        // Two different tokens should produce different keys
        let key1 = offsetKey(for: "token_aaa")
        let key2 = offsetKey(for: "token_bbb")
        XCTAssertNotEqual(key1, key2)
        XCTAssertTrue(key1.hasPrefix("telegram_offset_"))
        XCTAssertTrue(key2.hasPrefix("telegram_offset_"))
    }

    func testOffsetKeySameForSameToken() {
        let key1 = offsetKey(for: "my_stable_token")
        let key2 = offsetKey(for: "my_stable_token")
        XCTAssertEqual(key1, key2)
    }

    func testOffsetSaveAndLoad() {
        let token = "test_offset_\(UUID().uuidString)"
        let key = offsetKey(for: token)

        // Clean up before test
        UserDefaults.standard.removeObject(forKey: key)

        // Initially nil
        XCTAssertNil(UserDefaults.standard.object(forKey: key))

        // Save
        UserDefaults.standard.set(Int64(12345), forKey: key)
        let loaded = UserDefaults.standard.object(forKey: key) as? Int64
        XCTAssertEqual(loaded, 12345)

        // Clean up
        UserDefaults.standard.removeObject(forKey: key)
    }

    func testOffsetKeyFormat() {
        let key = offsetKey(for: "123:ABCxyz")
        // Should be 16 hex chars after prefix
        let prefix = "telegram_offset_"
        XCTAssertTrue(key.hasPrefix(prefix))
        let hexPart = String(key.dropFirst(prefix.count))
        XCTAssertEqual(hexPart.count, 16) // 8 bytes = 16 hex chars
    }

    // Helper: replicates TelegramService.offsetKey logic for testing
    private func offsetKey(for token: String) -> String {
        let hash = SHA256.hash(data: Data(token.utf8))
        let prefix = hash.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "telegram_offset_\(prefix)"
    }
}
