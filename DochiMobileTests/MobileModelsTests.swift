import AgentRuntimeCore
import AgentRuntimeMemory
import Foundation
import XCTest
@testable import DochiMobile

final class MobileCompatibleEndpointTests: XCTestCase {
    func testHTTPSBaseBuildsChatCompletionsEndpoint() throws {
        let endpoint = try MobileCompatibleEndpoint.chatCompletionsEndpoint(
            from: "https://models.example.com/v1"
        )
        XCTAssertEqual(endpoint.absoluteString, "https://models.example.com/v1/chat/completions")
    }

    func testExistingChatCompletionsEndpointIsNotDuplicated() throws {
        let endpoint = try MobileCompatibleEndpoint.chatCompletionsEndpoint(
            from: "https://models.example.com/custom/chat/completions"
        )
        XCTAssertEqual(endpoint.absoluteString, "https://models.example.com/custom/chat/completions")
    }

    func testRootBaseReceivesV1Path() throws {
        let endpoint = try MobileCompatibleEndpoint.chatCompletionsEndpoint(
            from: "https://models.example.com"
        )
        XCTAssertEqual(endpoint.absoluteString, "https://models.example.com/v1/chat/completions")
    }

    func testHTTPIsAllowedOnlyForLoopback() throws {
        XCTAssertNoThrow(try MobileCompatibleEndpoint.validatedBaseURL(from: "http://localhost:11434/v1"))
        XCTAssertNoThrow(try MobileCompatibleEndpoint.validatedBaseURL(from: "http://127.42.0.9:11434/v1"))
        XCTAssertNoThrow(try MobileCompatibleEndpoint.validatedBaseURL(from: "http://[::1]:11434/v1"))
        XCTAssertThrowsError(try MobileCompatibleEndpoint.validatedBaseURL(from: "http://192.168.1.10:11434/v1")) {
            XCTAssertEqual($0 as? MobileAgentError, .insecureBaseURL)
        }
        XCTAssertThrowsError(try MobileCompatibleEndpoint.validatedBaseURL(from: "http://models.example.com/v1")) {
            XCTAssertEqual($0 as? MobileAgentError, .insecureBaseURL)
        }
    }

    func testCredentialsQueryAndFragmentAreRejected() {
        for value in [
            "https://user:secret@models.example.com/v1",
            "https://models.example.com/v1?token=secret",
            "https://models.example.com/v1#token",
        ] {
            XCTAssertThrowsError(try MobileCompatibleEndpoint.validatedBaseURL(from: value))
        }
    }
}

final class MobileConversationStoreTests: XCTestCase {
    func testSnapshotRoundTripPreservesProviderContinuationAndToolMessages() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = MobileConversationStore(fileURL: fileURL)
        let continuation = ProviderContinuation(
            providerIdentifier: "anthropic",
            format: "anthropic.content-blocks",
            payload: .array([.object(["signature": .string("opaque-signed-state")])])
        )
        let call = AgentToolCall(id: "call-1", name: "memory.search", arguments: .object([:]))
        let messages = [
            AgentMessage(role: .user, content: [.text("전에 말한 걸 찾아줘")]),
            AgentMessage(
                role: .assistant,
                content: [.text("찾아볼게요."), .toolCall(call)],
                providerContinuation: continuation
            ),
            AgentMessage(
                role: .tool,
                content: [.toolResult(AgentToolResultContent(
                    toolCallID: call.id,
                    toolName: call.name,
                    content: .object(["result": .string("full tool state")])
                ))]
            ),
        ]
        let snapshot = MobileConversationSnapshot(
            userID: "user-1",
            sessionID: "session-1",
            providerID: "anthropic",
            modelID: "claude-sonnet-5",
            messages: messages
        )

