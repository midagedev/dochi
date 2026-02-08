import Foundation
import Supabase
import os

/// 클라우드 동기화 컨텍스트 서비스
/// - 로컬 ContextService를 래핑하여 write-through 클라우드 동기화 제공
/// - Supabase Realtime으로 다른 디바이스 변경사항 즉시 반영
/// - 오프라인 시 로컬만 사용, 온라인 복귀 시 동기화
/// - Cloud-always-wins on pull: 풀 시 클라우드 내용이 로컬을 덮어씁니다
@MainActor
final class CloudContextService: ContextServiceProtocol {
    private let local: ContextService
    private let supabaseService: SupabaseService

    /// 다른 디바이스에서 컨텍스트가 변경되었을 때 호출
    var onContextChanged: (() -> Void)?

    private var realtimeTask: Task<Void, Never>?

    init(local: ContextService = ContextService(), supabaseService: SupabaseService) {
        self.local = local
        self.supabaseService = supabaseService
    }

    // MARK: - Cloud Sync State

    private var isSyncing = false

    // MARK: - System

    func loadSystem() -> String {
        local.loadSystem()
    }

    func saveSystem(_ content: String) {
        local.saveSystem(content)
        scheduleCloudPush(fileType: "system", content: content)
    }

    var systemPath: String {
        local.systemPath
    }

    // MARK: - Memory

    func loadMemory() -> String {
        local.loadMemory()
    }

    func saveMemory(_ content: String) {
        local.saveMemory(content)
        scheduleCloudPush(fileType: "memory", content: content)
    }

    func appendMemory(_ content: String) {
        local.appendMemory(content)
        scheduleCloudPush(fileType: "memory", content: local.loadMemory())
    }

    var memoryPath: String {
        local.memoryPath
    }

    var memorySize: Int {
        local.memorySize
    }

    // MARK: - Family Memory

    func loadFamilyMemory() -> String {
        local.loadFamilyMemory()
    }

    func saveFamilyMemory(_ content: String) {
        local.saveFamilyMemory(content)
        scheduleCloudPush(fileType: "family_memory", content: content)
    }

    func appendFamilyMemory(_ content: String) {
        local.appendFamilyMemory(content)
        scheduleCloudPush(fileType: "family_memory", content: local.loadFamilyMemory())
    }

    // MARK: - User Memory

    func loadUserMemory(userId: UUID) -> String {
        local.loadUserMemory(userId: userId)
    }

    func saveUserMemory(userId: UUID, content: String) {
        local.saveUserMemory(userId: userId, content: content)
        scheduleCloudPush(fileType: "user_memory", content: content, userId: userId)
    }

    func appendUserMemory(userId: UUID, content: String) {
        local.appendUserMemory(userId: userId, content: content)
        scheduleCloudPush(fileType: "user_memory", content: local.loadUserMemory(userId: userId), userId: userId)
    }

    // MARK: - Profiles

    func loadProfiles() -> [UserProfile] {
        local.loadProfiles()
    }

    func saveProfiles(_ profiles: [UserProfile]) {
        local.saveProfiles(profiles)
        scheduleProfilesPush(profiles)
    }

    // MARK: - Migration

    func migrateIfNeeded() {
        local.migrateIfNeeded()
    }

    // MARK: - Sync Operations

