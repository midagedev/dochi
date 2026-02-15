import XCTest
@testable import Dochi

/// UX-8: 메모리 패널/토스트/참조 배지 모델 테스트
final class MemoryPanelTests: XCTestCase {

    // MARK: - MemoryContextInfo Tests

    func testMemoryContextInfoTotalLength() {
        let info = MemoryContextInfo(
            systemPromptLength: 100,
            agentPersonaLength: 50,
            workspaceMemoryLength: 200,
            agentMemoryLength: 30,
            personalMemoryLength: 80
        )
        XCTAssertEqual(info.totalLength, 460)
    }

    func testMemoryContextInfoEstimatedTokens() {
        let info = MemoryContextInfo(
            systemPromptLength: 100,
            agentPersonaLength: 0,
            workspaceMemoryLength: 0,
            agentMemoryLength: 0,
            personalMemoryLength: 0
        )
        XCTAssertEqual(info.estimatedTokens, 50)
    }

    func testMemoryContextInfoHasAnyMemory() {
        let emptyInfo = MemoryContextInfo(
            systemPromptLength: 0,
            agentPersonaLength: 0,
            workspaceMemoryLength: 0,
            agentMemoryLength: 0,
            personalMemoryLength: 0
        )
        XCTAssertFalse(emptyInfo.hasAnyMemory)

        let nonEmptyInfo = MemoryContextInfo(
            systemPromptLength: 10,
            agentPersonaLength: 0,
            workspaceMemoryLength: 0,
            agentMemoryLength: 0,
            personalMemoryLength: 0
        )
        XCTAssertTrue(nonEmptyInfo.hasAnyMemory)
    }

    func testMemoryContextInfoActiveLayerCount() {
        let info = MemoryContextInfo(
            systemPromptLength: 100,
            agentPersonaLength: 0,
            workspaceMemoryLength: 50,
            agentMemoryLength: 0,
            personalMemoryLength: 30
        )
        XCTAssertEqual(info.activeLayerCount, 3)
    }

    func testMemoryContextInfoLayers() {
        let info = MemoryContextInfo(
            systemPromptLength: 100,
            agentPersonaLength: 50,
            workspaceMemoryLength: 0,
            agentMemoryLength: 0,
            personalMemoryLength: 0
        )
        let layers = info.layers
        XCTAssertEqual(layers.count, 5)
        XCTAssertTrue(layers[0].isActive)
        XCTAssertTrue(layers[1].isActive)
        XCTAssertFalse(layers[2].isActive)
        XCTAssertFalse(layers[3].isActive)
        XCTAssertFalse(layers[4].isActive)
    }

