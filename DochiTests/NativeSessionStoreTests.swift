import XCTest
@testable import Dochi

@MainActor
final class NativeSessionStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NativeSessionStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testResumeKeyUsesWorkspaceAgentConversationTriplet() {
        let workspaceId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let conversationId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let key = NativeSessionStore.makeResumeKey(
            workspaceId: workspaceId,
            agentId: "도치",
            conversationId: conversationId
        )
        XCTAssertEqual(
            key,
            "11111111-1111-1111-1111-111111111111:도치:22222222-2222-2222-2222-222222222222"
        )
    }

    func testInterruptAndRecoverTransition() {
        let store = NativeSessionStore(baseURL: tempDir)
        let workspaceId = UUID()
        let conversationId = UUID()

        _ = store.activate(
            workspaceId: workspaceId,
            agentId: "도치",
            conversationId: conversationId
        )
        let interrupted = store.interrupt(
            workspaceId: workspaceId,
            agentId: "도치",
            conversationId: conversationId
        )
        XCTAssertEqual(interrupted.status, .interrupted)

        let recovered = store.recoverIfInterrupted(
            workspaceId: workspaceId,
            agentId: "도치",
            conversationId: conversationId
        )
        XCTAssertEqual(recovered?.status, .active)
    }

    func testStorePersistsRecordsAcrossInstances() {
        let workspaceId = UUID()
        let firstConversation = UUID()
        let secondConversation = UUID()

        let firstStore = NativeSessionStore(baseURL: tempDir)
        _ = firstStore.activate(
            workspaceId: workspaceId,
            agentId: "도치",
            conversationId: firstConversation,
            userId: "user-a"
        )
        _ = firstStore.interrupt(
            workspaceId: workspaceId,
            agentId: "도치",
            conversationId: secondConversation,
            userId: "user-a"
        )

        let reloaded = NativeSessionStore(baseURL: tempDir)
        XCTAssertEqual(
            reloaded.record(
                workspaceId: workspaceId,
                agentId: "도치",
                conversationId: firstConversation
            )?.userId,
            "user-a"
        )
        XCTAssertEqual(
            reloaded.record(
                workspaceId: workspaceId,
                agentId: "도치",
                conversationId: firstConversation
            )?.status,
            .active
        )
        XCTAssertEqual(
            reloaded.record(
                workspaceId: workspaceId,
                agentId: "도치",
                conversationId: secondConversation
            )?.status,
            .interrupted
        )
    }

    func testViewModelRestoresConversationAfterRestart() {
        let workspaceId = UUID()
        let sessionContext = SessionContext(workspaceId: workspaceId)
        sessionContext.currentUserId = "user-a"
        let settings = AppSettings()
        settings.activeAgentName = "도치"

        let conversationDirectory = tempDir.appendingPathComponent("conversations")
        let conversationService = ConversationService(baseURL: conversationDirectory)
        var conversation = Conversation(userId: sessionContext.currentUserId)
        conversation.messages.append(Message(role: .user, content: "hello"))
        conversationService.save(conversation: conversation)

        let firstStore = NativeSessionStore(baseURL: tempDir)
        let firstViewModel = makeViewModel(
            settings: settings,
            sessionContext: sessionContext,
            conversationService: conversationService,
            nativeSessionStore: firstStore
        )
        firstViewModel.loadConversations()
        firstViewModel.selectConversation(id: conversation.id)
        XCTAssertEqual(firstViewModel.currentConversation?.id, conversation.id)

        let secondStore = NativeSessionStore(baseURL: tempDir)
        let secondViewModel = makeViewModel(
            settings: settings,
            sessionContext: sessionContext,
            conversationService: conversationService,
            nativeSessionStore: secondStore
        )
        secondViewModel.loadConversations()
        secondViewModel.restoreNativeSessionIfNeeded()

        XCTAssertEqual(secondViewModel.currentConversation?.id, conversation.id)
    }

    func testRestoreFallsBackToOlderValidRecordWhenLatestIsMissing() {
        let workspaceId = UUID()
        let sessionContext = SessionContext(workspaceId: workspaceId)
        sessionContext.currentUserId = "user-a"

        let settings = AppSettings()
        settings.activeAgentName = "도치"

        let conversationDirectory = tempDir.appendingPathComponent("conversations")
        let conversationService = ConversationService(baseURL: conversationDirectory)
        let validConversation = Conversation(userId: "user-a")
        conversationService.save(conversation: validConversation)

        let missingConversationId = UUID()

        let store = NativeSessionStore(baseURL: tempDir)
        _ = store.activate(
            workspaceId: workspaceId,
            agentId: "도치",
            conversationId: validConversation.id,
            userId: "user-a"
        )
        Thread.sleep(forTimeInterval: 0.01)
        _ = store.activate(
            workspaceId: workspaceId,
            agentId: "도치",
            conversationId: missingConversationId,
            userId: "user-a"
        )

        let viewModel = makeViewModel(
            settings: settings,
            sessionContext: sessionContext,
            conversationService: conversationService,
            nativeSessionStore: store
        )
        viewModel.loadConversations()
        viewModel.restoreNativeSessionIfNeeded()

        XCTAssertEqual(viewModel.currentConversation?.id, validConversation.id)
        XCTAssertNil(store.record(
            workspaceId: workspaceId,
            agentId: "도치",
            conversationId: missingConversationId
        ))
    }

    func testRestoreSkipsConversationFromDifferentUser() {
        let workspaceId = UUID()
        let sessionContext = SessionContext(workspaceId: workspaceId)
        sessionContext.currentUserId = "user-a"

        let settings = AppSettings()
        settings.activeAgentName = "도치"

        let conversationDirectory = tempDir.appendingPathComponent("conversations")
        let conversationService = ConversationService(baseURL: conversationDirectory)
        let userAConversation = Conversation(userId: "user-a")
        let userBConversation = Conversation(userId: "user-b")
        conversationService.save(conversation: userAConversation)
        conversationService.save(conversation: userBConversation)

        let store = NativeSessionStore(baseURL: tempDir)
        _ = store.activate(
            workspaceId: workspaceId,
            agentId: "도치",
            conversationId: userAConversation.id,
            userId: "user-a"
        )
        Thread.sleep(forTimeInterval: 0.01)
        _ = store.activate(
            workspaceId: workspaceId,
            agentId: "도치",
            conversationId: userBConversation.id,
            userId: "user-b"
        )

        let viewModel = makeViewModel(
            settings: settings,
            sessionContext: sessionContext,
            conversationService: conversationService,
            nativeSessionStore: store
        )
        viewModel.loadConversations()
        viewModel.restoreNativeSessionIfNeeded()

        XCTAssertEqual(viewModel.currentConversation?.id, userAConversation.id)
    }

    private func makeViewModel(
        settings: AppSettings,
        sessionContext: SessionContext,
        conversationService: ConversationServiceProtocol,
        nativeSessionStore: NativeSessionStore
    ) -> DochiViewModel {
        DochiViewModel(
            toolService: MockBuiltInToolService(),
            contextService: MockContextService(),
            conversationService: conversationService,
            keychainService: MockKeychainService(),
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: settings,
            sessionContext: sessionContext,
            nativeSessionStore: nativeSessionStore
        )
    }
}
