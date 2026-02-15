import XCTest
@testable import Dochi

@MainActor
final class SyncEngineTests: XCTestCase {

    private var engine: SyncEngine!
    private var mockSupabase: MockSupabaseService!
    private var mockContext: MockContextService!
    private var mockConversation: MockConversationService!
    private var settings: AppSettings!
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        mockSupabase = MockSupabaseService()
        mockContext = MockContextService()
        mockConversation = MockConversationService()
        settings = AppSettings()
        settings.autoSyncEnabled = true
        settings.syncConversations = true
        settings.syncMemory = true
        settings.syncProfiles = true
        settings.conflictResolutionStrategy = "lastWriteWins"

        engine = SyncEngine(
            supabaseService: mockSupabase,
            settings: settings,
            contextService: mockContext,
            conversationService: mockConversation,
            baseURL: tempDir
        )
    }

    override func tearDown() async throws {
        engine?.stopAutoSync()
        engine = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - State Tests

    func testInitialStateIsDisabled() {
        XCTAssertEqual(engine.syncState, .disabled)
    }

    func testRestoreSyncStateWhenConfiguredAndSignedIn() {
        engine.restoreSyncState()
        // mockSupabase is configured and signed in by default
        XCTAssertEqual(engine.syncState, .idle)
    }

    func testRestoreSyncStateWhenNotConfigured() {
        mockSupabase.isConfigured = false
        engine.restoreSyncState()
        XCTAssertEqual(engine.syncState, .disabled)
    }

    func testRestoreSyncStateWhenNotSignedIn() {
        mockSupabase.authState = .signedOut
        engine.restoreSyncState()
        XCTAssertEqual(engine.syncState, .disabled)
    }

    func testRestoreSyncStateWhenAutoSyncDisabled() {
        settings.autoSyncEnabled = false
        engine.restoreSyncState()
        XCTAssertEqual(engine.syncState, .disabled)
    }

    // MARK: - Offline Queue Tests

    func testEnqueueChange() {
        engine.enqueueChange(entityType: .conversation, entityId: "test-id", action: .update)
        XCTAssertEqual(engine.pendingLocalChanges, 1)
    }

    func testEnqueueMultipleChanges() {
        engine.enqueueChange(entityType: .conversation, entityId: "1", action: .create)
        engine.enqueueChange(entityType: .memory, entityId: "2", action: .update)
        engine.enqueueChange(entityType: .profile, entityId: "3", action: .delete)
        XCTAssertEqual(engine.pendingLocalChanges, 3)
    }

    func testOfflineQueuePersistence() {
        engine.enqueueChange(entityType: .conversation, entityId: "test-id", action: .update, payload: "test".data(using: .utf8))
        XCTAssertEqual(engine.pendingLocalChanges, 1)

        // Create a new engine reading from the same directory
        let engine2 = SyncEngine(
            supabaseService: mockSupabase,
            settings: settings,
            contextService: mockContext,
            conversationService: mockConversation,
            baseURL: tempDir
        )
        XCTAssertEqual(engine2.pendingLocalChanges, 1)
        engine2.stopAutoSync()
    }

    // MARK: - Sync Tests

    func testSyncWhenNotConfigured() async {
        mockSupabase.isConfigured = false
        await engine.sync()
        XCTAssertEqual(engine.syncState, .disabled)
    }

    func testSyncWhenNotSignedIn() async {
        mockSupabase.authState = .signedOut
        await engine.sync()
        XCTAssertEqual(engine.syncState, .disabled)
    }

    func testSyncSuccess() async {
        engine.restoreSyncState()
        await engine.sync()

        // Should be idle after successful sync
        XCTAssertEqual(engine.syncState, .idle)
        XCTAssertNotNil(engine.lastSuccessfulSync)
        XCTAssertFalse(engine.syncHistory.isEmpty)
    }

    func testSyncPushesConversations() async {
        // Add a conversation
        let conversation = Conversation(title: "Test Conversation")
        mockConversation.save(conversation: conversation)

        engine.restoreSyncState()
        await engine.sync()

        // Should have pushed entities
        XCTAssertTrue(mockSupabase.pushedEntities.contains(where: { $0.type == .conversation }))
    }

    func testSyncPushesMemory() async {
        // Add workspace memory
        let wsId = UUID(uuidString: settings.currentWorkspaceId) ?? UUID()
        mockContext.workspaceMemory[wsId] = "Test memory content"

        engine.restoreSyncState()
        await engine.sync()

        XCTAssertTrue(mockSupabase.pushedEntities.contains(where: { $0.type == .memory }))
    }

    func testSyncPushesProfiles() async {
        mockContext.profiles = [
            UserProfile(id: UUID(), name: "Test User")
        ]

        engine.restoreSyncState()
        await engine.sync()

        XCTAssertTrue(mockSupabase.pushedEntities.contains(where: { $0.type == .profile }))
    }

    // MARK: - Conflict Tests

    func testResolveConflictKeepLocal() {
        let conflict = SyncConflict(
            entityType: .conversation,
            entityId: "test-id",
            entityTitle: "Test",
            localUpdatedAt: Date(),
            remoteUpdatedAt: Date().addingTimeInterval(-60),
            localPreview: "local",
            remotePreview: "remote"
        )
        engine.syncConflicts = [conflict]
        engine.syncState = .conflict(count: 1)

        engine.resolveConflict(id: conflict.id, resolution: .keepLocal)

        XCTAssertTrue(engine.syncConflicts.isEmpty)
        XCTAssertEqual(engine.syncState, .idle)
        // Should have enqueued a push for the local version
        XCTAssertEqual(engine.pendingLocalChanges, 1)
    }

    func testResolveConflictKeepRemote() {
        let conflict = SyncConflict(
            entityType: .memory,
            entityId: "test-id",
            entityTitle: "Memory",
            localUpdatedAt: Date(),
            remoteUpdatedAt: Date(),
            localPreview: "local",
            remotePreview: "remote"
        )
        engine.syncConflicts = [conflict]
        engine.syncState = .conflict(count: 1)

        engine.resolveConflict(id: conflict.id, resolution: .keepRemote)

        XCTAssertTrue(engine.syncConflicts.isEmpty)
        XCTAssertEqual(engine.syncState, .idle)
    }

    func testResolveAllConflicts() {
        let c1 = SyncConflict(
            entityType: .conversation,
            entityId: "1",
            entityTitle: "Conv 1",
            localUpdatedAt: Date(),
            remoteUpdatedAt: Date(),
            localPreview: "",
            remotePreview: ""
        )
        let c2 = SyncConflict(
            entityType: .memory,
            entityId: "2",
            entityTitle: "Memory",
            localUpdatedAt: Date(),
            remoteUpdatedAt: Date(),
            localPreview: "",
            remotePreview: ""
        )
        engine.syncConflicts = [c1, c2]
        engine.syncState = .conflict(count: 2)

        engine.resolveAllConflicts(resolution: .keepLocal)

        XCTAssertTrue(engine.syncConflicts.isEmpty)
        XCTAssertEqual(engine.syncState, .idle)
    }

    // MARK: - Online/Offline Tests

    func testUpdateOnlineStatusToOffline() {
        engine.restoreSyncState()
        XCTAssertEqual(engine.syncState, .idle)

        engine.updateOnlineStatus(isOnline: false)
        XCTAssertEqual(engine.syncState, .offline)
    }

    func testUpdateOnlineStatusToOnlineFromOffline() {
        engine.restoreSyncState()
        engine.updateOnlineStatus(isOnline: false)
        XCTAssertEqual(engine.syncState, .offline)

        // Going back online triggers sync
        engine.updateOnlineStatus(isOnline: true)
        // State should transition from offline
        XCTAssertNotEqual(engine.syncState, .offline)
    }

    // MARK: - Entity Count Tests

    func testEntityCounts() {
        mockConversation.save(conversation: Conversation(title: "C1"))
        mockConversation.save(conversation: Conversation(title: "C2"))
        mockContext.profiles = [
            UserProfile(id: UUID(), name: "User1"),
            UserProfile(id: UUID(), name: "User2"),
        ]

        let counts = engine.entityCounts()
        XCTAssertEqual(counts[.conversation], 2)
        XCTAssertEqual(counts[.profile], 2)
        XCTAssertEqual(counts[.memory], 1) // always 1 for workspace
    }

    func testEntityCountsRespectSettings() {
        settings.syncConversations = false
        settings.syncProfiles = false

        mockConversation.save(conversation: Conversation(title: "C1"))
        mockContext.profiles = [UserProfile(id: UUID(), name: "User1")]

        let counts = engine.entityCounts()
        XCTAssertNil(counts[.conversation])
        XCTAssertNil(counts[.profile])
    }

    // MARK: - Toast Tests

    func testDismissSyncToast() {
        let event = SyncToastEvent(direction: .incoming, entityType: .conversation, entityTitle: "Test")
        engine.syncToastEvents = [event]

        engine.dismissSyncToast(id: event.id)
        XCTAssertTrue(engine.syncToastEvents.isEmpty)
    }

    // MARK: - History Tests

    func testSyncHistoryLimited() async {
        engine.restoreSyncState()

        // Run sync multiple times
        for _ in 0..<25 {
            await engine.sync()
        }

        // History should be limited to 20 entries
        XCTAssertLessThanOrEqual(engine.syncHistory.count, 20)
    }

    // MARK: - Full Sync Tests

    func testFullSyncClearsTimestamps() async {
        engine.restoreSyncState()
        await engine.sync()
        let firstSyncTime = engine.lastSuccessfulSync

        // Wait a bit
        try? await Task.sleep(for: .milliseconds(100))

        await engine.fullSync()
        XCTAssertNotNil(engine.lastSuccessfulSync)
        if let first = firstSyncTime, let second = engine.lastSuccessfulSync {
            XCTAssertGreaterThan(second, first)
        }
    }

    // MARK: - Sync Disabled Tests

    func testSyncDisabledWhenAutoSyncOff() {
        settings.autoSyncEnabled = false
        engine.restoreSyncState()
        XCTAssertEqual(engine.syncState, .disabled)
    }
}

