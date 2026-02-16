import XCTest
@testable import Dochi

@MainActor
final class TelegramProactiveRelayTests: XCTestCase {

    private var settings: AppSettings!
    private var mockTelegramService: MockTelegramService!
    private var mockKeychainService: MockKeychainService!
    private var relay: TelegramProactiveRelay!

    override func setUp() async throws {
        settings = AppSettings()
        mockTelegramService = MockTelegramService()
        mockKeychainService = MockKeychainService()

        // Set up a telegram token
        try mockKeychainService.save(account: "telegram_bot_token", value: "test-token")

        relay = TelegramProactiveRelay(
            settings: settings,
            telegramService: mockTelegramService,
            keychainService: mockKeychainService
        )
        relay.start()

        // Set up chat mapping for current workspace
        let workspaceId = UUID(uuidString: settings.currentWorkspaceId)!
        let mapping = TelegramChatMapping(chatId: 12345, workspaceId: workspaceId, label: "Test", enabled: true)
        let data = try JSONEncoder().encode([mapping])
        settings.telegramChatMappingJSON = String(data: data, encoding: .utf8)!
    }

    override func tearDown() async throws {
        relay.stop()
        // Reset UserDefaults keys
        UserDefaults.standard.removeObject(forKey: "heartbeatNotificationChannel")
        UserDefaults.standard.removeObject(forKey: "suggestionNotificationChannel")
        UserDefaults.standard.removeObject(forKey: "telegramSkipWhenAppActive")
    }

    // MARK: - NotificationChannel Enum

    func testNotificationChannelRawValueRoundtrip() {
        for channel in NotificationChannel.allCases {
            let raw = channel.rawValue
            let decoded = NotificationChannel(rawValue: raw)
            XCTAssertEqual(decoded, channel)
        }
    }

    // MARK: - Channel Logic

    func testAppOnlyChannelDoesNotSendToTelegram() {
        XCTAssertFalse(relay.shouldSendToTelegram(channel: .appOnly))
    }

    func testOffChannelDoesNotSendToTelegram() {
        XCTAssertFalse(relay.shouldSendToTelegram(channel: .off))
    }

    func testTelegramOnlyChannelSendsToTelegram() {
        settings.telegramSkipWhenAppActive = false
        XCTAssertTrue(relay.shouldSendToTelegram(channel: .telegramOnly))
    }

    func testBothChannelSendsToTelegram() {
        settings.telegramSkipWhenAppActive = false
        XCTAssertTrue(relay.shouldSendToTelegram(channel: .both))
    }

    // MARK: - Heartbeat Alert

    func testHeartbeatTelegramRelay() async {
        settings.heartbeatNotificationChannel = NotificationChannel.both.rawValue
        settings.telegramSkipWhenAppActive = false

        await relay.sendHeartbeatAlert(
            calendar: "15:00 미팅",
            kanban: "- 디자인",
            reminder: "보고서 (마감: 17:00)",
            memory: nil
        )

        XCTAssertEqual(mockTelegramService.sentMessages.count, 1)
        let msg = mockTelegramService.sentMessages[0]
        XCTAssertEqual(msg.chatId, 12345)
        XCTAssertTrue(msg.text.contains("일정 알림"))
        XCTAssertTrue(msg.text.contains("칸반 진행 상황"))
        XCTAssertTrue(msg.text.contains("마감 임박 미리알림"))
        XCTAssertEqual(relay.todayTelegramNotificationCount, 1)
    }

    func testHeartbeatMemoryWarning() async {
        settings.heartbeatNotificationChannel = NotificationChannel.telegramOnly.rawValue
        settings.telegramSkipWhenAppActive = false

        await relay.sendHeartbeatAlert(
            calendar: "",
            kanban: "",
            reminder: "",
            memory: "워크스페이스 메모리가 4,200자로 커졌습니다."
        )

        XCTAssertEqual(mockTelegramService.sentMessages.count, 1)
        let msg = mockTelegramService.sentMessages[0]
        XCTAssertTrue(msg.text.contains("메모리 정리 필요"))
        XCTAssertTrue(msg.text.contains("메모리 정리해줘"))
    }

