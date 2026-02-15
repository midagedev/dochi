import XCTest
@testable import Dochi

/// SpotlightIndexer 및 딥링크 파싱 테스트 (H-4)
@MainActor
final class SpotlightIndexerTests: XCTestCase {

    // MARK: - Deep Link Parsing

    func testParseConversationDeepLink() {
        let uuid = UUID()
        let url = URL(string: "dochi://conversation/\(uuid.uuidString)")!
        let result = SpotlightIndexer.parseDeepLink(url: url)
        XCTAssertEqual(result, .conversation(id: uuid))
    }

    func testParseUserMemoryDeepLink() {
        let url = URL(string: "dochi://memory/user/test-user-123")!
        let result = SpotlightIndexer.parseDeepLink(url: url)
        XCTAssertEqual(result, .memoryUser(userId: "test-user-123"))
    }

    func testParseAgentMemoryDeepLink() {
        let wsId = UUID().uuidString
        let url = URL(string: "dochi://memory/agent/\(wsId)/MyAgent")!
        let result = SpotlightIndexer.parseDeepLink(url: url)
        XCTAssertEqual(result, .memoryAgent(workspaceId: wsId, agentName: "MyAgent"))
    }

    func testParseWorkspaceMemoryDeepLink() {
        let wsId = UUID().uuidString
        let url = URL(string: "dochi://memory/workspace/\(wsId)")!
        let result = SpotlightIndexer.parseDeepLink(url: url)
        XCTAssertEqual(result, .memoryWorkspace(workspaceId: wsId))
    }

    func testParseInvalidScheme() {
        let url = URL(string: "https://example.com/conversation/123")!
        let result = SpotlightIndexer.parseDeepLink(url: url)
        XCTAssertNil(result)
    }

    func testParseInvalidHost() {
        let url = URL(string: "dochi://unknown/something")!
        let result = SpotlightIndexer.parseDeepLink(url: url)
        XCTAssertNil(result)
    }

    func testParseConversationWithInvalidUUID() {
        let url = URL(string: "dochi://conversation/not-a-uuid")!
        let result = SpotlightIndexer.parseDeepLink(url: url)
        XCTAssertNil(result)
    }

    func testParseMemoryWithMissingComponents() {
        let url = URL(string: "dochi://memory/user")!
        let result = SpotlightIndexer.parseDeepLink(url: url)
        XCTAssertNil(result)
    }

    func testParseAgentMemoryWithMissingAgent() {
        let url = URL(string: "dochi://memory/agent/some-ws-id")!
        let result = SpotlightIndexer.parseDeepLink(url: url)
        XCTAssertNil(result)
    }

    // MARK: - Mock Indexer Integration

    func testMockIndexerIndexConversation() {
        let mock = MockSpotlightIndexer()
        let conversation = Conversation(title: "테스트 대화")
        mock.indexConversation(conversation)

        XCTAssertEqual(mock.indexedConversations.count, 1)
        XCTAssertEqual(mock.indexedConversations.first?.title, "테스트 대화")
        XCTAssertEqual(mock.indexedItemCount, 1)
        XCTAssertNotNil(mock.lastIndexedAt)
    }

    func testMockIndexerRemoveConversation() {
        let mock = MockSpotlightIndexer()
        let id = UUID()
        mock.indexedItemCount = 5
        mock.removeConversation(id: id)

        XCTAssertEqual(mock.removedConversationIds, [id])
        XCTAssertEqual(mock.indexedItemCount, 4)
    }

    func testMockIndexerIndexMemory() {
        let mock = MockSpotlightIndexer()
        mock.indexMemory(scope: "personal", identifier: "user-123", title: "메모리", content: "테스트 내용")

        XCTAssertEqual(mock.indexedMemories.count, 1)
        XCTAssertEqual(mock.indexedMemories.first?.scope, "personal")
        XCTAssertEqual(mock.indexedMemories.first?.identifier, "user-123")
        XCTAssertEqual(mock.indexedItemCount, 1)
    }

    func testMockIndexerRemoveMemory() {
        let mock = MockSpotlightIndexer()
        mock.indexedItemCount = 3
        mock.removeMemory(identifier: "user-123")

        XCTAssertEqual(mock.removedMemoryIdentifiers, ["user-123"])
        XCTAssertEqual(mock.indexedItemCount, 2)
    }

    func testMockIndexerRebuild() async {
        let mock = MockSpotlightIndexer()
        let conversations = [Conversation(title: "대화1"), Conversation(title: "대화2")]
        let contextService = MockContextService()
        let sessionContext = SessionContext(workspaceId: UUID())

        await mock.rebuildAllIndices(
            conversations: conversations,
            contextService: contextService,
            sessionContext: sessionContext
        )

        XCTAssertEqual(mock.rebuildCallCount, 1)
        XCTAssertEqual(mock.indexedItemCount, 2)
        XCTAssertNotNil(mock.lastIndexedAt)
    }

    func testMockIndexerClear() async {
        let mock = MockSpotlightIndexer()
        mock.indexedItemCount = 10
        mock.lastIndexedAt = Date()

        await mock.clearAllIndices()

        XCTAssertEqual(mock.clearCallCount, 1)
        XCTAssertEqual(mock.indexedItemCount, 0)
        XCTAssertNil(mock.lastIndexedAt)
    }

    // MARK: - ViewModel Deep Link Handling

    func testViewModelHandleDeepLinkConversation() {
        let conversationService = MockConversationService()
        let uuid = UUID()
        let conversation = Conversation(id: uuid, title: "테스트 대화")
        conversationService.conversations[uuid] = conversation

        let vm = DochiViewModel(
            llmService: MockLLMService(),
            toolService: MockBuiltInToolService(),
            contextService: MockContextService(),
            conversationService: conversationService,
            keychainService: MockKeychainService(),
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: AppSettings(),
            sessionContext: SessionContext(workspaceId: UUID())
        )

        let url = URL(string: "dochi://conversation/\(uuid.uuidString)")!
        vm.handleDeepLink(url: url)

        XCTAssertEqual(vm.currentConversation?.id, uuid)
    }

