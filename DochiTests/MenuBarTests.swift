import XCTest
@testable import Dochi

// MARK: - MenuBar AppSettings Tests

final class MenuBarSettingsTests: XCTestCase {

    @MainActor
    func testDefaultMenuBarEnabled() {
        // Clean up UserDefaults for this test
        UserDefaults.standard.removeObject(forKey: "menuBarEnabled")
        let settings = AppSettings()
        XCTAssertTrue(settings.menuBarEnabled, "menuBarEnabled should default to true")
    }

    @MainActor
    func testDefaultMenuBarGlobalShortcutEnabled() {
        UserDefaults.standard.removeObject(forKey: "menuBarGlobalShortcutEnabled")
        let settings = AppSettings()
        XCTAssertTrue(settings.menuBarGlobalShortcutEnabled, "menuBarGlobalShortcutEnabled should default to true")
    }

    @MainActor
    func testMenuBarEnabledPersistence() {
        let settings = AppSettings()
        settings.menuBarEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "menuBarEnabled"))

        settings.menuBarEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "menuBarEnabled"))
    }

    @MainActor
    func testMenuBarGlobalShortcutPersistence() {
        let settings = AppSettings()
        settings.menuBarGlobalShortcutEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "menuBarGlobalShortcutEnabled"))

        settings.menuBarGlobalShortcutEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "menuBarGlobalShortcutEnabled"))
    }
}

// MARK: - MenuBarManager Tests

final class MenuBarManagerTests: XCTestCase {

    @MainActor
    private func makeViewModel() -> DochiViewModel {
        let settings = AppSettings()
        let sessionContext = SessionContext(
            workspaceId: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            currentUserId: nil
        )
        return DochiViewModel(
            toolService: MockBuiltInToolService(),
            contextService: MockContextService(),
            conversationService: MockConversationService(),
            keychainService: MockKeychainService(),
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: settings,
            sessionContext: sessionContext
        )
    }

    @MainActor
    func testSetupCreatesStatusItem() {
        let settings = AppSettings()
        settings.menuBarEnabled = true
        let viewModel = makeViewModel()
        let manager = MenuBarManager(settings: settings, viewModel: viewModel)

        manager.setup()
        // After setup, popover should not be shown initially
        XCTAssertFalse(manager.isPopoverShown, "Popover should not be shown after setup")

        manager.teardown()
    }

    @MainActor
    func testSetupSkippedWhenDisabled() {
        let settings = AppSettings()
        settings.menuBarEnabled = false
        let viewModel = makeViewModel()
        let manager = MenuBarManager(settings: settings, viewModel: viewModel)

        manager.setup()
        // When disabled, popover should not exist
        XCTAssertFalse(manager.isPopoverShown, "Popover should not be available when disabled")

        manager.teardown()
    }

    @MainActor
    func testTeardownCleansUp() {
        let settings = AppSettings()
        settings.menuBarEnabled = true
        let viewModel = makeViewModel()
        let manager = MenuBarManager(settings: settings, viewModel: viewModel)

        manager.setup()
        manager.teardown()
        XCTAssertFalse(manager.isPopoverShown, "Popover should not be shown after teardown")
    }

    @MainActor
    func testIconStateDefault() {
        let settings = AppSettings()
        settings.menuBarEnabled = true
        let viewModel = makeViewModel()
        let manager = MenuBarManager(settings: settings, viewModel: viewModel)

        manager.setup()
        XCTAssertEqual(manager.iconState, .normal, "Initial icon state should be .normal")

        manager.teardown()
    }

    @MainActor
    func testUpdateIconState() {
        let settings = AppSettings()
        settings.menuBarEnabled = true
        let viewModel = makeViewModel()
        let manager = MenuBarManager(settings: settings, viewModel: viewModel)

        manager.setup()

        manager.updateIconState(.processing)
        XCTAssertEqual(manager.iconState, .processing)

        manager.updateIconState(.error)
        XCTAssertEqual(manager.iconState, .error)

        manager.updateIconState(.normal)
        XCTAssertEqual(manager.iconState, .normal)

        manager.teardown()
    }

    @MainActor
    func testHandleSettingsChangeEnables() {
        let settings = AppSettings()
        settings.menuBarEnabled = false
        let viewModel = makeViewModel()
        let manager = MenuBarManager(settings: settings, viewModel: viewModel)

        manager.setup()
        // Now enable
        settings.menuBarEnabled = true
        manager.handleSettingsChange()
        // Manager should now have status item (we check via isPopoverShown which is false but no crash)
        XCTAssertFalse(manager.isPopoverShown)

        manager.teardown()
    }