        try await store.save(snapshot)
        let loadedSnapshot = try await store.load(
            fallbackUserID: "ignored-user",
            fallbackSessionID: "ignored-session"
        )
        let loaded = try XCTUnwrap(loadedSnapshot)

        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(loaded.messages[1].providerContinuation, continuation)
        XCTAssertEqual(loaded.messages[2].role, .tool)
    }

    func testLegacyTextConversationMigratesToFullSnapshot() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacy = [MobileChatMessage(role: .user, text: "안녕")]
        try JSONEncoder().encode(legacy).write(to: fileURL)

        let loadedSnapshot = try await MobileConversationStore(fileURL: fileURL).load(
            fallbackUserID: "local-user",
            fallbackSessionID: "legacy-session"
        )
        let loaded = try XCTUnwrap(loadedSnapshot)

        XCTAssertEqual(loaded.userID, "local-user")
        XCTAssertEqual(loaded.sessionID, "legacy-session")
        XCTAssertEqual(loaded.messages.map(\.text), ["안녕"])
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("conversation.json")
    }
}

@MainActor
final class MobileAgentPreferencesTests: XCTestCase {
    func testFileMemoryDefaultsOffAndPersistsExplicitOptInAndICloudSelection() {
        let suiteName = "MobileAgentPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = MobileAgentPreferences(defaults: defaults)
        XCTAssertFalse(preferences.fileMemoryEnabled)
        XCTAssertNil(defaults.object(forKey: "mobile.agent.fileMemoryEnabled"))
        XCTAssertEqual(preferences.currentFileMemoryLocation, .local)

        preferences.fileMemoryEnabled = true
        preferences.fileMemoryLocation = MobileFileMemoryLocation.iCloudDrive.rawValue
        let restored = MobileAgentPreferences(defaults: defaults)
        XCTAssertTrue(restored.fileMemoryEnabled)
        XCTAssertEqual(restored.currentFileMemoryLocation, .iCloudDrive)
    }

    func testIdentityPersistsAndNewConversationChangesOnlySession() {
        let suiteName = "MobileAgentPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = MobileAgentPreferences(defaults: defaults)
        let userID = first.userID
        let originalSessionID = first.sessionID
        let nextSessionID = first.beginNewSession()
        let restored = MobileAgentPreferences(defaults: defaults)

        XCTAssertEqual(restored.userID, userID)
        XCTAssertNotEqual(nextSessionID, originalSessionID)
        XCTAssertEqual(restored.sessionID, nextSessionID)
    }

    func testProviderSelectionPersistsAnIndependentModelPerProvider() {
        let suiteName = "MobileAgentPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = MobileAgentPreferences(defaults: defaults)

        preferences.selectProvider(.openAI)
        XCTAssertEqual(preferences.model, MobileProviderKind.openAI.defaultModel)

        preferences.model = "my-fine-tuned-model"
        preferences.selectProvider(.gemini)
        XCTAssertEqual(preferences.model, MobileProviderKind.gemini.defaultModel)

        preferences.model = "my-gemini-model"
        preferences.selectProvider(.openAI)
        XCTAssertEqual(preferences.model, "my-fine-tuned-model")

        preferences.selectProvider(.gemini)
        XCTAssertEqual(preferences.model, "my-gemini-model")

        let restored = MobileAgentPreferences(defaults: defaults)
        XCTAssertEqual(restored.currentProvider, .gemini)
        XCTAssertEqual(restored.model, "my-gemini-model")
        restored.selectProvider(.openAI)
        XCTAssertEqual(restored.model, "my-fine-tuned-model")
    }

    func testLegacySingleModelMigratesIntoSelectedProvider() {
        let suiteName = "MobileAgentPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(MobileProviderKind.openAI.rawValue, forKey: "mobile.agent.provider")
        defaults.set("legacy-custom-model", forKey: "mobile.agent.model")

        let migrated = MobileAgentPreferences(defaults: defaults)
        XCTAssertEqual(migrated.currentProvider, .openAI)
        XCTAssertEqual(migrated.model, "legacy-custom-model")

        migrated.selectProvider(.gemini)
        XCTAssertEqual(migrated.model, MobileProviderKind.gemini.defaultModel)
        migrated.selectProvider(.openAI)
        XCTAssertEqual(migrated.model, "legacy-custom-model")
    }