    func testViewModelHandleDeepLinkMemory() {
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

        let url = URL(string: "dochi://memory/user/test-user")!
        vm.handleDeepLink(url: url)

        XCTAssertTrue(vm.notificationShowMemoryPanel)
    }

    func testViewModelHandleInvalidDeepLink() {
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

        let url = URL(string: "dochi://invalid/path")!
        vm.handleDeepLink(url: url)

        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - ViewModel Spotlight Indexer Integration

    func testViewModelDeleteConversationRemovesFromIndex() {
        let conversationService = MockConversationService()
        let uuid = UUID()
        conversationService.conversations[uuid] = Conversation(id: uuid, title: "삭제할 대화")

        let vm = DochiViewModel(
            llmService: MockLLMService(),
            toolService: MockBuiltInToolService(),
            contextService: MockContextService(),
            conversationService: conversationService,
            keychainService: MockKeychainService(),
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: AppSettings(),
            sessionContext: SessionContext(workspaceId: UUID())
        )

        let mockIndexer = MockSpotlightIndexer()
        vm.configureSpotlightIndexer(mockIndexer)

        vm.deleteConversation(id: uuid)

        XCTAssertEqual(mockIndexer.removedConversationIds, [uuid])
    }

    // MARK: - concreteSpotlightIndexer (C-1 fix)

    func testConcreteSpotlightIndexerReturnsNilForMock() {
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

        // Mock 인덱서는 SpotlightIndexer 구체 타입이 아니므로 nil 반환
        let mockIndexer = MockSpotlightIndexer()
        vm.configureSpotlightIndexer(mockIndexer)
        XCTAssertNil(vm.concreteSpotlightIndexer)
    }

    func testConcreteSpotlightIndexerReturnsConcreteType() {
        let settings = AppSettings()
        let vm = DochiViewModel(
            llmService: MockLLMService(),
            toolService: MockBuiltInToolService(),
            contextService: MockContextService(),
            conversationService: MockConversationService(),
            keychainService: MockKeychainService(),
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: settings,
            sessionContext: SessionContext(workspaceId: UUID())
        )

        let realIndexer = SpotlightIndexer(settings: settings)
        vm.configureSpotlightIndexer(realIndexer)
        XCTAssertNotNil(vm.concreteSpotlightIndexer)
        XCTAssertTrue(vm.concreteSpotlightIndexer === realIndexer)
    }

    // MARK: - contentURLPath (C-4 fix)

    func testContentURLPathPersonal() {
        let uuid = UUID().uuidString
        let result = SpotlightIndexer.contentURLPath(scope: "personal", identifier: "user-\(uuid)")
        XCTAssertEqual(result, "user/\(uuid)")
    }

    func testContentURLPathWorkspace() {
        let uuid = UUID().uuidString
        let result = SpotlightIndexer.contentURLPath(scope: "workspace", identifier: "workspace-\(uuid)")
        XCTAssertEqual(result, "workspace/\(uuid)")
    }

    func testContentURLPathAgent() {
        let wsId = UUID().uuidString
        let agentName = "MyAgent"
        let result = SpotlightIndexer.contentURLPath(scope: "agent", identifier: "agent-\(wsId)-\(agentName)")
        XCTAssertEqual(result, "agent/\(wsId)/\(agentName)")
    }

    func testContentURLPathProducesValidDeepLink() {
        // indexMemory()가 생성하는 URL이 parseDeepLink()로 올바르게 파싱되는지 검증
        let userId = UUID().uuidString
        let path = SpotlightIndexer.contentURLPath(scope: "personal", identifier: "user-\(userId)")
        let url = URL(string: "dochi://memory/\(path)")!
        let result = SpotlightIndexer.parseDeepLink(url: url)
        XCTAssertEqual(result, .memoryUser(userId: userId))
    }

    func testContentURLPathWorkspaceProducesValidDeepLink() {
        let wsId = UUID().uuidString
        let path = SpotlightIndexer.contentURLPath(scope: "workspace", identifier: "workspace-\(wsId)")
        let url = URL(string: "dochi://memory/\(path)")!
        let result = SpotlightIndexer.parseDeepLink(url: url)
        XCTAssertEqual(result, .memoryWorkspace(workspaceId: wsId))
    }

    func testContentURLPathAgentProducesValidDeepLink() {
        let wsId = UUID().uuidString
        let agentName = "TestAgent"
        let path = SpotlightIndexer.contentURLPath(scope: "agent", identifier: "agent-\(wsId)-\(agentName)")
        let url = URL(string: "dochi://memory/\(path)")!
        let result = SpotlightIndexer.parseDeepLink(url: url)
        XCTAssertEqual(result, .memoryAgent(workspaceId: wsId, agentName: agentName))
    }

    func testContentURLPathUnknownScopePassesThrough() {
        let result = SpotlightIndexer.contentURLPath(scope: "unknown", identifier: "some-id")
        XCTAssertEqual(result, "some-id")
    }

    // MARK: - AppSettings Defaults

    func testSpotlightSettingsDefaults() {
        let settings = AppSettings()
        XCTAssertTrue(settings.spotlightIndexingEnabled)
        XCTAssertTrue(settings.spotlightIndexConversations)
        XCTAssertTrue(settings.spotlightIndexPersonalMemory)
        XCTAssertTrue(settings.spotlightIndexAgentMemory)
        XCTAssertTrue(settings.spotlightIndexWorkspaceMemory)
    }
}
