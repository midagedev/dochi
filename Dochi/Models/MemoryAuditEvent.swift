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
}