    func testOfficialProviderDefaults() {
        XCTAssertEqual(MobileProviderKind.anthropic.defaultModel, "claude-sonnet-5")
        XCTAssertEqual(MobileProviderKind.openAI.defaultModel, "gpt-5.6")
        XCTAssertEqual(MobileProviderKind.gemini.defaultModel, "gemini-3.5-flash")
    }
}

final class MobileChatMessageTests: XCTestCase {
    func testDisplayProjectionIgnoresToolPayloadButKeepsAssistantIdentity() {
        let assistantID = UUID()
        let history = [
            AgentMessage(id: assistantID, role: .assistant, content: [.text("완료했어요")]),
            AgentMessage(role: .tool, content: [.toolResult(AgentToolResultContent(
                toolCallID: "1",
                toolName: "example",
                content: .string("must not render")
            ))]),
        ]

        let display = MobileChatMessage.displayMessages(from: history)

        XCTAssertEqual(display.count, 1)
        XCTAssertEqual(display[0].id, assistantID)
        XCTAssertEqual(display[0].text, "완료했어요")
    }

    func testModelChangeStripsOpaqueContinuationAndToolTurnsButKeepsDialogue() {
        let continuation = ProviderContinuation(
            providerIdentifier: "openAI",
            format: "opaque",
            payload: .string("signed-state")
        )
        let history = [
            AgentMessage(role: .user, text: "계속해줘"),
            AgentMessage(
                role: .assistant,
                content: [
                    .text("확인할게요"),
                    .toolCall(AgentToolCall(name: "memory.search", arguments: .object([:])))
                ],
                providerContinuation: continuation
            ),
            AgentMessage(role: .tool, content: [.toolResult(AgentToolResultContent(
                toolCallID: "call",
                toolName: "memory.search",
                content: .string("private result")
            ))]),
        ]

        let unchanged = MobileHistoryCompatibility.sanitizedHistory(
            history,
            storedProviderID: "openAI",
            storedModelID: "gpt-5.6",
            currentProviderID: "openAI",
            currentModelID: "gpt-5.6"
        )
        XCTAssertEqual(unchanged, history)

        let sanitized = MobileHistoryCompatibility.sanitizedHistory(
            history,
            storedProviderID: "openAI",
            storedModelID: "gpt-5.6",
            currentProviderID: "openAI",
            currentModelID: "different-model"
        )
        XCTAssertEqual(sanitized.map(\.role), [.user, .assistant])
        XCTAssertEqual(sanitized.map(\.text), ["계속해줘", "확인할게요"])
        XCTAssertTrue(sanitized.allSatisfy { $0.providerContinuation == nil })
        XCTAssertTrue(sanitized.allSatisfy { $0.toolCalls.isEmpty })
    }

    func testSensitiveMemoryApprovalCopyShowsExactContent() {
        let exactContent = "매주 금요일에는 약 복용 시간을 8시로 기억해줘"
        let request = AgentToolApprovalRequest(
            call: AgentToolCall(
                name: "memory.persist_sensitive",
                arguments: .object(["content": .string(exactContent)])
            ),
            descriptor: AgentToolDescriptor(
                name: "memory.persist_sensitive",
                description: "민감 기억 저장",
                inputSchema: .object(["type": .string("object")]),
                risk: .sensitive,
                sideEffect: .idempotent
            ),
            reason: "건강 관련 장기 기억은 승인이 필요합니다.",
            context: AgentToolExecutionContext(
                runID: UUID(),
                sessionID: "session",
                appID: "app",
                userID: "user",
                agentID: "도치"
            )
        )

        let message = MobileToolPresentation.approvalMessage(for: request)
        XCTAssertTrue(message.contains(exactContent))
        XCTAssertTrue(message.contains("저장할 내용"))
        XCTAssertTrue(message.contains(request.reason))
        XCTAssertFalse(MobileToolPresentation.allowsSessionApproval(request))
    }

