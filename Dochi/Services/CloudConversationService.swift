import Foundation
import Supabase
import os

/// 클라우드 동기화 대화 히스토리 서비스
/// - 로컬 ConversationService를 래핑하여 Supabase 동기화 제공
/// - Write-through: 저장/삭제 시 로컬 + 클라우드 동시 처리
/// - Pull-on-launch: 앱 시작 시 클라우드에서 대화 목록 동기화
/// - 소프트 딜리트: 클라우드에서는 deleted_at으로 표시
final class CloudConversationService: ConversationServiceProtocol, @unchecked Sendable {
    private let local: ConversationService
    private let supabaseService: SupabaseService
    private let deviceService: DeviceService

    init(
        local: ConversationService = ConversationService(),
        supabaseService: SupabaseService,
        deviceService: DeviceService
    ) {
        self.local = local
        self.supabaseService = supabaseService
        self.deviceService = deviceService
    }

    // MARK: - ConversationServiceProtocol

    func list() -> [Conversation] {
        local.list()
    }

    func load(id: UUID) -> Conversation? {
        local.load(id: id)
    }

    func save(_ conversation: Conversation) {
        local.save(conversation)
        schedulePush(conversation)
    }

    func delete(id: UUID) {
        local.delete(id: id)
        scheduleSoftDelete(id: id)
    }

    // MARK: - Cloud Sync

    /// 앱 시작 시 클라우드에서 대화 목록 동기화
    @MainActor
    func pullFromCloud() async {
        guard case .signedIn = supabaseService.authState,
              let wsId = supabaseService.selectedWorkspace?.id else { return }

        do {
            let cloudConversations: [CloudConversationRow] = try await supabaseService.client
                .from("conversations")
                .select()
                .eq("workspace_id", value: wsId)
                .is("deleted_at", value: nil)
                .order("updated_at", ascending: false)
                .execute()
                .value

            let localIds = Set(local.list().map(\.id))

            for row in cloudConversations {
                if !localIds.contains(row.id) {
                    // Cloud-only conversation — save locally
                    let conversation = row.toConversation()
                    local.save(conversation)
                }
            }

            Log.cloud.info("대화 클라우드 동기화 완료: \(cloudConversations.count)개")
        } catch {
            Log.cloud.warning("대화 클라우드 풀 실패: \(error, privacy: .public)")
        }
    }

    // MARK: - Push

    private func schedulePush(_ conversation: Conversation) {
        let svc = supabaseService
        let devSvc = deviceService
        Task { @MainActor in
            guard case .signedIn = svc.authState,
                  let wsId = svc.selectedWorkspace?.id else { return }

            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let messagesData = try encoder.encode(conversation.messages)
                let messagesJSON = String(data: messagesData, encoding: .utf8) ?? "[]"

                // Upsert
                try await svc.client
                    .from("conversations")
                    .upsert(CloudConversationInsert(
                        id: conversation.id,
                        workspace_id: wsId,
                        device_id: devSvc.currentDevice?.id,
                        title: conversation.title,
                        messages: messagesJSON,
                        summary: conversation.summary,
                        user_id: conversation.userId,
                        created_at: conversation.createdAt,
                        updated_at: conversation.updatedAt
                    ))
                    .execute()

                Log.cloud.debug("대화 클라우드 푸시 완료: \(conversation.id, privacy: .public)")
            } catch {
                Log.cloud.warning("대화 클라우드 푸시 실패: \(error, privacy: .public)")
            }
        }
    }

    private func scheduleSoftDelete(id: UUID) {
        let svc = supabaseService
        Task { @MainActor in
            guard case .signedIn = svc.authState,
                  let wsId = svc.selectedWorkspace?.id else { return }

            do {
                struct SoftDelete: Encodable {
                    let deleted_at: Date
                }

                try await svc.client
                    .from("conversations")
                    .update(SoftDelete(deleted_at: Date()))
                    .eq("id", value: id)
                    .eq("workspace_id", value: wsId)
                    .execute()

                Log.cloud.debug("대화 소프트 삭제: \(id, privacy: .public)")
            } catch {
                Log.cloud.warning("대화 소프트 삭제 실패: \(error, privacy: .public)")
            }
        }
    }
}

// MARK: - DTOs

private struct CloudConversationRow: Codable {
    let id: UUID
    let workspace_id: UUID
    let device_id: UUID?
    let title: String
    let messages: String  // JSONB stored as string
    let summary: String?
    let user_id: String?
    let created_at: Date
    let updated_at: Date

    func toConversation() -> Conversation {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let parsedMessages: [Message]
        if let data = messages.data(using: .utf8) {
            parsedMessages = (try? decoder.decode([Message].self, from: data)) ?? []
        } else {
            parsedMessages = []
        }

        return Conversation(
            id: id,
            title: title,
            messages: parsedMessages,
            createdAt: created_at,
            updatedAt: updated_at,
            userId: user_id,
            summary: summary
        )
    }
}

private struct CloudConversationInsert: Encodable {
    let id: UUID
    let workspace_id: UUID
    let device_id: UUID?
    let title: String
    let messages: String
    let summary: String?
    let user_id: String?
    let created_at: Date
    let updated_at: Date
}
