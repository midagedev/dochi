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

    func testRestoreSkippedWhenCurrentUserIsUnset() {
        let workspaceId = UUID()
        let sessionContext = SessionContext(workspaceId: workspaceId)
        sessionContext.currentUserId = nil

        let settings = AppSettings()
        settings.activeAgentName = "도치"

        let conversationDirectory = tempDir.appendingPathComponent("conversations")
        let conversationService = ConversationService(baseURL: conversationDirectory)
        let conversation = Conversation(userId: "user-a")
        conversationService.save(conversation: conversation)

        let store = NativeSessionStore(baseURL: tempDir)
        _ = store.activate(
            workspaceId: workspaceId,
            agentId: "도치",
            conversationId: conversation.id,
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

        XCTAssertNil(viewModel.currentConversation)
    }

    func testUpsertDoesNotOverwriteExistingSessionOwner() {
        let workspaceId = UUID()
        let conversationId = UUID()
        let store = NativeSessionStore(baseURL: tempDir)

        _ = store.activate(
            workspaceId: workspaceId,
            agentId: "도치",
            conversationId: conversationId,
            userId: "user-a"
        )
        _ = store.activate(
            workspaceId: workspaceId,
            agentId: "도치",
            conversationId: conversationId,
            userId: "user-b"
        )

        XCTAssertEqual(
            store.record(
                workspaceId: workspaceId,
                agentId: "도치",
                conversationId: conversationId
            )?.userId,
            "user-a"
        )
    }

    func testLatestRecordsPreserveUpdateOrderAcrossReload() {
        let workspaceId = UUID()
        let firstConversation = UUID()
        let secondConversation = UUID()

        let store = NativeSessionStore(baseURL: tempDir)
        _ = store.activate(
            workspaceId: workspaceId,
            agentId: "도치",
            conversationId: firstConversation,
            userId: "user-a"
        )
        _ = store.activate(
            workspaceId: workspaceId,
            agentId: "도치",
            conversationId: secondConversation,
            userId: "user-a"
        )
        _ = store.activate(
            workspaceId: workspaceId,
            agentId: "도치",
            conversationId: firstConversation,
            userId: "user-a"
        )

        let reloaded = NativeSessionStore(baseURL: tempDir)
        let latest = reloaded.latestRecords(
            workspaceId: workspaceId,
            agentId: "도치",
            userId: "user-a"
        )

        XCTAssertEqual(latest.first?.conversationId, firstConversation.uuidString)
    }

    func testLegacyStoreMigrationNormalizesRecordOrderByUpdatedAt() throws {
        let workspaceId = UUID()
        let olderConversation = UUID()
        let newerConversation = UUID()
        let agentId = "도치"
        let userId = "user-a"

        let olderDate = "2026-01-01T00:00:05Z"
        let newerDate = "2026-01-01T00:00:10Z"
        let olderResumeKey = NativeSessionStore.makeResumeKey(
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: olderConversation
        )
        let newerResumeKey = NativeSessionStore.makeResumeKey(
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: newerConversation
        )
        let legacyJSON =
            """
            {
              "records": [
                {
                  "resumeKey": "\(newerResumeKey)",
                  "workspaceId": "\(workspaceId.uuidString)",
                  "agentId": "\(agentId)",
                  "conversationId": "\(newerConversation.uuidString)",
                  "userId": "\(userId)",
                  "status": "active",
                  "createdAt": "\(newerDate)",
                  "updatedAt": "\(newerDate)"
                },
                {
                  "resumeKey": "\(olderResumeKey)",
                  "workspaceId": "\(workspaceId.uuidString)",
                  "agentId": "\(agentId)",
                  "conversationId": "\(olderConversation.uuidString)",
                  "userId": "\(userId)",
                  "status": "active",
                  "createdAt": "\(olderDate)",
                  "updatedAt": "\(olderDate)"
                }
              ],
              "version": 1
            }
            """
        try legacyJSON.write(
            to: tempDir.appendingPathComponent("native_sessions.json"),
            atomically: true,
            encoding: .utf8
        )

        let migratedStore = NativeSessionStore(baseURL: tempDir)
        let latest = migratedStore.latestRecords(
            workspaceId: workspaceId,
            agentId: agentId,
            userId: userId
        )

        XCTAssertEqual(latest.first?.conversationId, newerConversation.uuidString)
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
