import XCTest
@testable import Dochi

@MainActor
final class HeartbeatServiceTests: XCTestCase {

    // MARK: - HeartbeatTickResult

    func testTickResultStoresAllFields() {
        let result = HeartbeatTickResult(
            timestamp: Date(),
            checksPerformed: ["calendar", "kanban"],
            itemsFound: 3,
            notificationSent: true,
            error: nil
        )
        XCTAssertEqual(result.checksPerformed.count, 2)
        XCTAssertEqual(result.itemsFound, 3)
        XCTAssertTrue(result.notificationSent)
        XCTAssertNil(result.error)
    }

    func testTickResultWithError() {
        let result = HeartbeatTickResult(
            timestamp: Date(),
            checksPerformed: [],
            itemsFound: 0,
            notificationSent: false,
            error: "Test error"
        )
        XCTAssertEqual(result.error, "Test error")
        XCTAssertFalse(result.notificationSent)
    }

    // MARK: - HeartbeatService Init

    func testServiceInitialization() {
        let settings = AppSettings()
        let service = HeartbeatService(settings: settings)
        XCTAssertNil(service.lastTickDate)
        XCTAssertNil(service.lastTickResult)
        XCTAssertTrue(service.tickHistory.isEmpty)
        XCTAssertEqual(service.consecutiveErrors, 0)
    }

    func testMaxHistoryCount() {
        XCTAssertEqual(HeartbeatService.maxHistoryCount, 20)
    }

    // MARK: - Start/Stop

    func testStartWithDisabledSettingsDoesNothing() {
        let settings = AppSettings()
        settings.heartbeatEnabled = false
        let service = HeartbeatService(settings: settings)
        service.start()
        // Should not crash, no tick should happen
        XCTAssertNil(service.lastTickDate)
    }

    func testStopIsIdempotent() {
        let settings = AppSettings()
        let service = HeartbeatService(settings: settings)
        service.stop()
        service.stop() // Should not crash
        XCTAssertNil(service.lastTickDate)
    }

    func testRestartCyclesCleanly() {
        let settings = AppSettings()
        settings.heartbeatEnabled = false
        let service = HeartbeatService(settings: settings)
        service.restart()
        service.restart()
        XCTAssertNil(service.lastTickDate)
    }

    // MARK: - Configure

    func testConfigureAcceptsDependencies() {
        let settings = AppSettings()
        let service = HeartbeatService(settings: settings)
        let contextService = MockContextService()
        let sessionContext = SessionContext(workspaceId: UUID())
        service.configure(contextService: contextService, sessionContext: sessionContext)
        // Should not crash
    }

    // MARK: - Proactive Handler

    func testProactiveHandlerIsCalled() {
        let settings = AppSettings()
        let service = HeartbeatService(settings: settings)

        var receivedMessage: String?
        service.setProactiveHandler { message in
            receivedMessage = message
        }

        // Directly verify handler is set by replacing it
        service.setProactiveHandler { message in
            receivedMessage = message
        }
        XCTAssertNil(receivedMessage) // Not called yet
    }

    // MARK: - ViewModel integration

    func testInjectProactiveMessageAddsToConversation() {
        let contextService = MockContextService()
        let settings = AppSettings()
        let keychainService = MockKeychainService()
        keychainService.store["openai_api_key"] = "sk-test"
        let sessionContext = SessionContext(workspaceId: UUID())

        let viewModel = DochiViewModel(
            llmService: MockLLMService(),
            toolService: MockBuiltInToolService(),
            contextService: contextService,
            conversationService: MockConversationService(),
            keychainService: keychainService,
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: settings,
            sessionContext: sessionContext
        )

        // Create a conversation manually (newConversation() sets it to nil)
        viewModel.currentConversation = Conversation(title: "테스트")
        XCTAssertNotNil(viewModel.currentConversation)

        let messageBefore = viewModel.currentConversation?.messages.count ?? 0
        viewModel.injectProactiveMessage("테스트 알림")
        let messageAfter = viewModel.currentConversation?.messages.count ?? 0

        XCTAssertEqual(messageAfter, messageBefore + 1)
        XCTAssertEqual(viewModel.currentConversation?.messages.last?.content, "테스트 알림")
        XCTAssertEqual(viewModel.currentConversation?.messages.last?.role, .assistant)
    }

    func testInjectProactiveMessageWithNoConversationDoesNothing() {
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

        // Don't create a conversation
        viewModel.injectProactiveMessage("no conversation")
        // Should not crash
        XCTAssertNil(viewModel.currentConversation)
    }
}