    func testMemoryContextInfoCodableRoundTrip() throws {
        let original = MemoryContextInfo(
            systemPromptLength: 100,
            agentPersonaLength: 50,
            workspaceMemoryLength: 200,
            agentMemoryLength: 30,
            personalMemoryLength: 80
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MemoryContextInfo.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - MemoryToastEvent Tests

    func testMemoryToastEventDisplayMessage() {
        let event = MemoryToastEvent(
            scope: .personal,
            action: .saved,
            contentPreview: "좋아하는 음식: 피자"
        )
        XCTAssertEqual(event.displayMessage, "개인 메모리에 저장됨")
    }

    func testMemoryToastEventWorkspaceScope() {
        let event = MemoryToastEvent(
            scope: .workspace,
            action: .updated,
            contentPreview: "프로젝트 마일스톤 변경"
        )
        XCTAssertEqual(event.displayMessage, "워크스페이스 메모리에 업데이트됨")
    }

    func testMemoryToastEventContentPreviewTruncation() {
        let longContent = String(repeating: "가", count: 200)
        let event = MemoryToastEvent(scope: .personal, action: .saved, contentPreview: longContent)
        XCTAssertEqual(event.contentPreview.count, 80)
    }

    func testMemoryToastEventAgentScope() {
        let event = MemoryToastEvent(
            scope: .agent,
            action: .saved,
            contentPreview: "새로운 학습 내용"
        )
        XCTAssertEqual(event.displayMessage, "에이전트 메모리에 저장됨")
    }

    // MARK: - Message with MemoryContextInfo Tests

    func testMessageWithMemoryContextInfo() throws {
        let info = MemoryContextInfo(
            systemPromptLength: 100,
            agentPersonaLength: 50,
            workspaceMemoryLength: 0,
            agentMemoryLength: 0,
            personalMemoryLength: 0
        )
        let message = Message(
            role: .assistant,
            content: "안녕하세요!",
            memoryContextInfo: info
        )
        XCTAssertNotNil(message.memoryContextInfo)
        XCTAssertEqual(message.memoryContextInfo?.totalLength, 150)
    }

    func testMessageWithoutMemoryContextInfo() {
        let message = Message(role: .assistant, content: "테스트")
        XCTAssertNil(message.memoryContextInfo)
    }

    func testMessageMemoryContextInfoCodableRoundTrip() throws {
        let info = MemoryContextInfo(
            systemPromptLength: 100,
            agentPersonaLength: 50,
            workspaceMemoryLength: 200,
            agentMemoryLength: 30,
            personalMemoryLength: 80
        )
        let message = Message(
            role: .assistant,
            content: "테스트 응답",
            memoryContextInfo: info
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Message.self, from: data)

        XCTAssertEqual(decoded.memoryContextInfo?.totalLength, 460)
        XCTAssertEqual(decoded.memoryContextInfo?.activeLayerCount, 5)
    }

    func testMessageWithoutMemoryContextInfoBackwardsCompatible() throws {
        // Simulate old JSON without memoryContextInfo field
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "role": "assistant",
            "content": "Hello",
            "timestamp": "2026-01-01T00:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(Message.self, from: data)

        XCTAssertNil(message.memoryContextInfo)
        XCTAssertEqual(message.content, "Hello")
    }

    // MARK: - ViewModel Memory Toast Tests

    @MainActor
    func testViewModelShowMemoryToast() {
        let contextService = MockContextService()
        let viewModel = makeViewModel(contextService: contextService)

        viewModel.showMemoryToast(scope: .personal, action: .saved, contentPreview: "좋아하는 음식: 피자")
        XCTAssertEqual(viewModel.memoryToastEvents.count, 1)
        XCTAssertEqual(viewModel.memoryToastEvents[0].scope, .personal)
    }

    @MainActor
    func testViewModelDismissMemoryToast() {
        let contextService = MockContextService()
        let viewModel = makeViewModel(contextService: contextService)

        viewModel.showMemoryToast(scope: .workspace, action: .saved, contentPreview: "테스트")
        let eventId = viewModel.memoryToastEvents[0].id
        viewModel.dismissMemoryToast(id: eventId)
        XCTAssertTrue(viewModel.memoryToastEvents.isEmpty)
    }

    @MainActor
    func testViewModelBuildMemoryContextInfo() {
        let contextService = MockContextService()
        contextService.baseSystemPrompt = "You are a helpful assistant."
        let wsId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        contextService.workspaceMemory[wsId] = "프로젝트 관련 메모"

        let settings = AppSettings()
        let sessionContext = SessionContext(workspaceId: wsId, currentUserId: "user1")
        contextService.userMemory["user1"] = "좋아하는 음식: 피자"

        let viewModel = makeViewModel(
            contextService: contextService,
            settings: settings,
            sessionContext: sessionContext
        )
        let info = viewModel.buildMemoryContextInfo()

        XCTAssertTrue(info.hasAnyMemory)
        XCTAssertEqual(info.systemPromptLength, "You are a helpful assistant.".count)
        XCTAssertEqual(info.workspaceMemoryLength, "프로젝트 관련 메모".count)
        XCTAssertEqual(info.personalMemoryLength, "좋아하는 음식: 피자".count)
    }

    @MainActor
    func testViewModelBuildMemoryContextInfoEmpty() {
        let contextService = MockContextService()
        let viewModel = makeViewModel(contextService: contextService)
        let info = viewModel.buildMemoryContextInfo()
        XCTAssertFalse(info.hasAnyMemory)
        XCTAssertEqual(info.totalLength, 0)
    }

    // MARK: - Helper

    @MainActor
    private func makeViewModel(
        contextService: MockContextService = MockContextService(),
        settings: AppSettings = AppSettings(),
        sessionContext: SessionContext? = nil
    ) -> DochiViewModel {
        let wsId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let ctx = sessionContext ?? SessionContext(workspaceId: wsId)
        return DochiViewModel(
            llmService: MockLLMService(),
            toolService: MockBuiltInToolService(),
            contextService: contextService,
            conversationService: MockConversationService(),
            keychainService: MockKeychainService(),
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: settings,
            sessionContext: ctx
        )
    }
}