// MARK: - SyncModels Tests

@MainActor
final class SyncModelsTests: XCTestCase {

    func testSyncStateEquatable() {
        XCTAssertEqual(SyncState.idle, SyncState.idle)
        XCTAssertEqual(SyncState.conflict(count: 3), SyncState.conflict(count: 3))
        XCTAssertNotEqual(SyncState.idle, SyncState.syncing)
        XCTAssertNotEqual(SyncState.conflict(count: 1), SyncState.conflict(count: 2))
    }

    func testSyncStateDisplayText() {
        XCTAssertEqual(SyncState.idle.displayText, "동기화 완료")
        XCTAssertEqual(SyncState.syncing.displayText, "동기화 중...")
        XCTAssertEqual(SyncState.conflict(count: 3).displayText, "충돌 3건")
        XCTAssertTrue(SyncState.error(message: "테스트").displayText.contains("테스트"))
        XCTAssertEqual(SyncState.offline.displayText, "오프라인")
        XCTAssertEqual(SyncState.disabled.displayText, "비활성")
    }

    func testSyncProgressFraction() {
        var progress = SyncProgress(totalItems: 10, completedItems: 5, currentEntity: "test", startedAt: Date())
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.001)

        progress.completedItems = 10
        XCTAssertTrue(progress.isComplete)

