import XCTest
@testable import Dochi

/// Tests for the 4-layer ContextSnapshotBuilder (issue #287).
///
/// Acceptance criteria:
/// - Runtime context follows the 4-layer injection order
/// - Personal memory is never injected for a different user
/// - Budget overflow results in truncated injection, not session failure
@MainActor
final class ContextSnapshotBuilderTests: XCTestCase {

    // MARK: - Helpers

    private static let testWorkspaceId = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private func agentKey(_ wsId: UUID, _ name: String) -> String { "\(wsId)|\(name)" }

    private func makeContextService(
        systemPrompt: String? = nil,
        agentPersona: String? = nil,
        workspaceMemory: String? = nil,
        agentMemory: String? = nil,
        userMemory: [String: String] = [:]
    ) -> MockContextService {
        let ctx = MockContextService()
        ctx.baseSystemPrompt = systemPrompt
        if let persona = agentPersona {
            ctx.agentPersonas[agentKey(Self.testWorkspaceId, "testAgent")] = persona
        }
        if let wsMem = workspaceMemory {
            ctx.workspaceMemory[Self.testWorkspaceId] = wsMem
        }
        if let aMem = agentMemory {
            ctx.agentMemories[agentKey(Self.testWorkspaceId, "testAgent")] = aMem
        }
        for (uid, mem) in userMemory {
            ctx.userMemory[uid] = mem
        }
        return ctx
    }

    private func makeTestSnapshot(
        id: String = UUID().uuidString,
        workspaceId: String = "test-workspace"
    ) -> ContextSnapshot {
        ContextSnapshot(
            id: id,
            workspaceId: workspaceId,
            agentId: "testAgent",
            userId: "testUser",
            layers: ContextLayers(
                systemLayer: ContextLayer(name: .system, content: "System content"),
                workspaceLayer: ContextLayer(name: .workspace, content: "Workspace content"),
                agentLayer: ContextLayer(name: .agent, content: "Agent content"),
                personalLayer: ContextLayer(name: .personal, content: "Personal content")
            ),
            tokenEstimate: 100,
            createdAt: Date(),
            sourceRevision: "abc12345"
        )
    }

    // MARK: - 4-Layer Order Tests

    func testLayerOrderIsSystemWorkspaceAgentPersonal() {
        let ctx = makeContextService(
            systemPrompt: "System instructions",
            agentPersona: "Agent persona",
            workspaceMemory: "Workspace memory content",
            agentMemory: "Agent memory content",
            userMemory: ["user1": "Personal memory"]
        )
        let builder = ContextSnapshotBuilder(contextService: ctx)

        let snapshot = builder.build(
            workspaceId: Self.testWorkspaceId,
            agentId: "testAgent",
            userId: "user1",
            channelMetadata: nil,
            tokenBudget: 100_000
        )

        let layerNames = snapshot.layers.ordered.map(\.name)
        XCTAssertEqual(layerNames, [.system, .workspace, .agent, .personal])

        XCTAssertTrue(snapshot.layers.systemLayer.content.contains("System instructions"))
        XCTAssertTrue(snapshot.layers.systemLayer.content.contains("Agent persona"))
        XCTAssertTrue(snapshot.layers.workspaceLayer.content.contains("Workspace memory content"))
        XCTAssertTrue(snapshot.layers.agentLayer.content.contains("Agent memory content"))
        XCTAssertTrue(snapshot.layers.personalLayer.content.contains("Personal memory"))
    }

    func testSystemLayerCombinesBasePromptAndPersona() {
        let ctx = makeContextService(
            systemPrompt: "Global base",
            agentPersona: "Agent role description"
        )
        let builder = ContextSnapshotBuilder(contextService: ctx)

        let snapshot = builder.build(
            workspaceId: Self.testWorkspaceId,
            agentId: "testAgent",
            userId: nil,
            channelMetadata: nil,
            tokenBudget: 100_000
        )

        let systemContent = snapshot.layers.systemLayer.content
        XCTAssertTrue(systemContent.contains("Global base"))
        XCTAssertTrue(systemContent.contains("Agent role description"))
        let baseRange = systemContent.range(of: "Global base")!
        let personaRange = systemContent.range(of: "Agent role description")!
        XCTAssertTrue(baseRange.lowerBound < personaRange.lowerBound)
    }

