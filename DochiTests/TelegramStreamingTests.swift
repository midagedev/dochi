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

    // MARK: - Media Group

    func testMockSendPhotoTracked() async throws {
        let tg = MockTelegramService()
        let msgId = try await tg.sendPhoto(chatId: 42, filePath: "/tmp/test.png", caption: "테스트")
        XCTAssertEqual(tg.sentPhotos.count, 1)
        XCTAssertEqual(tg.sentPhotos[0].chatId, 42)
        XCTAssertEqual(tg.sentPhotos[0].filePath, "/tmp/test.png")
        XCTAssertEqual(tg.sentPhotos[0].caption, "테스트")
        XCTAssertEqual(msgId, 1000)
    }

    func testMockSendPhotoNilCaption() async throws {
        let tg = MockTelegramService()
        _ = try await tg.sendPhoto(chatId: 1, filePath: "/tmp/a.png", caption: nil)
        XCTAssertNil(tg.sentPhotos[0].caption)
    }

    func testMockSendMediaGroupTracked() async throws {
        let tg = MockTelegramService()
        let items = [
            TelegramMediaItem(filePath: "/tmp/a.png", caption: "A"),
            TelegramMediaItem(filePath: "/tmp/b.png", caption: nil),
        ]
        try await tg.sendMediaGroup(chatId: 99, items: items)
        XCTAssertEqual(tg.sentMediaGroups.count, 1)
        XCTAssertEqual(tg.sentMediaGroups[0].chatId, 99)
        XCTAssertEqual(tg.sentMediaGroups[0].items.count, 2)
        XCTAssertEqual(tg.sentMediaGroups[0].items[0].caption, "A")
        XCTAssertNil(tg.sentMediaGroups[0].items[1].caption)
    }

    func testTelegramMediaItemInit() {
        let item = TelegramMediaItem(filePath: "/tmp/photo.jpg", caption: "테스트 캡션")
        XCTAssertEqual(item.filePath, "/tmp/photo.jpg")
        XCTAssertEqual(item.caption, "테스트 캡션")
    }

    func testTelegramMediaItemNilCaption() {
        let item = TelegramMediaItem(filePath: "/tmp/photo.jpg", caption: nil)
        XCTAssertNil(item.caption)
    }

    // MARK: - Chat Mapping

    func testChatMappingStoreUpsertAndLoad() {
        let settings = AppSettings()
        settings.telegramChatMappingJSON = "[]" // Reset

        TelegramChatMappingStore.upsert(chatId: 123, label: "@user1", workspaceId: nil, in: settings)
        let mappings = TelegramChatMappingStore.loadMappings(from: settings)

        XCTAssertEqual(mappings.count, 1)
        XCTAssertEqual(mappings[0].chatId, 123)
        XCTAssertEqual(mappings[0].label, "@user1")
        XCTAssertTrue(mappings[0].enabled)

        // Clean up
        settings.telegramChatMappingJSON = "{}"
    }

    func testChatMappingStoreUpsertUpdatesExisting() {
        let settings = AppSettings()
        settings.telegramChatMappingJSON = "[]"

        TelegramChatMappingStore.upsert(chatId: 456, label: "old", workspaceId: nil, in: settings)
        TelegramChatMappingStore.upsert(chatId: 456, label: "new", workspaceId: nil, in: settings)

        let mappings = TelegramChatMappingStore.loadMappings(from: settings)
        XCTAssertEqual(mappings.count, 1)
        XCTAssertEqual(mappings[0].label, "new")

        settings.telegramChatMappingJSON = "{}"
    }

    func testChatMappingStoreRemove() {
        let settings = AppSettings()
        settings.telegramChatMappingJSON = "[]"

        TelegramChatMappingStore.upsert(chatId: 100, label: "a", workspaceId: nil, in: settings)
        TelegramChatMappingStore.upsert(chatId: 200, label: "b", workspaceId: nil, in: settings)
        TelegramChatMappingStore.remove(chatId: 100, from: settings)

        let mappings = TelegramChatMappingStore.loadMappings(from: settings)
        XCTAssertEqual(mappings.count, 1)
        XCTAssertEqual(mappings[0].chatId, 200)

        settings.telegramChatMappingJSON = "{}"
    }

    func testChatMappingCodable() throws {
        let mapping = TelegramChatMapping(
            chatId: 42,
            workspaceId: UUID(),
            label: "@test",
            enabled: false
        )

        let data = try JSONEncoder().encode(mapping)
        let decoded = try JSONDecoder().decode(TelegramChatMapping.self, from: data)

        XCTAssertEqual(decoded.chatId, 42)
        XCTAssertEqual(decoded.label, "@test")
        XCTAssertFalse(decoded.enabled)
        XCTAssertEqual(decoded.workspaceId, mapping.workspaceId)
    }

    func testIsTelegramHostDefault() {
        let settings = AppSettings()
        XCTAssertTrue(settings.isTelegramHost)
    }

    // MARK: - Connection Mode

    func testConnectionModeDefaultsToPolling() {
        let settings = AppSettings()
        XCTAssertEqual(
            TelegramConnectionMode(rawValue: settings.telegramConnectionMode),
            .polling
        )
    }

    func testConnectionModeDisplayNames() {
        XCTAssertEqual(TelegramConnectionMode.polling.displayName, "폴링")
        XCTAssertEqual(TelegramConnectionMode.webhook.displayName, "웹훅")
    }

    func testConnectionModeCodable() throws {
        for mode in TelegramConnectionMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(TelegramConnectionMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    // MARK: - Webhook Mock

    func testMockStartWebhook() async throws {
        let tg = MockTelegramService()
        XCTAssertFalse(tg.isWebhookActive)
        try await tg.startWebhook(token: "test", url: "https://example.com/webhook", port: 8443)
        XCTAssertTrue(tg.isWebhookActive)
        XCTAssertEqual(tg.webhookCalls.count, 1)
        XCTAssertEqual(tg.webhookCalls[0].url, "https://example.com/webhook")
    }

    func testMockStopWebhook() async throws {
        let tg = MockTelegramService()
        try await tg.startWebhook(token: "test", url: "https://example.com/webhook", port: 8443)
        try await tg.stopWebhook()
        XCTAssertFalse(tg.isWebhookActive)
    }

    func testMockSetWebhook() async throws {
        let tg = MockTelegramService()
        try await tg.setWebhook(token: "test", url: "https://example.com/webhook")
        XCTAssertEqual(tg.webhookCalls.count, 1)
    }

    func testMockDeleteWebhook() async throws {
        let tg = MockTelegramService()
        try await tg.deleteWebhook(token: "test") // Should not throw
    }

    func testMockGetWebhookInfo() async throws {
        let tg = MockTelegramService()
        let info = try await tg.getWebhookInfo(token: "test")
        XCTAssertEqual(info.url, "")
        XCTAssertEqual(info.pendingUpdateCount, 0)
    }

    // MARK: - Webhook Settings

    func testWebhookSettingsDefaults() {
        let settings = AppSettings()
        XCTAssertEqual(settings.telegramWebhookPort, 8443)
        XCTAssertEqual(settings.telegramWebhookURL, "")
    }

    // MARK: - WebhookInfo Model

    func testWebhookInfoInit() {
        let info = TelegramWebhookInfo(
            url: "https://example.com/webhook",
            hasCustomCertificate: false,
            pendingUpdateCount: 5,
            lastErrorDate: 1234567890,
            lastErrorMessage: "Connection refused"
        )
        XCTAssertEqual(info.url, "https://example.com/webhook")
        XCTAssertFalse(info.hasCustomCertificate)
        XCTAssertEqual(info.pendingUpdateCount, 5)
        XCTAssertEqual(info.lastErrorDate, 1234567890)
        XCTAssertEqual(info.lastErrorMessage, "Connection refused")
    }

    func testWebhookInfoNilErrors() {
        let info = TelegramWebhookInfo(
            url: "",
            hasCustomCertificate: false,
            pendingUpdateCount: 0,
            lastErrorDate: nil,
            lastErrorMessage: nil
        )
        XCTAssertNil(info.lastErrorDate)
        XCTAssertNil(info.lastErrorMessage)
    }

    // MARK: - HTTP Body Extraction

    func testExtractHTTPBody() {
        let httpData = "POST /webhook HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"update_id\":123}".data(using: .utf8)!
        let body = TelegramService.extractHTTPBody(from: httpData)
        XCTAssertNotNil(body)
        let bodyStr = String(data: body!, encoding: .utf8)
        XCTAssertEqual(bodyStr, "{\"update_id\":123}")
    }

    func testExtractHTTPBodyNoSeparator() {
        let data = "no separator here".data(using: .utf8)!
        let body = TelegramService.extractHTTPBody(from: data)
        XCTAssertNil(body)
    }

    func testExtractHTTPBodyEmptyBody() {
        let data = "HTTP/1.1 200 OK\r\n\r\n".data(using: .utf8)!
        let body = TelegramService.extractHTTPBody(from: data)
        XCTAssertNil(body)
    }

    // Helper: replicates TelegramService.offsetKey logic for testing
    private func offsetKey(for token: String) -> String {
        let hash = SHA256.hash(data: Data(token.utf8))
        let prefix = hash.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "telegram_offset_\(prefix)"
    }
}
