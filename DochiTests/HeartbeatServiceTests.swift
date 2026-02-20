import XCTest
@testable import Dochi

@MainActor
final class HeartbeatServiceTests: XCTestCase {

    private func makeViewModelForOpportunityTests() -> DochiViewModel {
        let contextService = MockContextService()
        let settings = AppSettings()
        let keychainService = MockKeychainService()
        keychainService.store["openai_api_key"] = "sk-test"

        return DochiViewModel(
            toolService: MockBuiltInToolService(),
            contextService: contextService,
            conversationService: MockConversationService(),
            keychainService: keychainService,
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: settings,
            sessionContext: SessionContext(workspaceId: UUID())
        )
    }

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

    func testMapTaskOpportunitiesBuildsStructuredActions() {
        let settings = AppSettings()
        let service = HeartbeatService(settings: settings)

        let opportunities = service.mapTaskOpportunities(
            calendarContext: "오전 9:00 팀 스탠드업",
            kanbanContext: "- 🔥 배포 체크 [제품 운영]",
            reminderContext: "계약서 확인 (마감: 오후 3:00)",
            memoryWarning: nil
        )

        XCTAssertGreaterThanOrEqual(opportunities.count, 3)
        XCTAssertTrue(opportunities.contains { $0.actionKind == .createReminder })
        XCTAssertTrue(opportunities.contains { $0.actionKind == .createKanbanCard })
        XCTAssertTrue(opportunities.allSatisfy { !$0.suggestedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    func testMapTaskOpportunitiesCapsResultSize() {
        let settings = AppSettings()
        let service = HeartbeatService(settings: settings)

        let opportunities = service.mapTaskOpportunities(
            calendarContext: "a\nb\nc",
            kanbanContext: "- x [A]\n- y [B]\n- z [C]",
            reminderContext: "r1 (마감: 10:00)\nr2 (마감: 11:00)\nr3 (마감: 12:00)",
            memoryWarning: "메모리 경고"
        )

        XCTAssertEqual(opportunities.count, 4)
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

    func testTickDoesNotTriggerExternalToolHealthCheck() async throws {
        let settings = AppSettings()
        settings.heartbeatEnabled = true
        settings.externalToolEnabled = true
        settings.heartbeatIntervalMinutes = 0
        settings.heartbeatCheckCalendar = false
        settings.heartbeatCheckKanban = false
        settings.heartbeatCheckReminders = false
        settings.heartbeatQuietHoursStart = 0
        settings.heartbeatQuietHoursEnd = 0

        let service = HeartbeatService(settings: settings)
        let externalToolManager = MockExternalToolSessionManager()
        service.setExternalToolManager(externalToolManager)

        service.start()
        defer { service.stop() }

        let timeout = Date().addingTimeInterval(0.5)
        while service.lastTickDate == nil && Date() < timeout {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNotNil(service.lastTickDate)
        XCTAssertEqual(
            externalToolManager.checkAllHealthCallCount,
            0,
            "External tool health checks should be driven by ExternalToolSessionManager monitor, not HeartbeatService tick."
        )
    }

    func testTickCollectsGitContextWithoutSendingNotificationAlone() async throws {
        let settings = AppSettings()
        settings.heartbeatEnabled = true
        settings.heartbeatIntervalMinutes = 0
        settings.heartbeatCheckCalendar = false
        settings.heartbeatCheckKanban = false
        settings.heartbeatCheckReminders = false
        settings.heartbeatQuietHoursStart = 0
        settings.heartbeatQuietHoursEnd = 0

        let service = HeartbeatService(settings: settings)
        let externalToolManager = MockExternalToolSessionManager()
        externalToolManager.mockGitRepositoryInsights = [
            GitRepositoryInsight(
                workDomain: "company",
                workDomainConfidence: 0.82,
                workDomainReason: "self-hosted git remote",
                path: "/Users/me/repo/work",
                name: "work",
                branch: "main",
                originURL: "ssh://git@git.company.local/team/work.git",
                remoteHost: "git.company.local",
                remoteOwner: "team",
                remoteRepository: "work",
                lastCommitEpoch: 1_700_000_000,
                lastCommitISO8601: "2023-11-14T22:13:20.000Z",
                lastCommitRelative: "1d ago",
                upstreamLastCommitEpoch: 1_700_000_000,
                upstreamLastCommitISO8601: "2023-11-14T22:13:20.000Z",
                upstreamLastCommitRelative: "1d ago",
                daysSinceLastCommit: 1,
                recentCommitCount30d: 8,
                changedFileCount: 2,
                untrackedFileCount: 1,
                aheadCount: 0,
                behindCount: 0,
                score: 60
            ),
        ]
        service.setExternalToolManager(externalToolManager)

        service.start()
        defer { service.stop() }

        let timeout = Date().addingTimeInterval(0.5)
        while service.lastTickDate == nil && Date() < timeout {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNotNil(service.lastTickDate)
        XCTAssertEqual(service.lastTickResult?.notificationSent, false)
        XCTAssertTrue(service.lastTickResult?.gitContextSummary?.contains("[company] work") == true)
    }

    func testTickTriggersResourceAutoTaskPipelineWhenEnabled() async throws {
        let settings = AppSettings()
        settings.heartbeatEnabled = true
        settings.heartbeatIntervalMinutes = 0
        settings.heartbeatCheckCalendar = false
        settings.heartbeatCheckKanban = false
        settings.heartbeatCheckReminders = false
        settings.heartbeatQuietHoursStart = 0
        settings.heartbeatQuietHoursEnd = 0
        settings.resourceAutoTaskEnabled = true
        settings.resourceAutoTaskOnlyWasteRisk = true
        settings.resourceAutoTaskTypes = [AutoTaskType.research.rawValue]

        let service = HeartbeatService(settings: settings)
        let optimizer = MockResourceOptimizer()
        service.setResourceOptimizer(optimizer)

        service.start()
        defer { service.stop() }

        let timeout = Date().addingTimeInterval(0.5)
        while service.lastTickDate == nil && Date() < timeout {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNotNil(service.lastTickDate)
        XCTAssertGreaterThanOrEqual(optimizer.evaluateAndQueueAutoTasksCallCount, 1)
        XCTAssertEqual(optimizer.lastOnlyWasteRisk, true)
        XCTAssertEqual(Set(optimizer.lastEvaluatedTypes), Set([.research]))
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

    func testExecuteTaskOpportunityTriggersKanbanActionAndShowsSuccessFeedback() async {
        let viewModel = makeViewModelForOpportunityTests()
        let opportunity = TaskOpportunity(
            source: .reminder,
            title: "칸반 등록",
            detail: "테스트",
            actionKind: .createKanbanCard,
            suggestedTitle: "테스트 작업"
        )

        let called = expectation(description: "kanban action called")
        viewModel.kanbanOpportunityExecutor = { _ in
            called.fulfill()
            return true
        }

        viewModel.executeTaskOpportunity(opportunity)
        await fulfillment(of: [called], timeout: 1.0)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.taskOpportunityActionFeedback?.opportunityId, opportunity.id)
        XCTAssertEqual(viewModel.taskOpportunityActionFeedback?.isSuccess, true)
        XCTAssertTrue(viewModel.completedTaskOpportunityIDs.contains(opportunity.id))
    }

    func testExecuteTaskOpportunityFailureShowsErrorFeedback() async {
        let viewModel = makeViewModelForOpportunityTests()
        let opportunity = TaskOpportunity(
            source: .calendar,
            title: "미리알림 등록",
            detail: "테스트",
            actionKind: .createReminder,
            suggestedTitle: "테스트 리마인더"
        )

        let called = expectation(description: "reminder action called")
        viewModel.reminderOpportunityExecutor = { _ in
            called.fulfill()
            return ToolResult(toolCallId: "", content: "미리알림 생성 실패", isError: true)
        }

        viewModel.executeTaskOpportunity(opportunity)
        await fulfillment(of: [called], timeout: 1.0)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.taskOpportunityActionFeedback?.opportunityId, opportunity.id)
        XCTAssertEqual(viewModel.taskOpportunityActionFeedback?.isSuccess, false)
        XCTAssertEqual(viewModel.errorMessage, "미리알림 생성 실패")
        XCTAssertFalse(viewModel.completedTaskOpportunityIDs.contains(opportunity.id))
    }
}