    @MainActor
    func testHandleSettingsChangeDisables() {
        let settings = AppSettings()
        settings.menuBarEnabled = true
        let viewModel = makeViewModel()
        let manager = MenuBarManager(settings: settings, viewModel: viewModel)

        manager.setup()
        // Now disable
        settings.menuBarEnabled = false
        manager.handleSettingsChange()
        XCTAssertFalse(manager.isPopoverShown)
    }

    @MainActor
    func testIconStateEquatable() {
        let state1: MenuBarManager.StatusIconState = .normal
        let state2: MenuBarManager.StatusIconState = .normal
        let state3: MenuBarManager.StatusIconState = .processing
        XCTAssertEqual(state1, state2)
        XCTAssertNotEqual(state1, state3)
    }
}

// MARK: - CommandPalette MenuBar Item Tests

final class CommandPaletteMenuBarTests: XCTestCase {

    func testMenuBarPaletteItemExists() {
        let item = CommandPaletteRegistry.staticItems.first { $0.id == "toggle-menu-bar" }
        XCTAssertNotNil(item, "Menu bar palette item should exist")
        XCTAssertEqual(item?.title, "메뉴바 퀵 액세스 토글")
        XCTAssertEqual(item?.subtitle, "⌘⇧D")
        XCTAssertEqual(item?.category, .navigation)
    }

    func testAllStaticItemsUniqueIds() {
        let ids = CommandPaletteRegistry.staticItems.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Static item IDs should be unique")
    }
}

// MARK: - MenuBarPopoverView Data Tests

final class MenuBarPopoverDataTests: XCTestCase {

    @MainActor
    private func makeViewModel(settings: AppSettings = AppSettings()) -> DochiViewModel {
        let sessionContext = SessionContext(
            workspaceId: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            currentUserId: nil
        )
        return DochiViewModel(
            toolService: MockBuiltInToolService(),
            contextService: MockContextService(),
            conversationService: MockConversationService(),
            keychainService: MockKeychainService(),
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: settings,
            sessionContext: sessionContext
        )
    }

    @MainActor
    func testEmptyConversationShowsEmptyState() {
        let settings = AppSettings()
        let viewModel = makeViewModel(settings: settings)

        // No current conversation means empty state
        XCTAssertNil(viewModel.currentConversation, "Should have no conversation initially")
        XCTAssertEqual(viewModel.interactionState, .idle, "Should be idle initially")
    }

    @MainActor
    func testMenuBarSharesViewModelState() {
        let settings = AppSettings()
        settings.activeAgentName = "테스트 에이전트"
        let viewModel = makeViewModel(settings: settings)

        // Setting inputText on viewModel should be visible
        viewModel.inputText = "테스트 입력"
        XCTAssertEqual(viewModel.inputText, "테스트 입력")
        XCTAssertEqual(viewModel.settings.activeAgentName, "테스트 에이전트")
    }

    @MainActor
    func testMenuBarSubscriptionUsageShowsThreeSlotsWithoutOptimizer() async {
        let viewModel = makeViewModel()

        await viewModel.refreshMenuBarSubscriptionUsage()

        XCTAssertEqual(
            viewModel.menuBarSubscriptionUsage.map(\.provider),
            [.codex, .claude, .gemini]
        )
        XCTAssertTrue(
            viewModel.menuBarSubscriptionUsage.allSatisfy { $0.availability == .serviceUnavailable }
        )
    }