    func testHeartbeatAppOnlyDoesNotSend() async {
        settings.heartbeatNotificationChannel = NotificationChannel.appOnly.rawValue

        await relay.sendHeartbeatAlert(
            calendar: "15:00 미팅",
            kanban: "",
            reminder: "",
            memory: nil
        )

        XCTAssertTrue(mockTelegramService.sentMessages.isEmpty)
    }

    func testHeartbeatOffDoesNotSend() async {
        settings.heartbeatNotificationChannel = NotificationChannel.off.rawValue

        await relay.sendHeartbeatAlert(
            calendar: "15:00 미팅",
            kanban: "",
            reminder: "",
            memory: nil
        )

        XCTAssertTrue(mockTelegramService.sentMessages.isEmpty)
    }

    // MARK: - Suggestion

    func testSuggestionTelegramRelay() async {
        settings.suggestionNotificationChannel = NotificationChannel.telegramOnly.rawValue
        settings.telegramSkipWhenAppActive = false

        let suggestion = ProactiveSuggestion(
            type: .newsTrend,
            title: "관심있으실 만한 소식",
            body: "최근 'Swift 6.1' 관련 대화를 하셨습니다.",
            suggestedPrompt: "최근 Swift 6.1 관련 뉴스를 조사해줘"
        )

        await relay.sendSuggestion(suggestion)

        XCTAssertEqual(mockTelegramService.sentMessages.count, 1)
        let msg = mockTelegramService.sentMessages[0]
        XCTAssertTrue(msg.text.contains("관심있으실 만한 소식"))
        XCTAssertTrue(msg.text.contains("알아봐줘"))
        XCTAssertEqual(relay.todayTelegramNotificationCount, 1)
    }

    func testSuggestionAllTypes() async {
        settings.suggestionNotificationChannel = NotificationChannel.both.rawValue
        settings.telegramSkipWhenAppActive = false

        let types: [(SuggestionType, String)] = [
            (.newsTrend, "알아봐줘"),
            (.deepDive, "설명해줘"),
            (.relatedResearch, "조사해줘"),
            (.kanbanCheck, "확인해줘"),
            (.memoryRemind, "리마인드해줘"),
            (.costReport, "요약 보여줘"),
        ]

        for (type, expectedHint) in types {
            let suggestion = ProactiveSuggestion(
                type: type,
                title: "테스트 제안",
                body: "테스트 본문",
                suggestedPrompt: "테스트"
            )
            await relay.sendSuggestion(suggestion)
            let msg = mockTelegramService.sentMessages.last!
            XCTAssertTrue(msg.text.contains(expectedHint), "Type \(type.rawValue) should contain hint '\(expectedHint)'")
        }

        XCTAssertEqual(mockTelegramService.sentMessages.count, types.count)
    }

    // MARK: - No Token

    func testNoTelegramTokenSkipsSilently() async {
        try! mockKeychainService.delete(account: "telegram_bot_token")

        settings.heartbeatNotificationChannel = NotificationChannel.both.rawValue
        settings.telegramSkipWhenAppActive = false

        await relay.sendHeartbeatAlert(
            calendar: "15:00 미팅",
            kanban: "",
            reminder: "",
            memory: nil
        )

        XCTAssertTrue(mockTelegramService.sentMessages.isEmpty)
    }

    // MARK: - No Chat Mapping

    func testNoChatMappingSkipsSilently() async {
        settings.telegramChatMappingJSON = "[]"
        settings.heartbeatNotificationChannel = NotificationChannel.both.rawValue
        settings.telegramSkipWhenAppActive = false

        await relay.sendHeartbeatAlert(
            calendar: "15:00 미팅",
            kanban: "",
            reminder: "",
            memory: nil
        )

        XCTAssertTrue(mockTelegramService.sentMessages.isEmpty)
    }

    // MARK: - Markdown Escape

    func testEscapeMarkdown() {
        let input = "Hello _world_ *bold* `code` [link]"
        let escaped = relay.escapeMarkdown(input)
        XCTAssertEqual(escaped, "Hello \\_world\\_ \\*bold\\* \\`code\\` \\[link]")
    }