    func testChannelMetadataAppendedToSystemLayer() {
        let ctx = makeContextService(systemPrompt: "Base")
        let builder = ContextSnapshotBuilder(contextService: ctx)

        let snapshot = builder.build(
            workspaceId: Self.testWorkspaceId,
            agentId: "testAgent",
            userId: nil,
            channelMetadata: "channel: telegram, device: iPhone",
            tokenBudget: 100_000
        )

        XCTAssertTrue(snapshot.layers.systemLayer.content.contains("channel: telegram"))
    }

    // MARK: - Personal Memory Boundary Tests

    func testPersonalMemoryNotInjectedForDifferentUser() {
        let ctx = makeContextService(
            userMemory: ["user1": "Secret user1 data", "user2": "Secret user2 data"]
        )
        let builder = ContextSnapshotBuilder(contextService: ctx)

        let snapshot = builder.build(
            workspaceId: Self.testWorkspaceId,
            agentId: "testAgent",
            userId: "user1",
            channelMetadata: nil,
            tokenBudget: 100_000
        )

        XCTAssertTrue(snapshot.layers.personalLayer.content.contains("Secret user1 data"))
        XCTAssertFalse(snapshot.layers.personalLayer.content.contains("Secret user2 data"))
    }

    func testPersonalMemoryEmptyWhenNoUserId() {
        let ctx = makeContextService(
            userMemory: ["user1": "Secret data"]
        )
        let builder = ContextSnapshotBuilder(contextService: ctx)

        let snapshot = builder.build(
            workspaceId: Self.testWorkspaceId,
            agentId: "testAgent",
            userId: nil,
            channelMetadata: nil,
            tokenBudget: 100_000
        )

        XCTAssertTrue(snapshot.layers.personalLayer.content.isEmpty)
    }

    func testPersonalMemoryEmptyWhenUserIdIsEmpty() {
        let ctx = makeContextService(
            userMemory: ["user1": "Secret data"]
        )
        let builder = ContextSnapshotBuilder(contextService: ctx)

        let snapshot = builder.build(
            workspaceId: Self.testWorkspaceId,
            agentId: "testAgent",
            userId: "",
            channelMetadata: nil,
            tokenBudget: 100_000
        )

        XCTAssertTrue(snapshot.layers.personalLayer.content.isEmpty)
    }

    // MARK: - Workspace Boundary Validation

    func testValidateBoundariesPassesForCorrectWorkspace() {
        let ctx = makeContextService()
        let builder = ContextSnapshotBuilder(contextService: ctx)

        let snapshot = builder.build(
            workspaceId: Self.testWorkspaceId,
            agentId: "testAgent",
            userId: "user1",
            channelMetadata: nil,
            tokenBudget: 100_000
        )

        let violations = ContextSnapshotBuilder.validateBoundaries(
            snapshot: snapshot,
            expectedWorkspaceId: Self.testWorkspaceId.uuidString,
            expectedUserId: "user1"
        )

        XCTAssertTrue(violations.isEmpty)
    }

    func testValidateBoundariesDetectsWorkspaceMismatch() {
        let ctx = makeContextService()
        let builder = ContextSnapshotBuilder(contextService: ctx)

        let snapshot = builder.build(
            workspaceId: Self.testWorkspaceId,
            agentId: "testAgent",
            userId: "user1",
            channelMetadata: nil,
            tokenBudget: 100_000
        )

        let wrongWorkspace = UUID().uuidString
        let violations = ContextSnapshotBuilder.validateBoundaries(
            snapshot: snapshot,
            expectedWorkspaceId: wrongWorkspace,
            expectedUserId: "user1"
        )

        XCTAssertFalse(violations.isEmpty)
        XCTAssertTrue(violations.first?.contains("Workspace boundary") == true)
    }

    func testValidateBoundariesDetectsUserMismatch() {
        let ctx = makeContextService(
            userMemory: ["user1": "User 1 personal memory"]
        )
        let builder = ContextSnapshotBuilder(contextService: ctx)

        let snapshot = builder.build(
            workspaceId: Self.testWorkspaceId,
            agentId: "testAgent",
            userId: "user1",
            channelMetadata: nil,
            tokenBudget: 100_000
        )

        let violations = ContextSnapshotBuilder.validateBoundaries(
            snapshot: snapshot,
            expectedWorkspaceId: Self.testWorkspaceId.uuidString,
            expectedUserId: "user2"
        )

        XCTAssertFalse(violations.isEmpty)
        XCTAssertTrue(violations.first?.contains("Personal memory boundary") == true)
    }

