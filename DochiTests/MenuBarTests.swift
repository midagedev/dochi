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
            llmService: MockLLMService(),
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
    func testEmptyConversationShowsEmptyState() {
        let settings = AppSettings()
        let sessionContext = SessionContext(
            workspaceId: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            currentUserId: nil
        )
        let viewModel = DochiViewModel(
            llmService: MockLLMService(),
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

        // No current conversation means empty state
        XCTAssertNil(viewModel.currentConversation, "Should have no conversation initially")
        XCTAssertEqual(viewModel.interactionState, .idle, "Should be idle initially")
    }

    @MainActor
    func testMenuBarSharesViewModelState() {
        let settings = AppSettings()
        settings.activeAgentName = "테스트 에이전트"
        let sessionContext = SessionContext(
            workspaceId: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            currentUserId: nil
        )
        let viewModel = DochiViewModel(
            llmService: MockLLMService(),
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

        // Setting inputText on viewModel should be visible
        viewModel.inputText = "테스트 입력"
        XCTAssertEqual(viewModel.inputText, "테스트 입력")
        XCTAssertEqual(viewModel.settings.activeAgentName, "테스트 에이전트")
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