    func testArchiveApprovalShowsExactSafeArgumentsAndRedactsUnknownValues() {
        let memoryID = UUID().uuidString.lowercased()
        let secret = "이 값은 승인 화면에 노출되면 안 됩니다"
        let request = AgentToolApprovalRequest(
            call: AgentToolCall(
                name: "memory.archive",
                arguments: .object([
                    "scope": .string("session"),
                    "id": .string(memoryID),
                    "expected_revision": 7,
                    "future_sensitive_argument": .string(secret),
                ])
            ),
            descriptor: AgentToolDescriptor(
                name: "memory.archive",
                description: "기억 보관",
                inputSchema: .object(["type": .string("object")]),
                risk: .sensitive,
                sideEffect: .nonIdempotent
            ),
            reason: "기억을 보관 처리하려면 승인이 필요합니다.",
            context: AgentToolExecutionContext(
                runID: UUID(),
                sessionID: "session",
                appID: "app",
                userID: "user",
                agentID: "도치"
            )
        )

        let message = MobileToolPresentation.approvalMessage(for: request)

        XCTAssertTrue(message.contains("scope: session"))
        XCTAssertTrue(message.contains("id: \(memoryID)"))
        XCTAssertTrue(message.contains("expected_revision: 7"))
        XCTAssertTrue(message.contains("future_sensitive_argument: [값 숨김]"))
        XCTAssertFalse(message.contains(secret))
        XCTAssertFalse(MobileToolPresentation.allowsSessionApproval(request))
    }
}