    // MARK: - Token Budget Tests

    func testBudgetOverflowTruncatesContent() {
        let largeContent = String(repeating: "가나다라마바사 ", count: 5000)
        let ctx = makeContextService(
            systemPrompt: "System",
            workspaceMemory: largeContent
        )
        let builder = ContextSnapshotBuilder(contextService: ctx)

        let snapshot = builder.build(
            workspaceId: Self.testWorkspaceId,
            agentId: "testAgent",
            userId: nil,
            channelMetadata: nil,
            tokenBudget: 1000
        )

        XCTAssertTrue(snapshot.layers.workspaceLayer.truncated)
        XCTAssertFalse(snapshot.id.isEmpty)
        XCTAssertGreaterThan(snapshot.tokenEstimate, 0)
    }

    func testBudgetNotExceededForSmallContent() {
        let ctx = makeContextService(
            systemPrompt: "Short system",
            workspaceMemory: "Short workspace"
        )
        let builder = ContextSnapshotBuilder(contextService: ctx)

        let snapshot = builder.build(
            workspaceId: Self.testWorkspaceId,
            agentId: "testAgent",
            userId: nil,
            channelMetadata: nil,
            tokenBudget: 100_000
        )

        for layer in snapshot.layers.ordered {
            XCTAssertFalse(layer.truncated, "Layer \(layer.name.rawValue) should not be truncated")
        }
    }

    func testTruncatedLayerContainsTruncationNote() {
        let largeContent = String(repeating: "테스트 컨텐츠 ", count: 2000)
        let ctx = makeContextService(workspaceMemory: largeContent)
        let builder = ContextSnapshotBuilder(contextService: ctx)

        let snapshot = builder.build(
            workspaceId: Self.testWorkspaceId,
            agentId: "testAgent",
            userId: nil,
            channelMetadata: nil,
            tokenBudget: 500
        )

        if snapshot.layers.workspaceLayer.truncated {
            XCTAssertTrue(snapshot.layers.workspaceLayer.content.contains("축약됨"))
        }
    }

    // MARK: - Empty Layer Handling

    func testEmptyLayersAreHandledGracefully() {
        let ctx = makeContextService()
        let builder = ContextSnapshotBuilder(contextService: ctx)

        let snapshot = builder.build(
            workspaceId: Self.testWorkspaceId,
            agentId: "testAgent",
            userId: nil,
            channelMetadata: nil,
            tokenBudget: 100_000
        )

        XCTAssertFalse(snapshot.id.isEmpty)
        XCTAssertEqual(snapshot.workspaceId, Self.testWorkspaceId.uuidString)

        for layer in snapshot.layers.ordered {
            XCTAssertFalse(layer.truncated)
        }
    }

    func testPartialLayersPresent() {
        let ctx = makeContextService(
            systemPrompt: "System instructions",
            userMemory: ["user1": "Personal memory"]
        )
        let builder = ContextSnapshotBuilder(contextService: ctx)

        let snapshot = builder.build(
            workspaceId: Self.testWorkspaceId,
            agentId: "testAgent",
            userId: "user1",
            channelMetadata: nil,
            tokenBudget: 100_000
        )

        XCTAssertFalse(snapshot.layers.systemLayer.content.isEmpty)
        XCTAssertTrue(snapshot.layers.workspaceLayer.content.isEmpty)
        XCTAssertTrue(snapshot.layers.agentLayer.content.isEmpty)
        XCTAssertFalse(snapshot.layers.personalLayer.content.isEmpty)
    }

    // MARK: - Snapshot Ref and Metadata

    func testSnapshotRefIsUniquePerBuild() {
        let ctx = makeContextService(systemPrompt: "System")
        let builder = ContextSnapshotBuilder(contextService: ctx)

        let snapshot1 = builder.build(workspaceId: Self.testWorkspaceId, agentId: "testAgent", userId: nil, channelMetadata: nil, tokenBudget: 100_000)
        let snapshot2 = builder.build(workspaceId: Self.testWorkspaceId, agentId: "testAgent", userId: nil, channelMetadata: nil, tokenBudget: 100_000)

        XCTAssertNotEqual(snapshot1.snapshotRef, snapshot2.snapshotRef)
    }

