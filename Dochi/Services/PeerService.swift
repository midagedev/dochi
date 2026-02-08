import Foundation
import Supabase
import os

/// 피어 메시지 타입
enum PeerMessageType: String, Codable {
    case ping                 // 연결 확인
    case pong                 // ping 응답
    case queryForward         // 쿼리를 다른 디바이스로 전달
    case responseForward      // 응답을 다른 디바이스로 전달
    case capabilityRequest    // 기능 요청 (예: TTS 없는 디바이스가 TTS 가능한 디바이스에 요청)
    case capabilityResponse   // 기능 응답
    case notification         // 일반 알림
}

/// 수신된 피어 메시지
struct PeerMessage: Identifiable, Codable {
    let id: UUID
    let workspaceId: UUID
    let fromDeviceId: UUID
    let toDeviceId: UUID?
    let messageType: String
    let payload: String  // JSONB as string
    let createdAt: Date
    var readAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case fromDeviceId = "from_device_id"
        case toDeviceId = "to_device_id"
        case messageType = "message_type"
        case payload
        case createdAt = "created_at"
        case readAt = "read_at"
    }
}

/// Supabase Realtime을 릴레이로 사용하는 피어 메시징 서비스
@MainActor
final class PeerService: ObservableObject {
    @Published private(set) var unreadMessages: [PeerMessage] = []

    /// 피어 메시지 수신 콜백
    var onMessageReceived: ((PeerMessage) -> Void)?

    private let supabaseService: SupabaseService
    private let deviceService: DeviceService
    private var realtimeTask: Task<Void, Never>?

    init(supabaseService: SupabaseService, deviceService: DeviceService) {
        self.supabaseService = supabaseService
        self.deviceService = deviceService
    }

    // MARK: - Send

    /// 특정 디바이스에 메시지 전송
    func send(
        to targetDeviceId: UUID,
        type: PeerMessageType,
        payload: [String: Any] = [:]
    ) async throws {
        guard let client = supabaseService.client,
              let wsId = supabaseService.selectedWorkspace?.id,
              let fromId = deviceService.currentDevice?.id else { return }

        let payloadDict = encodablePayload(from: payload)

        try await client
            .from("peer_messages")
            .insert(PeerMessageInsert(
                workspace_id: wsId,
                from_device_id: fromId,
                to_device_id: targetDeviceId,
                message_type: type.rawValue,
                payload: payloadDict
            ))
            .execute()

        Log.cloud.debug("피어 메시지 전송: \(type.rawValue, privacy: .public) → \(targetDeviceId, privacy: .public)")
    }

    /// 워크스페이스의 모든 피어에 브로드캐스트
    func broadcast(
        type: PeerMessageType,
        payload: [String: Any] = [:]
    ) async throws {
        guard let client = supabaseService.client,
              let wsId = supabaseService.selectedWorkspace?.id,
              let fromId = deviceService.currentDevice?.id else { return }

        let payloadDict = encodablePayload(from: payload)

        try await client
            .from("peer_messages")
            .insert(PeerMessageInsert(
                workspace_id: wsId,
                from_device_id: fromId,
                to_device_id: nil,
                message_type: type.rawValue,
                payload: payloadDict
            ))
            .execute()

        Log.cloud.debug("피어 브로드캐스트: \(type.rawValue, privacy: .public)")
    }

    // MARK: - Receive (Realtime)

    /// Realtime 구독 시작 — 이 디바이스로 온 메시지 수신
    func subscribeToMessages() {
        guard let client = supabaseService.client,
              let wsId = supabaseService.selectedWorkspace?.id,
              let selfId = deviceService.currentDevice?.id else { return }
        unsubscribeFromMessages()

        realtimeTask = Task { [weak self] in
            let channel = client.realtimeV2.channel("peer-msgs-\(selfId.uuidString)")

            // 이 디바이스 대상 메시지 + 브로드캐스트 메시지 모두 수신 위해
            // workspace 전체를 구독하고 클라이언트에서 필터링
            let insertions = channel.postgresChange(
                InsertAction.self,
                schema: "public",
                table: "peer_messages",
                filter: .eq("workspace_id", value: wsId)
            )

            do {
                try await channel.subscribeWithError()
                Log.cloud.info("피어 메시지 Realtime 구독 시작")
            } catch {
                Log.cloud.warning("피어 메시지 Realtime 구독 실패: \(error, privacy: .public)")
                return
            }

            for await insertion in insertions {
                guard !Task.isCancelled else { break }
                await self?.handleIncomingMessage(insertion, selfDeviceId: selfId)
            }
        }
    }

    func unsubscribeFromMessages() {
        realtimeTask?.cancel()
        realtimeTask = nil
    }

    /// 읽지 않은 메시지 로드
    func fetchUnreadMessages() async throws {
        guard let wsId = supabaseService.selectedWorkspace?.id,
              let selfId = deviceService.currentDevice?.id else { return }

        guard let client = supabaseService.client else { return }

        let messages: [PeerMessage] = try await client
            .from("peer_messages")
            .select()
            .eq("workspace_id", value: wsId)
            .or("to_device_id.eq.\(selfId),to_device_id.is.null")
            .is("read_at", value: nil)
            .order("created_at", ascending: false)
            .execute()
            .value

        unreadMessages = messages
    }

    /// 메시지 읽음 처리
    func markAsRead(_ messageId: UUID) async throws {
        guard let client = supabaseService.client,
              let selfId = deviceService.currentDevice?.id else { return }

        struct ReadUpdate: Encodable {
            let read_at: Date
        }

        try await client
            .from("peer_messages")
            .update(ReadUpdate(read_at: Date()))
            .eq("id", value: messageId)
            .or("to_device_id.eq.\(selfId),to_device_id.is.null")
            .execute()

        unreadMessages.removeAll { $0.id == messageId }
    }

    // MARK: - Helpers

    private func handleIncomingMessage(_ insertion: InsertAction, selfDeviceId: UUID) {
        do {
            let message = try insertion.decodeRecord(
                as: PeerMessage.self,
                decoder: PostgrestClient.Configuration.jsonDecoder
            )

            // 자기 자신이 보낸 메시지는 무시
            guard message.fromDeviceId != selfDeviceId else { return }

            // 이 디바이스 대상이거나 브로드캐스트(to_device_id == nil)만 처리
            guard message.toDeviceId == nil || message.toDeviceId == selfDeviceId else { return }

            unreadMessages.insert(message, at: 0)
            onMessageReceived?(message)

            Log.cloud.info("피어 메시지 수신: \(message.messageType, privacy: .public) from \(message.fromDeviceId, privacy: .public)")
        } catch {
            Log.cloud.warning("피어 메시지 디코딩 실패: \(error, privacy: .public)")
        }
    }

    private func encodablePayload(from dict: [String: Any]) -> [String: String] {
        // 간단한 문자열 딕셔너리로 변환 — JSONB 컬럼에 이중 인코딩 없이 저장됨
        var result: [String: String] = [:]
        for (key, value) in dict {
            result[key] = "\(value)"
        }
        return result
    }
}

// MARK: - DTOs

private struct PeerMessageInsert: Encodable {
    let workspace_id: UUID
    let from_device_id: UUID
    let to_device_id: UUID?
    let message_type: String
    let payload: [String: String]
}
