import Foundation
import os

/// 멀티디바이스 데이터 동기화 엔진 (G-3)
///
/// SupabaseServiceProtocol에 의존하며, 오프라인 큐와 충돌 감지/해결을 제공한다.
/// 실제 Supabase 서버 없이도 로컬 큐가 동작하도록 설계되었다.
@MainActor
@Observable
final class SyncEngine {

    // MARK: - Observable State

    var syncState: SyncState = .disabled
    private(set) var syncProgress: SyncProgress = .empty
    var syncConflicts: [SyncConflict] = []
    private(set) var lastSuccessfulSync: Date?
    private(set) var pendingLocalChanges: Int = 0
    private(set) var syncHistory: [SyncHistoryEntry] = []
    var syncToastEvents: [SyncToastEvent] = []

    // MARK: - Dependencies

    private let supabaseService: SupabaseServiceProtocol
    private let settings: AppSettings
    private let contextService: ContextServiceProtocol
    private let conversationService: ConversationServiceProtocol

    // MARK: - Internal

    private var syncMetadata: SyncMetadata
    private var offlineQueue: [SyncQueueItem] = []
    private var autoSyncTask: Task<Void, Never>?
    private var isOnline: Bool = true

    /// 오프라인 큐 파일 경로
    private let queueFileURL: URL
    /// 동기화 메타데이터 파일 경로
    private let metadataFileURL: URL

    private static let maxHistoryEntries = 20
    private static let autoSyncIntervalSeconds: TimeInterval = 60

    // MARK: - Init

    init(
        supabaseService: SupabaseServiceProtocol,
        settings: AppSettings,
        contextService: ContextServiceProtocol,
        conversationService: ConversationServiceProtocol,
        baseURL: URL? = nil
    ) {
        self.supabaseService = supabaseService
        self.settings = settings
        self.contextService = contextService
        self.conversationService = conversationService

        let base = baseURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Dochi")
        self.queueFileURL = base.appendingPathComponent("sync_queue.json")
        self.metadataFileURL = base.appendingPathComponent("sync_metadata.json")
        self.syncMetadata = SyncMetadata()

        // 저장된 메타데이터/큐 로드
        loadMetadata()
        loadOfflineQueue()
        updatePendingCount()
    }

    // MARK: - Public API

    /// 동기화 상태 복원 (앱 시작 시 호출)
    func restoreSyncState() {
        loadMetadata()
        loadOfflineQueue()
        updatePendingCount()

        guard supabaseService.isConfigured, supabaseService.authState.isSignedIn else {
            syncState = .disabled
            return
        }

        guard settings.autoSyncEnabled else {
            syncState = .disabled
            return
        }

        syncState = .idle
        lastSuccessfulSync = syncMetadata.lastSyncTimestamp

        // 자동 동기화 시작
        startAutoSync()
    }

    /// 수동 동기화 (변경분만)
    func sync() async {
        guard canSync() else { return }

        syncState = .syncing
        syncProgress = SyncProgress(totalItems: 4, completedItems: 0, currentEntity: "", startedAt: Date())

        do {
            // 1. 오프라인 큐 flush
            await flushOfflineQueue()
            syncProgress.completedItems = 1
            syncProgress.currentEntity = "대화"

            // 2. Push local changes
            if settings.syncConversations {
                try await pushConversations()
            }
            syncProgress.completedItems = 2
            syncProgress.currentEntity = "메모리"

            if settings.syncMemory {
                try await pushMemory()
            }
            syncProgress.completedItems = 3
            syncProgress.currentEntity = "프로필"

            if settings.syncProfiles {
                try await pushProfiles()
            }
            syncProgress.completedItems = 4

            // 3. Pull remote changes
            if settings.syncConversations {
                try await pullConversations()
            }
            if settings.syncMemory {
                try await pullMemory()
            }
            if settings.syncProfiles {
                try await pullProfiles()
            }

            // 동기화 성공
            syncMetadata.lastSyncTimestamp = Date()
            saveMetadata()
            lastSuccessfulSync = syncMetadata.lastSyncTimestamp

            if syncConflicts.isEmpty {
                syncState = .idle
            } else {
                syncState = .conflict(count: syncConflicts.count)
            }

            addHistoryEntry(direction: .outgoing, entityType: .conversation, entityTitle: "전체 동기화", success: true)
            Log.cloud.info("Sync completed successfully")
        } catch {
            let message = error.localizedDescription
            syncState = .error(message: String(message.prefix(50)))
            addHistoryEntry(direction: .outgoing, entityType: .conversation, entityTitle: "전체 동기화", success: false, errorMessage: message)
            Log.cloud.error("Sync failed: \(message)")
        }

        syncProgress = .empty
    }

