import XCTest
@testable import Dochi

// MARK: - FuzzyMatcher Tests

final class FuzzyMatcherTests: XCTestCase {

    // MARK: - isAllChoseong

    func testIsAllChoseong_choseongOnly() {
        XCTAssertTrue(FuzzyMatcher.isAllChoseong("ㄱㄴㄷ"))
        XCTAssertTrue(FuzzyMatcher.isAllChoseong("ㅎ"))
    }

    func testIsAllChoseong_mixed() {
        XCTAssertFalse(FuzzyMatcher.isAllChoseong("ㄱ가"))
        XCTAssertFalse(FuzzyMatcher.isAllChoseong("abc"))
        XCTAssertFalse(FuzzyMatcher.isAllChoseong(""))
    }

    // MARK: - extractChoseong

    func testExtractChoseong_hangul() {
        XCTAssertEqual(FuzzyMatcher.extractChoseong("새대화"), "ㅅㄷㅎ")
        XCTAssertEqual(FuzzyMatcher.extractChoseong("컨텍스트"), "ㅋㅌㅅㅌ")
    }

    func testExtractChoseong_mixed() {
        XCTAssertEqual(FuzzyMatcher.extractChoseong("A설정B"), "AㅅㅈB")
    }

    // MARK: - Jamo matching

    func testMatchScore_koreanSubstring() {
        let score = FuzzyMatcher.matchScore(title: "새 대화", query: "대화")
        XCTAssertGreaterThan(score, 0)
    }

    func testMatchScore_choseongMatch() {
        let score = FuzzyMatcher.matchScore(title: "새 대화", query: "ㅅㄷ")
        XCTAssertGreaterThan(score, 0, "Choseong query should match title's choseong")
    }

    func testMatchScore_choseongPrefix() {
        let score = FuzzyMatcher.matchScore(title: "설정 열기", query: "ㅅㅈ")
        XCTAssertGreaterThan(score, 0)
    }

    // MARK: - English matching

    func testMatchScore_englishContains() {
        let score = FuzzyMatcher.matchScore(title: "System Status", query: "stat")
        XCTAssertGreaterThan(score, 0)
    }

    func testMatchScore_englishPrefix() {
        let score = FuzzyMatcher.matchScore(title: "Settings", query: "Set")
        XCTAssertEqual(score, 50, "Prefix match should score 50")
    }

    func testMatchScore_englishCaseInsensitive() {
        let score = FuzzyMatcher.matchScore(title: "Settings", query: "settings")
        XCTAssertGreaterThan(score, 0)
    }

    // MARK: - Empty query & no results

    func testMatchScore_emptyQuery() {
        // Empty query typically returns 0 (handled by filter which returns all items)
        let score = FuzzyMatcher.matchScore(title: "test", query: "")
        // An empty query should not match any specific item
        XCTAssertEqual(score, 0)
    }

    func testMatchScore_noMatch() {
        let score = FuzzyMatcher.matchScore(title: "설정", query: "xyz")
        XCTAssertEqual(score, 0)
    }

    // MARK: - filter

    func testFilter_emptyQueryReturnsAll() {
        let items = ["a", "b", "c"]
        let result = FuzzyMatcher.filter(items: items, query: "", keyPath: \.self)
        XCTAssertEqual(result.count, 3)
    }

    func testFilter_withQuery() {
        let items = ["새 대화", "설정 열기", "시스템 상태"]
        let result = FuzzyMatcher.filter(items: items, query: "설정", keyPath: \.self)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first, "설정 열기")
    }

    func testFilter_recentBonus() {
        struct Item {
            let id: String
            let title: String
        }
        let items = [
            Item(id: "a", title: "설정 열기"),
            Item(id: "b", title: "설정 변경"),
        ]
        let result = FuzzyMatcher.filter(
            items: items,
            query: "설정",
            keyPath: \.title,
            recentIds: ["b"],
            idKeyPath: \.id
        )
        XCTAssertEqual(result.count, 2)
        // "b" should come first due to recent bonus
        XCTAssertEqual(result.first?.id, "b")
    }
}

// MARK: - CommandPaletteItem Tests

final class CommandPaletteItemTests: XCTestCase {

    func testStaticItemsNotEmpty() {
        XCTAssertFalse(CommandPaletteRegistry.staticItems.isEmpty)
    }

    func testStaticItemsHaveUniqueIds() {
        let ids = CommandPaletteRegistry.staticItems.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Static item IDs should be unique")
    }

    func testStaticItemsHaveRequiredFields() {
        for item in CommandPaletteRegistry.staticItems {
            XCTAssertFalse(item.id.isEmpty, "Item ID should not be empty")
            XCTAssertFalse(item.icon.isEmpty, "Item \(item.id) should have an icon")
            XCTAssertFalse(item.title.isEmpty, "Item \(item.id) should have a title")
        }
    }

