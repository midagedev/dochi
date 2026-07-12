import AgentRuntimeCore
import XCTest
@testable import Dochi

@MainActor
final class DochiViewModelTests: XCTestCase {
    private func makeViewModel(
        mode: InteractionMode = .textOnly,
        approvalBroker: AgentToolApprovalBroker? = nil
    ) -> (DochiViewModel, MockHermesBridge, MockTTSService, MockSpeechService) {
        let settings = AppSettings()
        settings.interactionMode = mode.rawValue
        settings.wakeWordAlwaysOn = false
        let speech = MockSpeechService()
        let tts = MockTTSService()
        let bridge = MockHermesBridge()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dochi-tests-\(UUID().uuidString)")
        let conversations = ConversationService(baseURL: tempDir)
        let vm = DochiViewModel(
            settings: settings,
            speechService: speech,
            ttsService: tts,
            soundService: MockSoundService(),
            conversationService: conversations,
            agentBackend: bridge,
            approvalBroker: approvalBroker
        )
        return (vm, bridge, tts, speech)
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testTextSendAppendsUserAndAssistantThenReturnsIdle() async {
        let (vm, bridge, _, _) = makeViewModel(mode: .textOnly)
        bridge.scriptedEvents = [.delta("안녕"), .delta("하세요"), .done(text: "안녕하세요", messageId: nil)]

        vm.inputText = "테스트"
        vm.sendMessage()

        await waitUntil { vm.interactionState == .idle && vm.messages.count >= 2 }

        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertEqual(vm.messages.first?.role, .user)
        XCTAssertEqual(vm.messages.first?.content, "테스트")
        XCTAssertEqual(vm.messages.last?.role, .assistant)
        XCTAssertEqual(vm.messages.last?.content, "안녕하세요")
        XCTAssertEqual(vm.interactionState, .idle)
        XCTAssertEqual(bridge.sentMessages, ["테스트"])
        XCTAssertTrue(vm.streamingText.isEmpty)
    }

    func testConversationKeepsItsOriginalMemoryIdentity() async {
        let (vm, bridge, _, _) = makeViewModel(mode: .textOnly)
        let previousDefaultUserID = vm.settings.defaultUserId
        defer { vm.settings.defaultUserId = previousDefaultUserID }
        vm.settings.defaultUserId = "original-user"
        vm.newConversation()
        vm.settings.defaultUserId = "different-user"
        bridge.scriptedEvents = [.done(text: "응답", messageId: nil)]

        vm.inputText = "질문"
        vm.sendMessage()
        await waitUntil { vm.interactionState == .idle && vm.messages.count >= 2 }

        XCTAssertEqual(bridge.sentUsers.count, 1)
        XCTAssertEqual(bridge.sentUsers[0], "original-user")
    }

    func testAssistantMarkdownImageIsStoredAsImageURL() async {
        let (vm, bridge, _, _) = makeViewModel(mode: .textOnly)
        bridge.scriptedEvents = [
            .done(text: "그림 만들었어.\n![생성 이미지](https://v3.fal.media/files/test/result.png)", messageId: nil)
        ]

        vm.inputText = "그림 그려줘"
        vm.sendMessage()

        await waitUntil { vm.interactionState == .idle && vm.messages.count >= 2 }

        let assistant = vm.messages.last
        XCTAssertEqual(assistant?.role, .assistant)
        XCTAssertEqual(assistant?.content, "그림 만들었어.")
        XCTAssertEqual(assistant?.imageURLs?.first?.absoluteString, "https://v3.fal.media/files/test/result.png")
    }

    func testAssistantToolJSONImageIsStoredAsImageURL() async {
        let (vm, bridge, _, _) = makeViewModel(mode: .textOnly)
        bridge.scriptedEvents = [
            .done(text: #"{"success": true, "image": "https://v3.fal.media/files/test/result.webp"}"#, messageId: nil)
        ]

        vm.inputText = "그림 그려줘"
        vm.sendMessage()

        await waitUntil { vm.interactionState == .idle && vm.messages.count >= 2 }

        let assistant = vm.messages.last
        XCTAssertEqual(assistant?.role, .assistant)
        XCTAssertEqual(assistant?.content, "")
        XCTAssertEqual(assistant?.imageURLs?.first?.absoluteString, "https://v3.fal.media/files/test/result.webp")
    }

    func testSendWhenDisconnectedSetsErrorAndKeepsNoAssistantMessage() async {
        let (vm, bridge, _, _) = makeViewModel(mode: .textOnly)
        bridge.connectionState = .disconnected

        vm.inputText = "안녕"
        vm.sendMessage()

        await waitUntil { vm.errorMessage != nil }

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertEqual(vm.interactionState, .idle)
        // user message was appended, but no assistant reply
        XCTAssertFalse(vm.messages.contains { $0.role == .assistant })
    }

    func testVoiceFinalResultStreamsToTTSAndResumesListening() async {
        let (vm, bridge, tts, speech) = makeViewModel(mode: .voiceAndText)
        bridge.scriptedEvents = [.delta("좋은 아침이에요."), .done(text: "좋은 아침이에요.", messageId: nil)]

        vm.startListening()                        // session becomes active, listening
        XCTAssertEqual(vm.interactionState, .listening)

        speech.emitFinal("도치야 안녕")              // user finished speaking
        await waitUntil { vm.interactionState == .speaking || !tts.enqueued.isEmpty }

        XCTAssertFalse(tts.enqueued.isEmpty, "assistant reply should be spoken")
        XCTAssertEqual(vm.interactionState, .speaking)

        let listensBefore = speech.startListeningCallCount
        tts.finishSpeaking()                        // audio playback completes
        await waitUntil { vm.interactionState == .listening }

        XCTAssertEqual(vm.interactionState, .listening)
        XCTAssertGreaterThan(speech.startListeningCallCount, listensBefore)
    }

    func testProactiveMessageIsAppendedAsAssistant() async {
        let (vm, bridge, _, _) = makeViewModel(mode: .textOnly)
        bridge.emitProactive("회의가 10분 뒤에 시작돼요.")
        await waitUntil { vm.messages.contains { $0.role == .assistant } }
        XCTAssertEqual(vm.messages.last?.content, "회의가 10분 뒤에 시작돼요.")
    }

    func testCancellingRequestDeniesPendingToolApproval() async {
        let broker = AgentToolApprovalBroker()
        let (vm, _, _, _) = makeViewModel(approvalBroker: broker)
        let request = AgentToolApprovalRequest(
            call: AgentToolCall(
                id: "approval",
                name: "sensitive_tool",
                arguments: .object([:])
            ),
            descriptor: AgentToolDescriptor(
                name: "sensitive_tool",
                description: "민감한 테스트 도구",
                inputSchema: .object(["type": .string("object")]),
                risk: .sensitive
            ),
            reason: "승인이 필요합니다.",
            context: AgentToolExecutionContext(
                runID: UUID(),
                sessionID: "session",
                appID: "com.hckim.dochi",
                userID: nil,
                agentID: "dochi-native"
            )
        )
        let decisionTask = Task { await broker.requestApproval(request) }
        await waitUntil { vm.pendingToolApproval?.id == request.id }

        vm.cancelRequest()
        let decision = await decisionTask.value

        XCTAssertNil(vm.pendingToolApproval)
        guard case .deny = decision else {
            return XCTFail("Cancelling a request must deny its pending approval")
        }
    }

    func testToolEventsSurfaceAsToolExecutions() async {
        let (vm, bridge, _, _) = makeViewModel(mode: .textOnly)
        bridge.scriptedEvents = [
            .toolStarted(name: "web_search", summary: "날씨 검색"),
            .delta("오늘은 맑아요."),
            .toolFinished(name: "web_search", isError: false, summary: "완료"),
            .done(text: "오늘은 맑아요.", messageId: nil),
        ]
        vm.inputText = "날씨 알려줘"
        vm.sendMessage()
        await waitUntil { vm.interactionState == .idle && !vm.toolExecutions.isEmpty }

        XCTAssertEqual(vm.toolExecutions.count, 1)
        XCTAssertEqual(vm.toolExecutions.first?.toolName, "web_search")
    }
}