    /// 강제 전체 동기화 (모든 데이터 다시 동기화)
    func fullSync() async {
        syncMetadata.entityTimestamps.removeAll()
        saveMetadata()
        await sync()
    }

    /// 초기 업로드 (첫 연결 시 로컬 데이터를 클라우드에 올림)
    func initialUpload(onProgress: ((Double) -> Void)? = nil) async throws {
        guard canSync() else { return }

        syncState = .syncing
        let totalSteps = 4
        var completed = 0

        do {
            // 대화
            try await pushConversations()
            completed += 1
            onProgress?(Double(completed) / Double(totalSteps))
            syncProgress = SyncProgress(totalItems: totalSteps, completedItems: completed, currentEntity: "메모리", startedAt: Date())

            // 메모리
            try await pushMemory()
            completed += 1
            onProgress?(Double(completed) / Double(totalSteps))
            syncProgress = SyncProgress(totalItems: totalSteps, completedItems: completed, currentEntity: "칸반", startedAt: Date())

            // 칸반 (placeholder)
            completed += 1
            onProgress?(Double(completed) / Double(totalSteps))
            syncProgress = SyncProgress(totalItems: totalSteps, completedItems: completed, currentEntity: "프로필", startedAt: Date())

            // 프로필
            try await pushProfiles()
            completed += 1
            onProgress?(Double(completed) / Double(totalSteps))

            syncMetadata.lastSyncTimestamp = Date()
            saveMetadata()
            lastSuccessfulSync = syncMetadata.lastSyncTimestamp
            syncState = .idle
            syncProgress = .empty

            Log.cloud.info("Initial upload completed")
        } catch {
            syncState = .error(message: String(error.localizedDescription.prefix(50)))
            syncProgress = .empty
            throw error
        }
    }

    /// 충돌 해결
    func resolveConflict(id: UUID, resolution: ConflictResolution) {
        guard let index = syncConflicts.firstIndex(where: { $0.id == id }) else { return }
        let conflict = syncConflicts[index]

        switch resolution {
        case .keepLocal:
            // 로컬 데이터를 push 큐에 추가
            enqueueChange(entityType: conflict.entityType, entityId: conflict.entityId, action: .update)
        case .keepRemote:
            // pull 시 원격 데이터로 덮어쓰기 (다음 sync에서 처리)
            Log.cloud.info("Conflict resolved: keep remote for \(conflict.entityId)")
        case .merge:
            // 병합은 메모리 타입에서만 지원 — 여기서는 로컬 우선으로 fallback
            enqueueChange(entityType: conflict.entityType, entityId: conflict.entityId, action: .update)
            Log.cloud.info("Conflict merged for \(conflict.entityId)")
        }

        syncConflicts.remove(at: index)

        if syncConflicts.isEmpty {
            syncState = .idle
        } else {
            syncState = .conflict(count: syncConflicts.count)
        }

        addHistoryEntry(
            direction: .outgoing,
            entityType: conflict.entityType,
            entityTitle: "충돌 해결: \(conflict.entityTitle)",
            success: true
        )
    }

    /// 모든 충돌을 일괄 해결
    func resolveAllConflicts(resolution: ConflictResolution) {
        let conflicts = syncConflicts
        for conflict in conflicts {
            resolveConflict(id: conflict.id, resolution: resolution)
        }
    }

    /// 로컬 변경 발생 시 큐에 적재
    func enqueueChange(entityType: SyncEntityType, entityId: String, action: SyncAction, payload: Data? = nil) {
        let item = SyncQueueItem(
            entityType: entityType,
            entityId: entityId,
            action: action,
            payload: payload
        )
        offlineQueue.append(item)
        saveOfflineQueue()
        updatePendingCount()

        Log.cloud.debug("Enqueued sync change: \(entityType.rawValue)/\(entityId)/\(action.rawValue)")
    }

    /// 토스트 이벤트 제거
    func dismissSyncToast(id: UUID) {
        syncToastEvents.removeAll { $0.id == id }
    }

    /// 네트워크 상태 업데이트
    func updateOnlineStatus(isOnline: Bool) {
        self.isOnline = isOnline
        if isOnline {
            if syncState == .offline {
                syncState = .idle
                // 온라인 복구 시 큐 flush
                Task {
                    await flushOfflineQueue()
                    await sync()
                }
            }
        } else {
            if syncState != .disabled {
                syncState = .offline
            }
        }
    }

