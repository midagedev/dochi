import Foundation

// MARK: - MemoryAuditEvent

/// Records an action taken on a memory candidate for audit/traceability.
struct MemoryAuditEvent: Codable, Sendable {
    let eventId: String
    let timestamp: Date
    let candidateId: String
    let targetLayer: MemoryTargetLayer
    let action: MemoryAuditAction
    let workspaceId: String
    let agentId: String?
    let userId: String?
    let reason: String

    init(
        eventId: String = UUID().uuidString,
        timestamp: Date = Date(),
        candidateId: String,
        targetLayer: MemoryTargetLayer,
        action: MemoryAuditAction,
        workspaceId: String,
        agentId: String? = nil,
        userId: String? = nil,
        reason: String
    ) {
        self.eventId = eventId
        self.timestamp = timestamp
        self.candidateId = candidateId
        self.targetLayer = targetLayer
        self.action = action
        self.workspaceId = workspaceId
        self.agentId = agentId
        self.userId = userId
        self.reason = reason
    }
}

// MARK: - MemoryAuditAction

/// The kind of action recorded in a memory audit event.
enum MemoryAuditAction: String, Codable, Sendable {
    case stored
    case dropped
    case deduplicated
    case retryQueued
    case retryFailed
    case projectionRefreshed
    case projectionFailed
    case autoApproved
    case pendingApproval
    case conflictDetected
    case conflictDropped
}

// MARK: - MemoryApprovalPolicy

/// 메모리 쓰기 승인 정책.
/// - `auto`: 중복검사 통과 후 자동 승인하여 즉시 저장
/// - `requireApproval`: 사용자 승인 대기 상태로 전환
enum MemoryApprovalPolicy: String, Codable, Sendable {
    case auto
    case requireApproval
}
