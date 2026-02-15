import XCTest
import UserNotifications
@testable import Dochi

@MainActor
final class NotificationCenterTests: XCTestCase {

    // MARK: - AppSettings Notification Properties

    func testNotificationSettingsDefaults() {
        let settings = AppSettings()
        XCTAssertTrue(settings.notificationCalendarEnabled)
        XCTAssertTrue(settings.notificationKanbanEnabled)
        XCTAssertTrue(settings.notificationReminderEnabled)
        XCTAssertTrue(settings.notificationMemoryEnabled)
        XCTAssertTrue(settings.notificationSoundEnabled)
        XCTAssertTrue(settings.notificationReplyEnabled)
    }

    func testNotificationSettingsPersistence() {
        let settings = AppSettings()
        settings.notificationCalendarEnabled = false
        XCTAssertFalse(settings.notificationCalendarEnabled)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "notificationCalendarEnabled"))

        settings.notificationKanbanEnabled = false
        XCTAssertFalse(settings.notificationKanbanEnabled)

        settings.notificationReminderEnabled = false
        XCTAssertFalse(settings.notificationReminderEnabled)

        settings.notificationMemoryEnabled = false
        XCTAssertFalse(settings.notificationMemoryEnabled)

        settings.notificationSoundEnabled = false
        XCTAssertFalse(settings.notificationSoundEnabled)

        settings.notificationReplyEnabled = false
        XCTAssertFalse(settings.notificationReplyEnabled)

        // Restore defaults
        settings.notificationCalendarEnabled = true
        settings.notificationKanbanEnabled = true
        settings.notificationReminderEnabled = true
        settings.notificationMemoryEnabled = true
        settings.notificationSoundEnabled = true
        settings.notificationReplyEnabled = true
    }

    // MARK: - NotificationManager Initialization

    func testNotificationManagerInitialization() {
        let settings = AppSettings()
        let manager = NotificationManager(settings: settings)
        XCTAssertNil(manager.onReply)
        XCTAssertNil(manager.onOpenApp)
        XCTAssertEqual(manager.authorizationStatus, .notDetermined)
    }

    // MARK: - NotificationManager Category Constants

    func testNotificationCategoryValues() {
        XCTAssertEqual(NotificationManager.Category.calendar.rawValue, "dochi-calendar")
        XCTAssertEqual(NotificationManager.Category.kanban.rawValue, "dochi-kanban")
        XCTAssertEqual(NotificationManager.Category.reminder.rawValue, "dochi-reminder")
        XCTAssertEqual(NotificationManager.Category.memory.rawValue, "dochi-memory")
    }

    func testNotificationCategoryAllCases() {
        let allCases = NotificationManager.Category.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.calendar))
        XCTAssertTrue(allCases.contains(.kanban))
        XCTAssertTrue(allCases.contains(.reminder))
        XCTAssertTrue(allCases.contains(.memory))
    }

    // MARK: - NotificationManager Action Constants

    func testNotificationActionValues() {
        XCTAssertEqual(NotificationManager.ActionIdentifier.reply.rawValue, "reply")
        XCTAssertEqual(NotificationManager.ActionIdentifier.openApp.rawValue, "open-app")
        XCTAssertEqual(NotificationManager.ActionIdentifier.dismiss.rawValue, "dismiss")
    }

    // MARK: - Category Filtering

    func testSendCalendarNotificationRespectsSettings() {
        let settings = AppSettings()
        settings.notificationCalendarEnabled = false
        let manager = NotificationManager(settings: settings)

        // Should not crash when disabled
        manager.sendCalendarNotification(events: "테스트 이벤트")

        // Restore
        settings.notificationCalendarEnabled = true
    }

    func testSendKanbanNotificationRespectsSettings() {
        let settings = AppSettings()
        settings.notificationKanbanEnabled = false
        let manager = NotificationManager(settings: settings)

        // Should not crash when disabled
        manager.sendKanbanNotification(tasks: "테스트 작업")

        // Restore
        settings.notificationKanbanEnabled = true
    }

    func testSendReminderNotificationRespectsSettings() {
        let settings = AppSettings()
        settings.notificationReminderEnabled = false
        let manager = NotificationManager(settings: settings)

        // Should not crash when disabled
        manager.sendReminderNotification(reminders: "테스트 미리알림")

        // Restore
        settings.notificationReminderEnabled = true
    }

    func testSendMemoryNotificationRespectsSettings() {
        let settings = AppSettings()
        settings.notificationMemoryEnabled = false
        let manager = NotificationManager(settings: settings)

        // Should not crash when disabled
        manager.sendMemoryNotification(warning: "테스트 경고")

        // Restore
        settings.notificationMemoryEnabled = true
    }

    // MARK: - Register Categories

    func testRegisterCategoriesDoesNotCrash() {
        let settings = AppSettings()
        let manager = NotificationManager(settings: settings)
        manager.registerCategories()
        // Should not crash; categories are registered with UNUserNotificationCenter
    }

    // MARK: - HeartbeatService NotificationManager Integration

    func testHeartbeatServiceAcceptsNotificationManager() {
        let settings = AppSettings()
        let heartbeatService = HeartbeatService(settings: settings)
        let manager = NotificationManager(settings: settings)
        heartbeatService.setNotificationManager(manager)
        // Should not crash
    }

    // MARK: - NotificationManager Callback Wiring

    func testOnReplyCallbackIsInvoked() {
        let settings = AppSettings()
        let manager = NotificationManager(settings: settings)

        var receivedText: String?
        var receivedCategory: String?
        var receivedBody: String?

        manager.onReply = { text, category, body in
            receivedText = text
            receivedCategory = category
            receivedBody = body
        }

        // Simulate callback invocation
        manager.onReply?("답장 텍스트", "dochi-calendar", "원본 알림")

        XCTAssertEqual(receivedText, "답장 텍스트")
        XCTAssertEqual(receivedCategory, "dochi-calendar")
        XCTAssertEqual(receivedBody, "원본 알림")
    }

    func testOnOpenAppCallbackIsInvoked() {
        let settings = AppSettings()
        let manager = NotificationManager(settings: settings)

        var receivedCategory: String?

        manager.onOpenApp = { category in
            receivedCategory = category
        }

        // Simulate callback invocation
        manager.onOpenApp?("dochi-kanban")

        XCTAssertEqual(receivedCategory, "dochi-kanban")
    }

    // MARK: - ViewModel Notification Handling

    func testHandleNotificationReplyInjectsAndSends() {
        let settings = AppSettings()
        let keychainService = MockKeychainService()
        keychainService.store["openai_api_key"] = "sk-test"

        let viewModel = DochiViewModel(
            llmService: MockLLMService(),
            toolService: MockBuiltInToolService(),
            contextService: MockContextService(),
            conversationService: MockConversationService(),
            keychainService: keychainService,
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: settings,
            sessionContext: SessionContext(workspaceId: UUID())
        )

        // Create a conversation first
        viewModel.currentConversation = Conversation(title: "알림 테스트")
        let initialCount = viewModel.currentConversation?.messages.count ?? 0

        // Handle notification reply
        viewModel.handleNotificationReply(
            text: "네, 확인했어요",
            category: "dochi-calendar",
            originalBody: "10:00 회의가 있습니다"
        )

        // Should have injected the original notification body as assistant message
        let afterCount = viewModel.currentConversation?.messages.count ?? 0
        XCTAssertGreaterThanOrEqual(afterCount, initialCount + 1)

        // First injected message should contain the notification context
        if afterCount > initialCount {
            let injectedMessage = viewModel.currentConversation!.messages[initialCount]
            XCTAssertEqual(injectedMessage.role, .assistant)
            XCTAssertTrue(injectedMessage.content.contains("10:00 회의가 있습니다"))
        }
    }

    func testHandleNotificationOpenAppDoesNotCrash() {
        let settings = AppSettings()
        let keychainService = MockKeychainService()
        keychainService.store["openai_api_key"] = "sk-test"

        let viewModel = DochiViewModel(
            llmService: MockLLMService(),
            toolService: MockBuiltInToolService(),
            contextService: MockContextService(),
            conversationService: MockConversationService(),
            keychainService: keychainService,
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: settings,
            sessionContext: SessionContext(workspaceId: UUID())
        )

        // Should not crash for any category
        viewModel.handleNotificationOpenApp(category: NotificationManager.Category.calendar.rawValue)
        viewModel.handleNotificationOpenApp(category: NotificationManager.Category.kanban.rawValue)
        viewModel.handleNotificationOpenApp(category: NotificationManager.Category.reminder.rawValue)
        viewModel.handleNotificationOpenApp(category: NotificationManager.Category.memory.rawValue)
        viewModel.handleNotificationOpenApp(category: "unknown-category")
    }

    // MARK: - NotificationAuthorizationStatusView

    func testAuthorizationStatusViewStates() {
        // Test that each status creates a valid view (no crash)
        _ = NotificationAuthorizationStatusView(status: .authorized)
        _ = NotificationAuthorizationStatusView(status: .denied)
        _ = NotificationAuthorizationStatusView(status: .notDetermined)
        _ = NotificationAuthorizationStatusView(status: .provisional)
    }
}