final class MobileCheckpointCleanupTests: XCTestCase {
    func testCompletedRunCleanupDeletesOnlyObservedCheckpointIDs() async throws {
        let store = InMemoryAgentCheckpointStore()
        let identity = makeIdentity()
        let unresolved = makeCheckpoint(
            identity: identity,
            state: .started,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let completed = makeCheckpoint(
            identity: identity,
            state: .completed,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        await store.save(unresolved)
        await store.save(completed)

        try await MobileCheckpointCleanup.deleteCompletedRun(
            checkpointIDs: [completed.id],
            from: store
        )

        let deletedCheckpoint = await store.load(id: completed.id)
        let retainedCheckpoint = await store.load(id: unresolved.id)
        XCTAssertNil(deletedCheckpoint)
        XCTAssertEqual(retainedCheckpoint, unresolved)
    }

    func testNewConversationRetainsUnresolvedNonIdempotentCheckpoint() async throws {
        let store = InMemoryAgentCheckpointStore()
        let identity = makeIdentity()
        let unresolved = makeCheckpoint(
            identity: identity,
            state: .indeterminate,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        await store.save(unresolved)

        let deleted = try await MobileCheckpointCleanup.deleteConversationIfSafe(
            identity,
            from: store
        )

        XCTAssertFalse(deleted)
        let retainedCheckpoint = await store.load(id: unresolved.id)
        XCTAssertEqual(retainedCheckpoint, unresolved)
    }

    func testNewConversationFindsOlderUnresolvedCheckpointBehindNewerCompletedOne() async throws {
        let store = InMemoryAgentCheckpointStore()
        let identity = makeIdentity()
        let unresolved = makeCheckpoint(
            identity: identity,
            state: .started,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let newerCompleted = makeCheckpoint(
            identity: identity,
            state: .completed,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        await store.save(unresolved)
        await store.save(newerCompleted)

        let deletedAll = try await MobileCheckpointCleanup.deleteConversationIfSafe(
            identity,
            from: store
        )

        let retainedUnresolved = await store.load(id: unresolved.id)
        let removedCompleted = await store.load(id: newerCompleted.id)
        XCTAssertFalse(deletedAll)
        XCTAssertEqual(retainedUnresolved, unresolved)
        XCTAssertNil(removedCompleted)
    }

    func testNewConversationDeletesResolvedCheckpointIdentity() async throws {
        let store = InMemoryAgentCheckpointStore()
        let identity = makeIdentity()
        let completed = makeCheckpoint(
            identity: identity,
            state: .completed,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        await store.save(completed)

        let deleted = try await MobileCheckpointCleanup.deleteConversationIfSafe(
            identity,
            from: store
        )

        XCTAssertTrue(deleted)
        let deletedCheckpoint = await store.load(id: completed.id)
        XCTAssertNil(deletedCheckpoint)
    }

    private func makeIdentity() -> MobileCheckpointIdentity {
        MobileCheckpointIdentity(
            appID: "com.example.mobile",
            userID: "user-1",
            sessionID: "session-1",
            agentID: "도치"
        )
    }

    private func makeCheckpoint(
        identity: MobileCheckpointIdentity,
        state: AgentToolExecutionState,
        createdAt: Date
    ) -> AgentRunCheckpoint {
        AgentRunCheckpoint(
            runID: UUID(),
            sessionID: identity.sessionID,
            appID: identity.appID,
            userID: identity.userID,
            agentID: identity.agentID,
            providerID: "anthropic",
            model: "claude-sonnet-5",
            messages: [],
            stepCount: 1,
            toolCallCount: 1,
            usage: AgentTokenUsage(),
            toolExecutions: [AgentToolExecutionRecord(
                callID: UUID().uuidString,
                toolName: "memory.archive",
                sideEffect: .nonIdempotent,
                state: state
            )],
            createdAt: createdAt
        )
    }
}

final class MobileCompletedRunCommitterTests: XCTestCase {
    func testCompletedRunSavesSnapshotBeforeDeletingCheckpoint() async throws {
        let recorder = MobileCommitRecorder()
        let conversationStore = RecordingConversationStore(recorder: recorder)
        let checkpointStore = RecordingCheckpointStore(recorder: recorder)
        let checkpoint = makeCheckpoint()
        await checkpointStore.save(checkpoint)

        try await MobileCompletedRunCommitter.commit(
            snapshot: makeSnapshot(),
            conversationStore: conversationStore,
            checkpointIDs: [checkpoint.id],
            checkpointStore: checkpointStore
        )

        let events = await recorder.events
        XCTAssertEqual(events, ["save-snapshot", "delete-checkpoint"])
        let deleted = await checkpointStore.load(id: checkpoint.id)
        XCTAssertNil(deleted)
    }

    func testSnapshotFailurePreservesCheckpointForRecovery() async throws {
        let recorder = MobileCommitRecorder()
        let conversationStore = RecordingConversationStore(
            recorder: recorder,
            shouldFail: true
        )
        let checkpointStore = RecordingCheckpointStore(recorder: recorder)
        let checkpoint = makeCheckpoint()
        await checkpointStore.save(checkpoint)

        do {
            try await MobileCompletedRunCommitter.commit(
                snapshot: makeSnapshot(),
                conversationStore: conversationStore,
                checkpointIDs: [checkpoint.id],
                checkpointStore: checkpointStore
            )
            XCTFail("Expected snapshot persistence to fail")
        } catch is RecordingConversationStore.Failure {
            // Expected.
        }

        let events = await recorder.events
        XCTAssertEqual(events, ["save-snapshot"])
        let retained = await checkpointStore.load(id: checkpoint.id)
        XCTAssertEqual(retained, checkpoint)
        XCTAssertTrue(
            MobileAgentError.completedConversationPersistenceFailed.localizedDescription
                .contains("복구 체크포인트는 보존")
        )
    }

    private func makeSnapshot() -> MobileConversationSnapshot {
        MobileConversationSnapshot(
            userID: "user-1",
            sessionID: "session-1",
            providerID: "anthropic",
            modelID: "claude-sonnet-5",
            messages: [AgentMessage(role: .assistant, text: "완료")]
        )
    }

    private func makeCheckpoint() -> AgentRunCheckpoint {
        AgentRunCheckpoint(
            runID: UUID(),
            sessionID: "session-1",
            appID: "com.hckim.dochi.mobile",
            userID: "user-1",
            agentID: "도치",
            providerID: "anthropic",
            model: "claude-sonnet-5",
            messages: [AgentMessage(role: .assistant, text: "완료")],
            stepCount: 1,
            toolCallCount: 0,
            usage: AgentTokenUsage()
        )
    }
}

private actor MobileCommitRecorder {
    private(set) var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }
}

private actor RecordingConversationStore: MobileConversationStoring {
    struct Failure: Error {}

    let recorder: MobileCommitRecorder
    let shouldFail: Bool

    init(recorder: MobileCommitRecorder, shouldFail: Bool = false) {
        self.recorder = recorder
        self.shouldFail = shouldFail
    }

    func load(
        fallbackUserID: String,
        fallbackSessionID: String
    ) async throws -> MobileConversationSnapshot? {
        nil
    }

    func save(_ snapshot: MobileConversationSnapshot) async throws {
        await recorder.append("save-snapshot")
        if shouldFail { throw Failure() }
    }
}

private actor RecordingCheckpointStore: AgentCheckpointStore {
    let recorder: MobileCommitRecorder
    private var checkpoints: [UUID: AgentRunCheckpoint] = [:]

    init(recorder: MobileCommitRecorder) {
        self.recorder = recorder
    }

    func save(_ checkpoint: AgentRunCheckpoint) {
        checkpoints[checkpoint.id] = checkpoint
    }

    func load(id: UUID) -> AgentRunCheckpoint? {
        checkpoints[id]
    }

    func latest(
        appID: String,
        userID: String?,
        sessionID: String,
        agentID: String
    ) -> AgentRunCheckpoint? {
        checkpoints.values
            .filter {
                $0.appID == appID
                    && $0.userID == userID
                    && $0.sessionID == sessionID
                    && $0.agentID == agentID
            }
            .max { $0.createdAt < $1.createdAt }
    }

    func delete(id: UUID) async {
        await recorder.append("delete-checkpoint")
        checkpoints[id] = nil
    }

    func deleteAll(
        appID: String,
        userID: String?,
        sessionID: String,
        agentID: String
    ) {
        checkpoints = checkpoints.filter { _, checkpoint in
            checkpoint.appID != appID
                || checkpoint.userID != userID
                || checkpoint.sessionID != sessionID
                || checkpoint.agentID != agentID
        }
    }
}

final class MobileSpeechCallbackGateTests: XCTestCase {
    func testStaleCallbackCannotFinishOrReplaceCurrentGeneration() {
        var gate = MobileSpeechCallbackGate()
        let oldID = UUID()
        let currentID = UUID()

        gate.begin(id: oldID)
        gate.begin(id: currentID)

        XCTAssertFalse(gate.accepts(oldID))
        XCTAssertFalse(gate.finish(oldID))
        XCTAssertEqual(gate.activeGenerationID, currentID)
        XCTAssertTrue(gate.accepts(currentID))
    }

    func testOnlyCurrentGenerationCanFinish() {
        var gate = MobileSpeechCallbackGate()
        let currentID = gate.begin()

        XCTAssertTrue(gate.finish(currentID))
        XCTAssertNil(gate.activeGenerationID)
        XCTAssertFalse(gate.accepts(currentID))
    }
}

final class MobileOwnedMemoryRepositoryTests: XCTestCase {
    func testListingAndPurgeAllIncludePastSessionsButPreserveEveryOtherOwner() async throws {
        let store = InMemoryMemoryStore()
        let repository = MobileOwnedMemoryRepository(
            store: store,
            appID: "com.hckim.dochi.mobile",
            userID: "owner"
        )
        let currentSession = try await insert(
            store: store,
            content: "현재 대화 기억",
            scope: .session(
                appID: "com.hckim.dochi.mobile",
                sessionID: "current-session",
                userID: "owner",
                agentID: "도치"
            )
        )
        let pastSession = try await insert(
            store: store,
            content: "과거 대화 기억",
            scope: .session(
                appID: "com.hckim.dochi.mobile",
                sessionID: "past-session",
                userID: "owner",
                agentID: "도치"
            )
        )
        let otherUser = try await insert(
            store: store,
            content: "다른 사용자",
            scope: .user(appID: "com.hckim.dochi.mobile", userID: "neighbor")
        )
        let otherApp = try await insert(
            store: store,
            content: "다른 앱",
            scope: .user(appID: "com.example.other", userID: "owner")
        )
        let applicationWide = try await insert(
            store: store,
            content: "앱 전체",
            scope: .application(appID: "com.hckim.dochi.mobile")
        )
        let userUnbound = try await insert(
            store: store,
            content: "사용자 미지정",
            scope: .agent(appID: "com.hckim.dochi.mobile", agentID: "도치")
        )

        let listed = try await repository.records()
        XCTAssertEqual(Set(listed.map(\.id)), Set([currentSession.id, pastSession.id]))

        let result = try await repository.purgeAll()
        XCTAssertEqual(result.recordsPurged, 2)
        let ownerRecordsAfterPurge = try await repository.records()
        XCTAssertTrue(ownerRecordsAfterPurge.isEmpty)
        for record in [otherUser, otherApp, applicationWide, userUnbound] {
            let retained = try await store.fetch(
                id: record.id,
                scope: record.scope,
                includeExpired: true
            )
            XCTAssertEqual(retained, record)
        }
    }

    func testExactPurgeRejectsRecordFromAnotherOwner() async throws {
        let store = InMemoryMemoryStore()
        let repository = MobileOwnedMemoryRepository(
            store: store,
            appID: "com.hckim.dochi.mobile",
            userID: "owner"
        )
        let otherUser = try await insert(
            store: store,
            content: "다른 사용자 기억",
            scope: .user(appID: "com.hckim.dochi.mobile", userID: "neighbor")
        )

        do {
            _ = try await repository.purge(otherUser)
            XCTFail("다른 사용자의 기억 삭제가 거부되어야 합니다.")
        } catch {
            XCTAssertEqual(error as? MobileMemoryManagementError, .recordNotOwned)
        }
        let retained = try await store.fetch(
            id: otherUser.id,
            scope: otherUser.scope,
            includeExpired: true
        )
        XCTAssertEqual(retained, otherUser)
    }

    private func insert(
        store: InMemoryMemoryStore,
        content: String,
        scope: MemoryScope
    ) async throws -> MemoryRecord {
        try await store.upsert(MemoryProposal(
            scope: scope,
            kind: .fact,
            content: content,
            provenance: MemoryProvenance(source: "mobile-memory-tests")
        ))
    }
}

final class MobileMemoryPresentationTests: XCTestCase {
    func testPastSessionScopeAndRecordMetadataRemainVisible() async throws {
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let store = InMemoryMemoryStore()
        let record = try await store.upsert(
            MemoryProposal(
                scope: .session(
                    appID: "com.hckim.dochi.mobile",
                    sessionID: "past-session-identifier",
                    userID: "owner",
                    agentID: "도치"
                ),
                kind: .preference,
                content: "따뜻한 차를 좋아함",
                provenance: MemoryProvenance(source: "test")
            ),
            status: .archived,
            at: updatedAt
        )

        XCTAssertEqual(MobileMemoryPresentation.scopeLabel(record.scope), "대화 · past-ses")
        XCTAssertEqual(MobileMemoryPresentation.kindLabel(record.kind), "선호")
        XCTAssertEqual(MobileMemoryPresentation.statusLabel(record), "보관됨")
        XCTAssertFalse(MobileMemoryPresentation.updatedLabel(record.updatedAt).isEmpty)
    }

    func testDeletionPreviewNormalizesAndBoundsLongContent() {
        let preview = MobileMemoryPresentation.deletionPreview(
            "  아주   긴\n기억 내용입니다  ",
            maximumLength: 8
        )

        XCTAssertEqual(preview, "아주 긴 기억 …")
    }
}
