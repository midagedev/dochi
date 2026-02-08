import Foundation
import Supabase
import os

/// 클라우드 동기화 대화 히스토리 서비스
/// - 로컬 ConversationService를 래핑하여 Supabase 동기화 제공
/// - Write-through: 저장/삭제 시 로컬 + 클라우드 동시 처리
/// - Pull-on-launch: 앱 시작 시 클라우드에서 대화 목록 동기화
/// - 소프트 딜리트: 클라우드에서는 deleted_at으로 표시
@MainActor
final class CloudConversationService: ConversationServiceProtocol {
    private let local: ConversationService
    private let supabaseService: SupabaseService
    private let deviceService: any DeviceServiceProtocol

    init(
        local: ConversationService = ConversationService(),
        supabaseService: SupabaseService,
        deviceService: any DeviceServiceProtocol
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
    /// Cloud-always-wins on pull: 풀 시 클라우드 내용이 로컬을 덮어씁니다
    func pullFromCloud() async {
        guard let client = supabaseService.client,
              case .signedIn = supabaseService.authState,
              let wsId = supabaseService.selectedWorkspace?.id else { return }

        do {
            // Fetch non-deleted conversations from cloud
            let cloudConversations: [CloudConversationRow] = try await client
                .from("conversations")
                .select()
                .eq("workspace_id", value: wsId)
                .is("deleted_at", value: nil)
                .order("updated_at", ascending: false)
                .execute()
                .value

            let localConversations = local.list()
            let localById = Dictionary(uniqueKeysWithValues: localConversations.map { ($0.id, $0) })

            for row in cloudConversations {
                if let localConv = localById[row.id] {
                    // Update local if cloud is newer
                    if row.updated_at > localConv.updatedAt {
                        local.save(row.toConversation())
                    }
                } else {
                    // Cloud-only conversation — save locally
                    local.save(row.toConversation())
                }
            }

            // Fetch soft-deleted conversations to clean up local copies
            let deletedRows: [CloudConversationRow] = try await client
                .from("conversations")
                .select()
                .eq("workspace_id", value: wsId)
                .not("deleted_at", operator: .is, value: Bool?.none)
                .execute()
                .value

            let deletedIds = Set(deletedRows.map(\.id))
            for localConv in localConversations where deletedIds.contains(localConv.id) {
                local.delete(id: localConv.id)
            }

            Log.cloud.info("대화 클라우드 동기화 완료: \(cloudConversations.count)개, 삭제: \(deletedRows.count)개")
        } catch {
            Log.cloud.warning("대화 클라우드 풀 실패: \(error, privacy: .public)")
        }
    }

    // MARK: - Push

    private func schedulePush(_ conversation: Conversation) {
        Task {
            guard let client = supabaseService.client,
                  case .signedIn = supabaseService.authState,
                  let wsId = supabaseService.selectedWorkspace?.id else { return }

            do {
                try await client
                    .from("conversations")
                    .upsert(CloudConversationInsert(
                        id: conversation.id,
                        workspace_id: wsId,
                        device_id: deviceService.currentDevice?.id,
                        title: conversation.title,
                        messages: conversation.messages,
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
        Task {
            guard let client = supabaseService.client,
                  case .signedIn = supabaseService.authState,
                  let wsId = supabaseService.selectedWorkspace?.id else { return }

            do {
                struct SoftDelete: Encodable {
                    let deleted_at: Date
                }

                try await client
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
    let messages: [Message]
    let summary: String?
    let user_id: String?
    let created_at: Date
    let updated_at: Date

    enum CodingKeys: String, CodingKey {
        case id, workspace_id, device_id, title, messages, summary, user_id, created_at, updated_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        workspace_id = try container.decode(UUID.self, forKey: .workspace_id)
        device_id = try container.decodeIfPresent(UUID.self, forKey: .device_id)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        user_id = try container.decodeIfPresent(String.self, forKey: .user_id)
        created_at = try container.decode(Date.self, forKey: .created_at)
        updated_at = try container.decode(Date.self, forKey: .updated_at)

        // Handle both JSONB array and legacy double-encoded string
        let rowId = id
        do {
            messages = try container.decode([Message].self, forKey: .messages)
        } catch {
            // Fallback: try decoding as string (legacy double-encoded format)
            if let jsonString = try? container.decode(String.self, forKey: .messages),
               let data = jsonString.data(using: .utf8) {
                let msgDecoder = JSONDecoder()
                msgDecoder.dateDecodingStrategy = .iso8601
                do {
                    messages = try msgDecoder.decode([Message].self, from: data)
                } catch {
                    Log.cloud.warning("메시지 파싱 실패 (id: \(rowId)): \(error, privacy: .public)")
                    messages = []
                }
            } else {
                Log.cloud.warning("메시지 파싱 실패 (id: \(rowId)): \(error, privacy: .public)")
                messages = []
            }
        }
    }

    func toConversation() -> Conversation {
        Conversation(
            id: id,
            title: title,
            messages: messages,
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
    let messages: [Message]
    let summary: String?
    let user_id: String?
    let created_at: Date
    let updated_at: Date
}
