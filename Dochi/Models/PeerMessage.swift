import Foundation

// MARK: - Message Types

enum PeerMessageType: String, Codable, Sendable, CaseIterable {
    case text
    case ttsRequest = "tts_request"
    case command
    case notification
    case taskResult = "task_result"

    var displayName: String {
        switch self {
        case .text: "텍스트"
        case .ttsRequest: "TTS 요청"
        case .command: "명령"
        case .notification: "알림"
        case .taskResult: "태스크 결과"
        }
    }
}

enum PeerMessageStatus: String, Codable, Sendable {
    case queued
    case delivered
    case processed
    case expired
    case failed
}

// MARK: - Peer Message Model

struct PeerMessage: Codable, Identifiable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let senderDeviceId: UUID
    let receiverDeviceId: UUID
    var type: PeerMessageType
    var payloadJSON: String
    var status: PeerMessageStatus
    let createdAt: Date
    var deliveredAt: Date?
    var processedAt: Date?
    var expiresAt: Date?
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        workspaceId: UUID,
        senderDeviceId: UUID,
        receiverDeviceId: UUID,
        type: PeerMessageType,
        payloadJSON: String = "{}",
        status: PeerMessageStatus = .queued,
        createdAt: Date = Date(),
        deliveredAt: Date? = nil,
        processedAt: Date? = nil,
        expiresAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.senderDeviceId = senderDeviceId
        self.receiverDeviceId = receiverDeviceId
        self.type = type
        self.payloadJSON = payloadJSON
        self.status = status
        self.createdAt = createdAt
        self.deliveredAt = deliveredAt
        self.processedAt = processedAt
        self.expiresAt = expiresAt
        self.errorMessage = errorMessage
    }

    var payload: [String: Any] {
        guard let data = payloadJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() > expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case senderDeviceId = "sender_device_id"
        case receiverDeviceId = "receiver_device_id"
        case type
        case payloadJSON = "payload_json"
        case status
        case createdAt = "created_at"
        case deliveredAt = "delivered_at"
        case processedAt = "processed_at"
        case expiresAt = "expires_at"
        case errorMessage = "error_message"
    }
}

// MARK: - Message Handler Protocol

@MainActor
protocol PeerMessageHandler {
    func handle(message: PeerMessage) async -> Bool
}

// MARK: - Peer Message Router

@MainActor
final class PeerMessageRouter {
    private(set) var inbox: [UUID: PeerMessage] = [:]      // received messages
    private(set) var outbox: [UUID: PeerMessage] = [:]     // sent messages
    private var handlers: [PeerMessageType: PeerMessageHandler] = [:]

    let localDeviceId: UUID
    let workspaceId: UUID
    private let defaultTTL: TimeInterval   // seconds

    init(localDeviceId: UUID, workspaceId: UUID, defaultTTL: TimeInterval = 86400) {
        self.localDeviceId = localDeviceId
        self.workspaceId = workspaceId
        self.defaultTTL = defaultTTL
    }

    // MARK: - Handler Registration

    func registerHandler(_ handler: PeerMessageHandler, for type: PeerMessageType) {
        handlers[type] = handler
    }

    // MARK: - Send

    @discardableResult
    func send(
        to receiverDeviceId: UUID,
        type: PeerMessageType,
        payloadJSON: String = "{}",
        ttl: TimeInterval? = nil
    ) -> PeerMessage {
        let expiresAt = Date().addingTimeInterval(ttl ?? defaultTTL)
        let message = PeerMessage(
            workspaceId: workspaceId,
            senderDeviceId: localDeviceId,
            receiverDeviceId: receiverDeviceId,
            type: type,
            payloadJSON: payloadJSON,
            expiresAt: expiresAt
        )
        outbox[message.id] = message
        Log.cloud.info("Peer message queued: \(type.rawValue) → \(receiverDeviceId.uuidString.prefix(8))")
        return message
    }

    // MARK: - Receive

    /// Called when a message arrives (e.g., from Supabase Realtime).
    func receive(message: PeerMessage) async {
        // Skip if expired
        if message.isExpired {
            var expired = message
            expired.status = .expired
            inbox[message.id] = expired
            Log.cloud.debug("Peer message expired on arrival: [\(message.id.uuidString.prefix(8))]")
            return
        }

        var msg = message
        msg.status = .delivered
        msg.deliveredAt = Date()
        inbox[msg.id] = msg

        Log.cloud.info("Peer message received: \(msg.type.rawValue) from \(msg.senderDeviceId.uuidString.prefix(8))")

        // Process with handler
        if let handler = handlers[msg.type] {
            let success = await handler.handle(message: msg)
            msg.status = success ? .processed : .failed
            if !success {
                msg.errorMessage = "핸들러 처리 실패"
            }
            msg.processedAt = Date()
        } else {
            msg.status = .failed
            msg.errorMessage = "등록된 핸들러 없음: \(msg.type.rawValue)"
            Log.cloud.warning("No handler for peer message type: \(msg.type.rawValue)")
        }
        inbox[msg.id] = msg
    }

    /// Deliver queued messages for this device (called on reconnect).
    func deliverQueued(messages: [PeerMessage]) async {
        let pending = messages
            .filter { $0.receiverDeviceId == localDeviceId && $0.status == .queued }
            .sorted { $0.createdAt < $1.createdAt }

        if !pending.isEmpty {
            Log.cloud.info("Delivering \(pending.count) queued peer messages")
        }

        for message in pending {
            await receive(message: message)
        }
    }

    // MARK: - Query

    func pendingOutbox() -> [PeerMessage] {
        outbox.values
            .filter { $0.status == .queued }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func recentInbox(limit: Int = 50) -> [PeerMessage] {
        Array(
            inbox.values
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(limit)
        )
    }

    func markSent(messageId: UUID) {
        guard var msg = outbox[messageId] else { return }
        msg.status = .delivered
        msg.deliveredAt = Date()
        outbox[messageId] = msg
    }

    // MARK: - Cleanup

    func cleanupExpired() {
        let now = Date()

        // Expire queued messages past TTL
        for (id, msg) in inbox where msg.status == .queued || msg.status == .delivered {
            if let expiresAt = msg.expiresAt, expiresAt < now {
                var expired = msg
                expired.status = .expired
                inbox[id] = expired
            }
        }

        for (id, msg) in outbox where msg.status == .queued {
            if let expiresAt = msg.expiresAt, expiresAt < now {
                var expired = msg
                expired.status = .expired
                outbox[id] = expired
            }
        }
    }

    /// Removes processed/expired/failed messages older than cutoff.
    func purge(olderThan interval: TimeInterval = 86400) {
        let cutoff = Date().addingTimeInterval(-interval)
        let terminalStatuses: Set<PeerMessageStatus> = [.processed, .expired, .failed]

        inbox = inbox.filter { _, msg in
            !(terminalStatuses.contains(msg.status) && msg.createdAt < cutoff)
        }

        outbox = outbox.filter { _, msg in
            !(terminalStatuses.contains(msg.status) && msg.createdAt < cutoff)
        }
    }
}