        let empty = SyncProgress.empty
        XCTAssertEqual(empty.fraction, 0)
        XCTAssertFalse(empty.isComplete)
    }

    func testSyncEntityTypeDisplayName() {
        XCTAssertEqual(SyncEntityType.conversation.displayName, "대화")
        XCTAssertEqual(SyncEntityType.memory.displayName, "메모리")
        XCTAssertEqual(SyncEntityType.kanban.displayName, "칸반")
        XCTAssertEqual(SyncEntityType.profile.displayName, "프로필")
    }

    func testSyncToastEventDisplayMessage() {
        let incoming = SyncToastEvent(direction: .incoming, entityType: .conversation, entityTitle: "테스트")
        XCTAssertTrue(incoming.displayMessage.contains("수신"))

        let outgoing = SyncToastEvent(direction: .outgoing, entityType: .memory, entityTitle: "메모리")
        XCTAssertTrue(outgoing.displayMessage.contains("발신"))

        let conflict = SyncToastEvent(direction: .incoming, entityType: .conversation, entityTitle: "충돌", isConflict: true)
        XCTAssertTrue(conflict.displayMessage.contains("충돌"))
    }

    func testSyncConflictEquatable() {
        let id = UUID()
        let c1 = SyncConflict(
            id: id,
            entityType: .conversation,
            entityId: "test",
            entityTitle: "Test",
            localUpdatedAt: Date.distantPast,
            remoteUpdatedAt: Date.distantFuture,
            localPreview: "local",
            remotePreview: "remote"
        )
        let c2 = SyncConflict(
            id: id,
            entityType: .conversation,
            entityId: "test",
            entityTitle: "Test",
            localUpdatedAt: Date.distantPast,
            remoteUpdatedAt: Date.distantFuture,
            localPreview: "local",
            remotePreview: "remote"
        )
        XCTAssertEqual(c1, c2)
    }

    func testSyncQueueItemCodable() throws {
        let item = SyncQueueItem(
            entityType: .conversation,
            entityId: "test-123",
            action: .update,
            payload: "test".data(using: .utf8)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SyncQueueItem.self, from: data)

        XCTAssertEqual(decoded.id, item.id)
        XCTAssertEqual(decoded.entityType, item.entityType)
        XCTAssertEqual(decoded.entityId, item.entityId)
        XCTAssertEqual(decoded.action, item.action)
        XCTAssertEqual(decoded.payload, item.payload)
    }

    func testSyncMetadataCodable() throws {
        var metadata = SyncMetadata()
        metadata.lastSyncTimestamp = Date()
        metadata.entityTimestamps = ["entity-1": Date(), "entity-2": Date()]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SyncMetadata.self, from: data)

        XCTAssertNotNil(decoded.lastSyncTimestamp)
        XCTAssertEqual(decoded.entityTimestamps.count, 2)
    }

    func testSyncHistoryEntry() {
        let entry = SyncHistoryEntry(
            direction: .outgoing,
            entityType: .conversation,
            entityTitle: "Test",
            success: true
        )
        XCTAssertTrue(entry.success)
        XCTAssertNil(entry.errorMessage)

        let errorEntry = SyncHistoryEntry(
            direction: .incoming,
            entityType: .memory,
            entityTitle: "Memory",
            success: false,
            errorMessage: "Network error"
        )
        XCTAssertFalse(errorEntry.success)
        XCTAssertEqual(errorEntry.errorMessage, "Network error")
    }
}

// MARK: - AppSettings Sync Tests

@MainActor
final class AppSettingsSyncTests: XCTestCase {

    func testDefaultSyncSettings() {
        let settings = AppSettings()
        XCTAssertTrue(settings.autoSyncEnabled)
        XCTAssertTrue(settings.realtimeSyncEnabled)
        XCTAssertTrue(settings.syncConversations)
        XCTAssertTrue(settings.syncMemory)
        XCTAssertTrue(settings.syncKanban)
        XCTAssertTrue(settings.syncProfiles)
        XCTAssertEqual(settings.conflictResolutionStrategy, "lastWriteWins")
    }
}