    func testSnapshotContainsCorrectMetadata() {
        let ctx = makeContextService(systemPrompt: "System")
        let builder = ContextSnapshotBuilder(contextService: ctx)

        let snapshot = builder.build(
            workspaceId: Self.testWorkspaceId,
            agentId: "testAgent",
            userId: "user1",
            channelMetadata: nil,
            tokenBudget: 100_000
        )

        XCTAssertEqual(snapshot.workspaceId, Self.testWorkspaceId.uuidString)
        XCTAssertEqual(snapshot.agentId, "testAgent")
        XCTAssertEqual(snapshot.userId, "user1")
        XCTAssertGreaterThan(snapshot.tokenEstimate, 0)
        XCTAssertFalse(snapshot.sourceRevision.isEmpty)
    }

    // MARK: - Source Revision

    func testSourceRevisionChangesWhenContentChanges() {
        let ctx = makeContextService(systemPrompt: "Version 1")
        let builder = ContextSnapshotBuilder(contextService: ctx)

        let snapshot1 = builder.build(workspaceId: Self.testWorkspaceId, agentId: "testAgent", userId: nil, channelMetadata: nil, tokenBudget: 100_000)
        ctx.baseSystemPrompt = "Version 2"
        let snapshot2 = builder.build(workspaceId: Self.testWorkspaceId, agentId: "testAgent", userId: nil, channelMetadata: nil, tokenBudget: 100_000)

        XCTAssertNotEqual(snapshot1.sourceRevision, snapshot2.sourceRevision)
    }

    func testSourceRevisionStableForSameContent() {
        let ctx = makeContextService(systemPrompt: "Stable content")
        let builder = ContextSnapshotBuilder(contextService: ctx)

        let snapshot1 = builder.build(workspaceId: Self.testWorkspaceId, agentId: "testAgent", userId: nil, channelMetadata: nil, tokenBudget: 100_000)
        let snapshot2 = builder.build(workspaceId: Self.testWorkspaceId, agentId: "testAgent", userId: nil, channelMetadata: nil, tokenBudget: 100_000)

        XCTAssertEqual(snapshot1.sourceRevision, snapshot2.sourceRevision)
    }

    // MARK: - Combined Text

    func testCombinedTextJoinsNonEmptyLayers() {
        let ctx = makeContextService(
            systemPrompt: "System",
            workspaceMemory: "Workspace",
            userMemory: ["u1": "Personal"]
        )
        let builder = ContextSnapshotBuilder(contextService: ctx)

        let snapshot = builder.build(
            workspaceId: Self.testWorkspaceId,
            agentId: "testAgent",
            userId: "u1",
            channelMetadata: nil,
            tokenBudget: 100_000
        )

        let combined = snapshot.layers.combinedText
        XCTAssertTrue(combined.contains("System"))
        XCTAssertTrue(combined.contains("Workspace"))
        XCTAssertTrue(combined.contains("Personal"))
        XCTAssertFalse(combined.contains("\n\n\n\n"))
    }

    // MARK: - Token Estimate

    func testTokenEstimateIsReasonable() {
        let content = String(repeating: "한글 텍스트 ", count: 100)
        let ctx = makeContextService(systemPrompt: content)
        let builder = ContextSnapshotBuilder(contextService: ctx)

        let snapshot = builder.build(
            workspaceId: Self.testWorkspaceId,
            agentId: "testAgent",
            userId: nil,
            channelMetadata: nil,
            tokenBudget: 100_000
        )

        let expectedApprox = snapshot.layers.totalCharCount / 2
        XCTAssertEqual(snapshot.tokenEstimate, max(expectedApprox, 1))
    }

    // MARK: - ContextSnapshotStore Tests