    @MainActor
    func testAllItemsIncludesConversations() {
        let conv = Conversation(title: "테스트 대화")
        let items = CommandPaletteRegistry.allItems(
            conversations: [conv],
            agents: [],
            workspaceIds: [],
            profiles: [],
            currentAgentName: "도치",
            currentWorkspaceId: UUID(),
            currentUserId: nil
        )

        let conversationItems = items.filter { $0.category == .conversation }
        XCTAssertEqual(conversationItems.count, 1)
        XCTAssertEqual(conversationItems.first?.title, "테스트 대화")
    }

    @MainActor
    func testAllItemsIncludesAgents() {
        let items = CommandPaletteRegistry.allItems(
            conversations: [],
            agents: ["도치", "비서"],
            workspaceIds: [],
            profiles: [],
            currentAgentName: "도치",
            currentWorkspaceId: UUID(),
            currentUserId: nil
        )

        let agentItems = items.filter { $0.category == .agent }
        XCTAssertEqual(agentItems.count, 2)
    }
}

// MARK: - Recent History Tests

final class CommandPaletteRecentTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clear recents before each test
        UserDefaults.standard.removeObject(forKey: "commandPaletteRecentIds")
    }

    func testRecordAndLoadRecent() {
        CommandPaletteRegistry.recordRecent(id: "test-1")
        CommandPaletteRegistry.recordRecent(id: "test-2")

        let recents = CommandPaletteRegistry.recentIds()
        XCTAssertEqual(recents.count, 2)
        XCTAssertEqual(recents[0], "test-2") // Most recent first
        XCTAssertEqual(recents[1], "test-1")
    }

    func testRecordRecentDeduplicates() {
        CommandPaletteRegistry.recordRecent(id: "test-1")
        CommandPaletteRegistry.recordRecent(id: "test-2")
        CommandPaletteRegistry.recordRecent(id: "test-1") // Duplicate

        let recents = CommandPaletteRegistry.recentIds()
        XCTAssertEqual(recents.count, 2)
        XCTAssertEqual(recents[0], "test-1") // Most recent first
    }

    func testRecordRecentMaxCap() {
        for i in 1...15 {
            CommandPaletteRegistry.recordRecent(id: "item-\(i)")
        }

        let recents = CommandPaletteRegistry.recentIds()
        XCTAssertEqual(recents.count, 10, "Recent history should be capped at 10")
        XCTAssertEqual(recents[0], "item-15") // Most recent first
    }

    func testEmptyRecents() {
        let recents = CommandPaletteRegistry.recentIds()
        XCTAssertTrue(recents.isEmpty)
    }
}

// MARK: - selectConversationByIndex Tests

final class SelectConversationByIndexTests: XCTestCase {

    @MainActor
    func testSelectByIndexInRange() {
        let mockConversation = MockConversationService()
        let conv1 = Conversation(title: "첫 번째")
        let conv2 = Conversation(title: "두 번째")
        let conv3 = Conversation(title: "세 번째")
        mockConversation.save(conversation: conv1)
        mockConversation.save(conversation: conv2)
        mockConversation.save(conversation: conv3)

        let vm = DochiViewModel(
            llmService: MockLLMService(),
            toolService: MockBuiltInToolService(),
            contextService: MockContextService(),
            conversationService: mockConversation,
            keychainService: MockKeychainService(),
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: AppSettings(),
            sessionContext: SessionContext(workspaceId: UUID())
        )
        vm.loadConversations()

        // Verify conversations loaded
        XCTAssertEqual(vm.conversations.count, 3)

        // Select 2nd conversation (1-based index)
        vm.selectConversationByIndex(2)
        XCTAssertNotNil(vm.currentConversation, "Should select a conversation")
        // Conversation order is by updatedAt desc, so index 2 should map to a real conversation
        XCTAssertEqual(vm.currentConversation?.id, vm.conversations[1].id)
    }

    @MainActor
    func testSelectByIndexOutOfRange() {
        let mockConversation = MockConversationService()
        let conv = Conversation(title: "유일한 대화")
        mockConversation.save(conversation: conv)

        let vm = DochiViewModel(
            llmService: MockLLMService(),
            toolService: MockBuiltInToolService(),
            contextService: MockContextService(),
            conversationService: mockConversation,
            keychainService: MockKeychainService(),
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: AppSettings(),
            sessionContext: SessionContext(workspaceId: UUID())
        )
        vm.loadConversations()

        // Select out of range
        vm.selectConversationByIndex(5)
        XCTAssertNil(vm.currentConversation, "Should not select when index is out of range")
    }

    @MainActor
    func testSelectByIndexZero() {
        let vm = DochiViewModel(
            llmService: MockLLMService(),
            toolService: MockBuiltInToolService(),
            contextService: MockContextService(),
            conversationService: MockConversationService(),
            keychainService: MockKeychainService(),
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: AppSettings(),
            sessionContext: SessionContext(workspaceId: UUID())
        )

        // Index 0 is invalid (1-based)
        vm.selectConversationByIndex(0)
        XCTAssertNil(vm.currentConversation)
    }
}