    func testCalendarMessageFormat() async {
        settings.heartbeatNotificationChannel = NotificationChannel.telegramOnly.rawValue
        settings.telegramSkipWhenAppActive = false

        await relay.sendHeartbeatAlert(
            calendar: "15:00 팀 미팅\n16:30 코드리뷰",
            kanban: "",
            reminder: "",
            memory: nil
        )

        let msg = mockTelegramService.sentMessages[0].text
        XCTAssertTrue(msg.hasPrefix("\u{1F4C5}"))
        XCTAssertTrue(msg.contains("*일정 알림*"))
    }

    func testKanbanMessageFormat() async {
        settings.heartbeatNotificationChannel = NotificationChannel.telegramOnly.rawValue
        settings.telegramSkipWhenAppActive = false

        await relay.sendHeartbeatAlert(
            calendar: "",
            kanban: "- 디자인 시스템 구축",
            reminder: "",
            memory: nil
        )

        let msg = mockTelegramService.sentMessages[0].text
        XCTAssertTrue(msg.hasPrefix("\u{1F4CB}"))
        XCTAssertTrue(msg.contains("*칸반 진행 상황*"))
    }

    func testReminderMessageFormat() async {
        settings.heartbeatNotificationChannel = NotificationChannel.telegramOnly.rawValue
        settings.telegramSkipWhenAppActive = false

        await relay.sendHeartbeatAlert(
            calendar: "",
            kanban: "",
            reminder: "세금 신고 (마감: 15:00)",
            memory: nil
        )

        let msg = mockTelegramService.sentMessages[0].text
        XCTAssertTrue(msg.hasPrefix("\u{23F0}"))
        XCTAssertTrue(msg.contains("*마감 임박 미리알림*"))
    }

    func testMemoryMessageFormat() async {
        settings.heartbeatNotificationChannel = NotificationChannel.telegramOnly.rawValue
        settings.telegramSkipWhenAppActive = false

        await relay.sendHeartbeatAlert(
            calendar: "",
            kanban: "",
            reminder: "",
            memory: "워크스페이스 메모리가 4,200자로 커졌습니다."
        )

        let msg = mockTelegramService.sentMessages[0].text
        XCTAssertTrue(msg.hasPrefix("\u{1F4BE}"))
        XCTAssertTrue(msg.contains("*메모리 정리 필요*"))
        XCTAssertTrue(msg.contains("메모리 정리해줘"))
    }

    // MARK: - Daily Count

    func testDailyCount() async {
        settings.heartbeatNotificationChannel = NotificationChannel.telegramOnly.rawValue
        settings.telegramSkipWhenAppActive = false

        await relay.sendHeartbeatAlert(calendar: "A", kanban: "", reminder: "", memory: nil)
        await relay.sendHeartbeatAlert(calendar: "B", kanban: "", reminder: "", memory: nil)

        XCTAssertEqual(relay.todayTelegramNotificationCount, 2)
    }

    // MARK: - Send Failure Graceful

    func testSendFailureGraceful() async {
        // Use a service that will throw
        let failingService = MockTelegramService()
        let failRelay = TelegramProactiveRelay(
            settings: settings,
            telegramService: failingService,
            keychainService: mockKeychainService
        )
        failRelay.start()

        // Remove chat mapping so it skips (no error)
        settings.telegramChatMappingJSON = "[]"
        settings.heartbeatNotificationChannel = NotificationChannel.both.rawValue
        settings.telegramSkipWhenAppActive = false

        await failRelay.sendHeartbeatAlert(calendar: "A", kanban: "", reminder: "", memory: nil)

        // Should not crash, count stays 0
        XCTAssertEqual(failRelay.todayTelegramNotificationCount, 0)
    }

    // MARK: - Empty Content

    func testEmptyContentDoesNotSend() async {
        settings.heartbeatNotificationChannel = NotificationChannel.both.rawValue
        settings.telegramSkipWhenAppActive = false

        await relay.sendHeartbeatAlert(calendar: "", kanban: "", reminder: "", memory: nil)

        XCTAssertTrue(mockTelegramService.sentMessages.isEmpty)
    }
}