    func testStoreAndResolveSnapshot() {
        let store = ContextSnapshotStore()
        let snapshot = makeTestSnapshot(id: "test-ref-1")

        let ref = store.store(snapshot)
        XCTAssertEqual(ref, "test-ref-1")
        XCTAssertEqual(store.count, 1)

        let resolved = store.resolve("test-ref-1")
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.id, "test-ref-1")
    }

    func testStoreReturnsNilForUnknownRef() {
        let store = ContextSnapshotStore()
        XCTAssertNil(store.resolve("nonexistent"))
    }

    func testStoreRemovesSnapshot() {
        let store = ContextSnapshotStore()
        store.store(makeTestSnapshot(id: "to-remove"))
        store.remove("to-remove")
        XCTAssertNil(store.resolve("to-remove"))
        XCTAssertEqual(store.count, 0)
    }

    func testStoreRemovesAllForWorkspace() {
        let store = ContextSnapshotStore()
        store.store(makeTestSnapshot(id: "ws1-snap1", workspaceId: "ws-1"))
        store.store(makeTestSnapshot(id: "ws1-snap2", workspaceId: "ws-1"))
        store.store(makeTestSnapshot(id: "ws2-snap1", workspaceId: "ws-2"))

        store.removeAll(workspaceId: "ws-1")
        XCTAssertEqual(store.count, 1)
        XCTAssertNil(store.resolve("ws1-snap1"))
        XCTAssertNotNil(store.resolve("ws2-snap1"))
    }

    func testStoreEvictsOldestWhenFull() {
        let store = ContextSnapshotStore(maxEntries: 3, ttl: 3600)

        store.store(makeTestSnapshot(id: "snap-1"))
        store.store(makeTestSnapshot(id: "snap-2"))
        store.store(makeTestSnapshot(id: "snap-3"))
        store.store(makeTestSnapshot(id: "snap-4"))

        XCTAssertEqual(store.count, 3)
        XCTAssertNil(store.resolve("snap-1"))
        XCTAssertNotNil(store.resolve("snap-4"))
    }

    func testStoreExpiredEntriesReturnNil() {
        let store = ContextSnapshotStore(maxEntries: 50, ttl: 0)
        store.store(makeTestSnapshot(id: "expired-snap"))
        XCTAssertNil(store.resolve("expired-snap"))
    }

    // MARK: - Serialization Roundtrip

    func testSnapshotSerializationRoundtrip() throws {
        let snapshot = makeTestSnapshot(id: "serialize-test")

        let data = try ContextSnapshotStore.serialize(snapshot)
        let decoded = try ContextSnapshotStore.deserialize(data)

        XCTAssertEqual(decoded.id, snapshot.id)
        XCTAssertEqual(decoded.workspaceId, snapshot.workspaceId)
        XCTAssertEqual(decoded.layers.systemLayer.content, snapshot.layers.systemLayer.content)
    }

    // MARK: - Integration: RuntimeBridge Context Snapshot

    func testMockRuntimeBridgeContextSnapshotFlow() async {
        let mock = MockRuntimeBridgeService()
        let ctx = MockContextService()
        ctx.baseSystemPrompt = "Test system prompt"

        mock.configureContextSnapshot(contextService: ctx)
        XCTAssertEqual(mock.configureContextSnapshotCallCount, 1)

        let ref = mock.buildContextSnapshot(
            workspaceId: Self.testWorkspaceId,
            agentId: "testAgent",
            userId: "user1",
            channelMetadata: nil,
            tokenBudget: 16_000
        )
        XCTAssertNotNil(ref)
        XCTAssertEqual(mock.buildContextSnapshotCallCount, 1)

        let resolved = mock.resolveContextSnapshot(ref: ref!)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(mock.resolveContextSnapshotCallCount, 1)
    }

    func testSnapshotRefPassedToSessionRun() {
        let mock = MockRuntimeBridgeService()
        mock.stubbedSnapshotRef = "my-snapshot-ref"

        let ref = mock.buildContextSnapshot(
            workspaceId: Self.testWorkspaceId,
            agentId: "agent",
            userId: "user",
            channelMetadata: nil,
            tokenBudget: 16_000
        )
        XCTAssertEqual(ref, "my-snapshot-ref")

        let params = SessionRunParams(
            sessionId: "session-1",
            input: "hello",
            contextSnapshotRef: ref,
            permissionMode: nil
        )

        _ = mock.runSession(params: params)
        XCTAssertEqual(mock.lastRunParams?.contextSnapshotRef, "my-snapshot-ref")
    }
}