    /// 앱 시작 시 클라우드에서 최신 버전 가져오기 (Pull-on-launch)
    func pullFromCloud() async {
        guard let client = supabaseService.client,
              let wsId = resolveWorkspaceId() else { return }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let files: [ContextFileRow] = try await client
                .from("context_files")
                .select()
                .eq("workspace_id", value: wsId)
                .execute()
                .value

            for file in files {
                applyCloudFile(file)
            }

            // Pull profiles
            await pullProfilesFromCloud(workspaceId: wsId)

            Log.cloud.info("클라우드 컨텍스트 동기화 완료: \(files.count)개 파일")
        } catch {
            Log.cloud.warning("클라우드 컨텍스트 풀 실패: \(error, privacy: .public)")
        }
    }

    // MARK: - Realtime Subscriptions

    /// Supabase Realtime 구독 시작 — 다른 디바이스의 변경사항 즉시 반영
    func subscribeToRealtimeChanges() {
        guard let client = supabaseService.client,
              let wsId = resolveWorkspaceId() else { return }
        unsubscribeFromRealtime()

        realtimeTask = Task { [weak self] in
            let channel = client.realtimeV2.channel("context-\(wsId.uuidString)")

            let contextChanges = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "context_files",
                filter: .eq("workspace_id", value: wsId)
            )

            let profileChanges = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "profiles",
                filter: .eq("workspace_id", value: wsId)
            )

            do {
                try await channel.subscribeWithError()
                Log.cloud.info("컨텍스트 Realtime 구독 시작")
            } catch {
                Log.cloud.warning("컨텍스트 Realtime 구독 실패: \(error, privacy: .public)")
                return
            }

            // Listen for context_files changes
            Task { [weak self] in
                for await action in contextChanges {
                    guard !Task.isCancelled else { break }
                    await self?.handleContextRealtimeEvent(action)
                }
            }

            // Listen for profiles changes
            Task { [weak self] in
                for await action in profileChanges {
                    guard !Task.isCancelled else { break }
                    await self?.handleProfileRealtimeEvent(action, workspaceId: wsId)
                }
            }
        }
    }

    /// Realtime 구독 해제
    func unsubscribeFromRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
    }

    private func handleContextRealtimeEvent(_ action: AnyAction) {
        do {
            switch action {
            case .insert(let insert):
                let row = try insert.decodeRecord(as: ContextFileRow.self, decoder: PostgrestClient.Configuration.jsonDecoder)
                applyCloudFile(row)
                onContextChanged?()
            case .update(let update):
                let row = try update.decodeRecord(as: ContextFileRow.self, decoder: PostgrestClient.Configuration.jsonDecoder)
                applyCloudFile(row)
                onContextChanged?()
            case .delete:
                break // context_files are not deleted, only updated
            }
        } catch {
            Log.cloud.warning("컨텍스트 Realtime 이벤트 디코딩 실패: \(error, privacy: .public)")
        }
    }

    private func handleProfileRealtimeEvent(_ action: AnyAction, workspaceId: UUID) {
        // On any profile change, re-pull all profiles for simplicity
        switch action {
        case .insert, .update, .delete:
            Task {
                await self.pullProfilesFromCloud(workspaceId: workspaceId)
                self.onContextChanged?()
            }
        }
    }

    /// 로컬 변경 → 클라우드 동기화 (write-through, 비동기 fire-and-forget)
    private func scheduleCloudPush(fileType: String, content: String, userId: UUID? = nil) {
        let svc = supabaseService
        Task {
            guard let client = svc.client,
                  let wsId = svc.selectedWorkspace?.id else { return }
            guard case .signedIn = svc.authState else { return }
            let authUserId = self.resolveAuthUserId()

            do {
                let existing = try await self.fetchContextFile(workspaceId: wsId, fileType: fileType, userId: userId)

                if let existing {
                    let newVersion = existing.version + 1
                    try await client
                        .from("context_files")
                        .update(ContextFileUpdate(
                            content: content,
                            version: newVersion,
                            updated_at: Date(),
                            updated_by: authUserId
                        ))
                        .eq("id", value: existing.id)
                        .execute()

                    try await self.recordHistory(
                        contextFileId: existing.id,
                        workspaceId: wsId,
                        fileType: fileType,
                        content: content,
                        version: newVersion
                    )
                } else {
                    let inserted: ContextFileRow = try await client
                        .from("context_files")
                        .insert(ContextFileInsert(
                            workspace_id: wsId,
                            file_type: fileType,
                            user_id: userId,
                            content: content,
                            updated_by: authUserId
                        ))
                        .select()
                        .single()
                        .execute()
                        .value

                    try await self.recordHistory(
                        contextFileId: inserted.id,
                        workspaceId: wsId,
                        fileType: fileType,
                        content: content,
                        version: 1
                    )
                }

                Log.cloud.debug("클라우드 푸시 완료: \(fileType, privacy: .public)")
            } catch {
                Log.cloud.warning("클라우드 푸시 실패 (\(fileType, privacy: .public)): \(error, privacy: .public)")
            }
        }
    }

    private func scheduleProfilesPush(_ profiles: [UserProfile]) {
        let svc = supabaseService
        Task {
            guard let client = svc.client,
                  let wsId = svc.selectedWorkspace?.id else { return }
            guard case .signedIn = svc.authState else { return }

            do {
                if profiles.isEmpty {
                    try await client
                        .from("profiles")
                        .delete()
                        .eq("workspace_id", value: wsId)
                        .execute()
                } else {
                    let rows = profiles.map { profile in
                        ProfileRow(
                            id: profile.id,
                            workspace_id: wsId,
                            name: profile.name,
                            aliases: profile.aliases,
                            description: profile.description
                        )
                    }
                    try await client
                        .from("profiles")
                        .upsert(rows)
                        .execute()

                    // Remove profiles no longer in the list
                    let currentIds = profiles.map(\.id)
                    try await client
                        .from("profiles")
                        .delete()
                        .eq("workspace_id", value: wsId)
                        .not("id", operator: .in, value: currentIds)
                        .execute()
                }

                Log.cloud.debug("프로필 클라우드 푸시 완료: \(profiles.count)명")
            } catch {
                Log.cloud.warning("프로필 클라우드 푸시 실패: \(error, privacy: .public)")
            }
        }
    }

    private func pullProfilesFromCloud(workspaceId: UUID) async {
        guard let client = supabaseService.client else { return }
        do {
            let rows: [ProfileRow] = try await client
                .from("profiles")
                .select()
                .eq("workspace_id", value: workspaceId)
                .execute()
                .value

            if !rows.isEmpty {
                let profiles = rows.map { row in
                    UserProfile(
                        id: row.id,
                        name: row.name,
                        aliases: row.aliases,
                        description: row.description
                    )
                }
                local.saveProfiles(profiles)
                Log.cloud.debug("프로필 클라우드 풀 완료: \(profiles.count)명")
            }
        } catch {
            Log.cloud.warning("프로필 클라우드 풀 실패: \(error, privacy: .public)")
        }
    }

    // MARK: - Helpers

    private func resolveWorkspaceId() -> UUID? {
        guard case .signedIn = supabaseService.authState else { return nil }
        return supabaseService.selectedWorkspace?.id
    }

    private func resolveAuthUserId() -> UUID? {
        if case .signedIn(let id, _) = supabaseService.authState {
            return id
        }
        return nil
    }

    private func fetchContextFile(workspaceId: UUID, fileType: String, userId: UUID? = nil) async throws -> ContextFileRow? {
        guard let client = supabaseService.client else { return nil }
        var query = client
            .from("context_files")
            .select()
            .eq("workspace_id", value: workspaceId)
            .eq("file_type", value: fileType)

        if let userId {
            query = query.eq("user_id", value: userId)
        } else {
            query = query.is("user_id", value: nil)
        }

        let rows: [ContextFileRow] = try await query.execute().value
        return rows.first
    }

    private func applyCloudFile(_ file: ContextFileRow) {
        let localContent: String
        switch file.file_type {
        case "system":
            localContent = local.loadSystem()
        case "memory":
            localContent = local.loadMemory()
        case "family_memory":
            localContent = local.loadFamilyMemory()
        case "user_memory":
            if let uid = file.user_id {
                localContent = local.loadUserMemory(userId: uid)
            } else {
                return
            }
        default:
            return
        }

        // Cloud-always-wins: cloud content overwrites local if different
        if file.content != localContent {
            switch file.file_type {
            case "system":
                local.saveSystem(file.content)
            case "memory":
                local.saveMemory(file.content)
            case "family_memory":
                local.saveFamilyMemory(file.content)
            case "user_memory":
                if let uid = file.user_id {
                    local.saveUserMemory(userId: uid, content: file.content)
                }
            default:
                break
            }
            Log.cloud.info("클라우드 → 로컬 동기화: \(file.file_type, privacy: .public)")
        }
    }

    private func recordHistory(contextFileId: UUID, workspaceId: UUID, fileType: String, content: String, version: Int) async throws {
        guard let client = supabaseService.client else { return }
        try await client
            .from("context_history")
            .insert(ContextHistoryInsert(
                context_file_id: contextFileId,
                workspace_id: workspaceId,
                file_type: fileType,
                content: content,
                version: version,
                edited_by: resolveAuthUserId()
            ))
            .execute()
    }
}

// MARK: - Codable DTOs

private struct ContextFileRow: Codable {
    let id: UUID
    let workspace_id: UUID
    let file_type: String
    let user_id: UUID?
    let content: String
    let version: Int
    let updated_at: Date
    let updated_by: UUID?
}

private struct ContextFileInsert: Encodable {
    let workspace_id: UUID
    let file_type: String
    let user_id: UUID?
    let content: String
    let updated_by: UUID?
}

private struct ContextFileUpdate: Encodable {
    let content: String
    let version: Int
    let updated_at: Date
    let updated_by: UUID?
}

private struct ContextHistoryInsert: Encodable {
    let context_file_id: UUID
    let workspace_id: UUID
    let file_type: String
    let content: String
    let version: Int
    let edited_by: UUID?
}

private struct ProfileRow: Codable {
    let id: UUID
    let workspace_id: UUID
    let name: String
    let aliases: [String]
    let description: String
}