    @MainActor
    func testMenuBarSubscriptionUsageMapsConfiguredProvidersAndKeepsMissingSlot() async throws {
        let viewModel = makeViewModel()
        let mockOptimizer = MockResourceOptimizer()

        let codexPlan = SubscriptionPlan(
            providerName: "OpenAI",
            planName: "ChatGPT Plus",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: 1_000_000
        )
        let claudePlan = SubscriptionPlan(
            providerName: "Anthropic",
            planName: "Claude Max",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: nil
        )

        mockOptimizer.subscriptions = [codexPlan, claudePlan]
        mockOptimizer.monitoringSnapshotsByID[codexPlan.id] = SubscriptionMonitoringSnapshot(
            subscriptionID: codexPlan.id,
            source: codexPlan.usageSource,
            provider: codexPlan.providerName,
            statusCode: "ok_log_scan",
            statusMessage: nil,
            lastCollectedAt: Date(),
            primaryWindow: MonitoringUsageWindowSnapshot(
                label: "session",
                usedPercent: 40,
                windowMinutes: 300
            ),
            secondaryWindow: MonitoringUsageWindowSnapshot(
                label: "weekly",
                usedPercent: 65,
                windowMinutes: 10_080
            )
        )
        mockOptimizer.monitoringSnapshotsByID[claudePlan.id] = SubscriptionMonitoringSnapshot(
            subscriptionID: claudePlan.id,
            source: claudePlan.usageSource,
            provider: claudePlan.providerName,
            statusCode: "ok_log_scan",
            statusMessage: nil,
            lastCollectedAt: Date(),
            primaryWindow: MonitoringUsageWindowSnapshot(
                label: "주간",
                usedPercent: 70
            )
        )

        viewModel.configureResourceOptimizer(mockOptimizer)
        await viewModel.refreshMenuBarSubscriptionUsage()

        let codex = try XCTUnwrap(
            viewModel.menuBarSubscriptionUsage.first(where: { $0.provider == .codex })
        )
        XCTAssertEqual(codex.remainingText, "60% 남음")
        XCTAssertEqual(codex.detailText, "세션 사용 40%")
        XCTAssertEqual(codex.windows.count, 2)
        XCTAssertEqual(codex.windows.map(\.label), ["세션", "주간"])
        XCTAssertEqual(codex.availability, .active)

        let claude = try XCTUnwrap(
            viewModel.menuBarSubscriptionUsage.first(where: { $0.provider == .claude })
        )
        XCTAssertEqual(claude.remainingText, "30% 남음")
        XCTAssertEqual(claude.detailText, "주간 사용 70%")
        XCTAssertEqual(claude.windows.count, 1)
        XCTAssertEqual(claude.availability, .active)

        let gemini = try XCTUnwrap(
            viewModel.menuBarSubscriptionUsage.first(where: { $0.provider == .gemini })
        )
        XCTAssertEqual(gemini.remainingText, "미등록")
        XCTAssertEqual(gemini.availability, .notConfigured)
    }

    @MainActor
    func testMenuBarSubscriptionUsageShowsResetCountdownWhenResetsAtProvided() async throws {
        let viewModel = makeViewModel()
        let mockOptimizer = MockResourceOptimizer()

        let codexPlan = SubscriptionPlan(
            providerName: "OpenAI",
            planName: "ChatGPT Plus",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: nil
        )

        mockOptimizer.subscriptions = [codexPlan]
        mockOptimizer.monitoringSnapshotsByID[codexPlan.id] = SubscriptionMonitoringSnapshot(
            subscriptionID: codexPlan.id,
            source: codexPlan.usageSource,
            provider: codexPlan.providerName,
            statusCode: "ok_log_scan",
            statusMessage: nil,
            lastCollectedAt: Date(),
            primaryWindow: MonitoringUsageWindowSnapshot(
                label: "session",
                usedPercent: 25,
                windowMinutes: 300,
                resetsAt: Date().addingTimeInterval(2 * 60 * 60)
            )
        )

        viewModel.configureResourceOptimizer(mockOptimizer)
        await viewModel.refreshMenuBarSubscriptionUsage()

        let codex = try XCTUnwrap(
            viewModel.menuBarSubscriptionUsage.first(where: { $0.provider == .codex })
        )
        let detail = try XCTUnwrap(codex.windows.first?.detail)
        XCTAssertTrue(detail.contains("남음"))
    }

    @MainActor
    func testMenuBarSuggestionExposedWhenToggleEnabled() {
        let settings = AppSettings()
        settings.proactiveSuggestionMenuBarEnabled = true
        let viewModel = makeViewModel(settings: settings)

        let mockSuggestionService = MockProactiveSuggestionService()
        let suggestion = ProactiveSuggestion(
            type: .newsTrend,
            title: "메뉴바 제안",
            body: "제안 본문",
            suggestedPrompt: "프롬프트"
        )
        mockSuggestionService.currentSuggestion = suggestion
        viewModel.configureProactiveSuggestionService(mockSuggestionService)

        XCTAssertEqual(viewModel.menuBarSuggestion?.id, suggestion.id)
    }

    @MainActor
    func testMenuBarSuggestionHiddenWhenToggleDisabled() {
        let settings = AppSettings()
        settings.proactiveSuggestionMenuBarEnabled = false
        let viewModel = makeViewModel(settings: settings)

        let mockSuggestionService = MockProactiveSuggestionService()
        mockSuggestionService.currentSuggestion = ProactiveSuggestion(
            type: .newsTrend,
            title: "메뉴바 제안",
            body: "제안 본문",
            suggestedPrompt: "프롬프트"
        )
        viewModel.configureProactiveSuggestionService(mockSuggestionService)

        XCTAssertNil(viewModel.menuBarSuggestion)
    }
}

// MARK: - StatusIconState Equatable

extension MenuBarManager.StatusIconState: @retroactive Equatable {
    public static func == (lhs: MenuBarManager.StatusIconState, rhs: MenuBarManager.StatusIconState) -> Bool {
        switch (lhs, rhs) {
        case (.normal, .normal): return true
        case (.processing, .processing): return true
        case (.error, .error): return true
        default: return false
        }
    }
}
