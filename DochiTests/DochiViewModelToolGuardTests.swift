import XCTest
@testable import Dochi

@MainActor
final class DochiViewModelToolGuardTests: XCTestCase {
    func testRepeatedToolsEnableIsBlocked() async {
        let llmService = MockLLMService()
        llmService.stubbedResponses = [
            .toolCalls([
                CodableToolCall(
                    id: "tc1",
                    name: "tools-_-enable",
                    argumentsJSON: #"{"names":["open_url"]}"#
                ),
            ]),
            .toolCalls([
                CodableToolCall(
                    id: "tc2",
                    name: "tools-_-enable",
                    argumentsJSON: #"{"names":["open_url"]}"#
                ),
            ]),
            .text("완료"),
        ]

        let toolService = MockBuiltInToolService()
        let viewModel = makeViewModel(llmService: llmService, toolService: toolService)

        viewModel.inputText = "세션 상태 확인해줘"
        viewModel.sendMessage()
        await waitUntilIdle(viewModel)

        XCTAssertEqual(toolService.executeCallCount, 1)
        let blockedMessage = viewModel.currentConversation?.messages.last(where: {
            $0.role == .tool && $0.content.contains("제어 도구 호출 차단")
        })
        XCTAssertNotNil(blockedMessage)
    }

    func testSameToolSameArgumentsThirdCallIsBlocked() async {
        let llmService = MockLLMService()
        llmService.stubbedResponses = [
            .toolCalls([
                CodableToolCall(
                    id: "tc1",
                    name: "web_search",
                    argumentsJSON: #"{"query":"swift"}"#
                ),
            ]),
            .toolCalls([
                CodableToolCall(
                    id: "tc2",
                    name: "web_search",
                    argumentsJSON: #"{"query":"swift"}"#
                ),
            ]),
            .toolCalls([
                CodableToolCall(
                    id: "tc3",
                    name: "web_search",
                    argumentsJSON: #"{"query":"swift"}"#
                ),
            ]),
            .text("완료"),
        ]

        let toolService = MockBuiltInToolService()
        let viewModel = makeViewModel(llmService: llmService, toolService: toolService)

        viewModel.inputText = "swift 검색해줘"
        viewModel.sendMessage()
        await waitUntilIdle(viewModel)

        XCTAssertEqual(toolService.executeCallCount, 2)
        let blockedMessage = viewModel.currentConversation?.messages.last(where: {
            $0.role == .tool && $0.content.contains("반복 호출 차단")
        })
        XCTAssertNotNil(blockedMessage)
    }

    // MARK: - Helpers

    private func makeViewModel(
        llmService: MockLLMService,
        toolService: MockBuiltInToolService
    ) -> DochiViewModel {
        let settings = AppSettings()
        let wsId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let sessionContext = SessionContext(workspaceId: wsId)

        let keychainService = MockKeychainService()
        keychainService.store["openai_api_key"] = "sk-test"

        return DochiViewModel(
            llmService: llmService,
            toolService: toolService,
            contextService: MockContextService(),
            conversationService: MockConversationService(),
            keychainService: keychainService,
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: settings,
            sessionContext: sessionContext
        )
    }

    private func waitUntilIdle(_ viewModel: DochiViewModel, timeout: TimeInterval = 2.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while viewModel.interactionState != .idle && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