    /// 동기화 대상 엔티티 수 반환
    func entityCounts() -> [SyncEntityType: Int] {
        var counts: [SyncEntityType: Int] = [:]

        if settings.syncConversations {
            counts[.conversation] = conversationService.list().count
        }
        if settings.syncMemory {
            counts[.memory] = 1 // workspace memory count
        }
        if settings.syncKanban {
            counts[.kanban] = 0 // placeholder
        }
        if settings.syncProfiles {
            counts[.profile] = contextService.loadProfiles().count
        }

        return counts
    }

    /// 자동 동기화 중지
    func stopAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
    }

    // MARK: - Private: Auto Sync

    private func startAutoSync() {
        autoSyncTask?.cancel()
        guard settings.autoSyncEnabled else { return }

        autoSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.autoSyncIntervalSeconds))
                guard !Task.isCancelled else { return }
                await self?.sync()
            }
        }
    }

    // MARK: - Private: Push

    private func pushConversations() async throws {
        let conversations = conversationService.list()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(conversations)
        try await supabaseService.pushEntities(type: .conversation, payload: data)

        addToast(direction: .outgoing, entityType: .conversation, entityTitle: "대화 \(conversations.count)건")
    }

    private func pushMemory() async throws {
        // Push workspace memory as a single payload
        let wsId = UUID(uuidString: settings.currentWorkspaceId) ?? UUID()
        if let memory = contextService.loadWorkspaceMemory(workspaceId: wsId) {
            let data = Data(memory.utf8)
            try await supabaseService.pushEntities(type: .memory, payload: data)
            addToast(direction: .outgoing, entityType: .memory, entityTitle: "워크스페이스 메모리")
        }
    }

    private func pushProfiles() async throws {
        let profiles = contextService.loadProfiles()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profiles)
        try await supabaseService.pushEntities(type: .profile, payload: data)

        addToast(direction: .outgoing, entityType: .profile, entityTitle: "프로필 \(profiles.count)건")
    }

    // MARK: - Private: Pull

    private func pullConversations() async throws {
        guard let data = try await supabaseService.pullEntities(type: .conversation, since: syncMetadata.lastSyncTimestamp) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let remoteConversations = try decoder.decode([Conversation].self, from: data)

        // 충돌 감지: updatedAt 비교
        let localConversations = conversationService.list()
        let localMap = Dictionary(uniqueKeysWithValues: localConversations.map { ($0.id.uuidString, $0) })

        for remote in remoteConversations {
            if let local = localMap[remote.id.uuidString] {
                if local.updatedAt != remote.updatedAt && local.updatedAt > (syncMetadata.entityTimestamps[remote.id.uuidString] ?? .distantPast) {
                    // 충돌 — 양쪽 다 변경됨
                    if settings.conflictResolutionStrategy == "lastWriteWins" {
                        // 최근 작성이 우선
                        if remote.updatedAt > local.updatedAt {
                            conversationService.save(conversation: remote)
                        }
                        // 로컬이 최신이면 유지 (다음 push에서 올라감)
                    } else {
                        // 수동 해결
                        let conflict = SyncConflict(
                            entityType: .conversation,
                            entityId: remote.id.uuidString,
                            entityTitle: remote.title,
                            localUpdatedAt: local.updatedAt,
                            remoteUpdatedAt: remote.updatedAt,
                            localPreview: String(local.messages.last?.content.prefix(100) ?? ""),
                            remotePreview: String(remote.messages.last?.content.prefix(100) ?? "")
                        )
                        syncConflicts.append(conflict)
                    }
                } else if remote.updatedAt > local.updatedAt {
                    // 원격이 더 최신
                    conversationService.save(conversation: remote)
                    addToast(direction: .incoming, entityType: .conversation, entityTitle: remote.title)
                }
            } else {
                // 새 대화 — 원격에서 수신
                conversationService.save(conversation: remote)
                addToast(direction: .incoming, entityType: .conversation, entityTitle: remote.title)
            }

            syncMetadata.entityTimestamps[remote.id.uuidString] = remote.updatedAt
        }
    }

    private func pullMemory() async throws {
        guard let data = try await supabaseService.pullEntities(type: .memory, since: syncMetadata.lastSyncTimestamp) else { return }

        let remoteMemory = String(data: data, encoding: .utf8) ?? ""
        guard !remoteMemory.isEmpty else { return }

        let wsId = UUID(uuidString: settings.currentWorkspaceId) ?? UUID()
        let localMemory = contextService.loadWorkspaceMemory(workspaceId: wsId)

        if localMemory != remoteMemory {
            if settings.conflictResolutionStrategy == "lastWriteWins" {
                // 원격 데이터 적용
                contextService.saveWorkspaceMemory(workspaceId: wsId, content: remoteMemory)
                addToast(direction: .incoming, entityType: .memory, entityTitle: "워크스페이스 메모리")
            } else if let localMemory, !localMemory.isEmpty {
                let conflict = SyncConflict(
                    entityType: .memory,
                    entityId: wsId.uuidString,
                    entityTitle: "워크스페이스 메모리",
                    localUpdatedAt: Date(),
                    remoteUpdatedAt: Date(),
                    localPreview: String(localMemory.prefix(200)),
                    remotePreview: String(remoteMemory.prefix(200))
                )
                syncConflicts.append(conflict)
            } else {
                contextService.saveWorkspaceMemory(workspaceId: wsId, content: remoteMemory)
                addToast(direction: .incoming, entityType: .memory, entityTitle: "워크스페이스 메모리")
            }
        }
    }

    private func pullProfiles() async throws {
        guard let data = try await supabaseService.pullEntities(type: .profile, since: syncMetadata.lastSyncTimestamp) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let remoteProfiles = try decoder.decode([UserProfile].self, from: data)

        if !remoteProfiles.isEmpty {
            // 원격 프로필이 있으면 병합 (이름 기준 매칭)
            var localProfiles = contextService.loadProfiles()
            let localNames = Set(localProfiles.map(\.name))

            for remote in remoteProfiles where !localNames.contains(remote.name) {
                localProfiles.append(remote)
                addToast(direction: .incoming, entityType: .profile, entityTitle: remote.name)
            }

            contextService.saveProfiles(localProfiles)
        }
    }

    // MARK: - Private: Offline Queue

    private func flushOfflineQueue() async {
        guard isOnline else { return }

        var failedItems: [SyncQueueItem] = []

        for item in offlineQueue {
            do {
                if let payload = item.payload {
                    try await supabaseService.pushEntities(type: item.entityType, payload: payload)
                }
            } catch {
                failedItems.append(item)
                Log.cloud.warning("Failed to flush queue item \(item.id): \(error.localizedDescription)")
            }
        }

        offlineQueue = failedItems
        saveOfflineQueue()
        updatePendingCount()
    }

    // MARK: - Private: Persistence

    private func loadMetadata() {
        guard FileManager.default.fileExists(atPath: metadataFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: metadataFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            syncMetadata = try decoder.decode(SyncMetadata.self, from: data)
            Log.cloud.debug("Loaded sync metadata")
        } catch {
            Log.cloud.warning("Failed to load sync metadata: \(error.localizedDescription)")
        }
    }

    private func saveMetadata() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(syncMetadata)
            try data.write(to: metadataFileURL, options: .atomic)
        } catch {
            Log.cloud.error("Failed to save sync metadata: \(error.localizedDescription)")
        }
    }

    private func loadOfflineQueue() {
        guard FileManager.default.fileExists(atPath: queueFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: queueFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            offlineQueue = try decoder.decode([SyncQueueItem].self, from: data)
            let count = offlineQueue.count
            Log.cloud.debug("Loaded offline queue: \(count) items")
        } catch {
            Log.cloud.warning("Failed to load offline queue: \(error.localizedDescription)")
        }
    }

    private func saveOfflineQueue() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(offlineQueue)
            try data.write(to: queueFileURL, options: .atomic)
        } catch {
            Log.cloud.error("Failed to save offline queue: \(error.localizedDescription)")
        }
    }

    private func updatePendingCount() {
        pendingLocalChanges = offlineQueue.count
    }

    // MARK: - Private: Helpers

    private func canSync() -> Bool {
        guard supabaseService.isConfigured else {
            syncState = .disabled
            return false
        }
        guard supabaseService.authState.isSignedIn else {
            syncState = .disabled
            return false
        }
        guard isOnline else {
            syncState = .offline
            return false
        }
        return true
    }

    private func addToast(direction: SyncDirection, entityType: SyncEntityType, entityTitle: String, isConflict: Bool = false) {
        let event = SyncToastEvent(
            direction: direction,
            entityType: entityType,
            entityTitle: entityTitle,
            isConflict: isConflict
        )
        syncToastEvents.append(event)

        // 자동 제거 (5초 후)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.syncToastEvents.removeAll { $0.id == event.id }
        }
    }

    private func addHistoryEntry(direction: SyncDirection, entityType: SyncEntityType, entityTitle: String, success: Bool, errorMessage: String? = nil) {
        let entry = SyncHistoryEntry(
            direction: direction,
            entityType: entityType,
            entityTitle: entityTitle,
            success: success,
            errorMessage: errorMessage
        )
        syncHistory.insert(entry, at: 0)
        if syncHistory.count > Self.maxHistoryEntries {
            syncHistory = Array(syncHistory.prefix(Self.maxHistoryEntries))
        }
    }
}
