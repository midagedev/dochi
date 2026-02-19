import Foundation

// MARK: - LeaseRoutingReason

enum LeaseRoutingReason: String, Codable, Sendable, CaseIterable {
    case initialAssignment
    case reassignmentOffline
    case reassignmentExpired
    case reassignmentManual
    case released
}

// MARK: - SessionRoutingRecord

struct SessionRoutingRecord: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let leaseId: UUID
    let workspaceId: UUID
    let agentId: String
    let conversationId: String
    let fromDeviceId: UUID?
    /// Target device for this routing event.
    /// `nil` when the lease is released (no destination device).
    let toDeviceId: UUID?
    let reason: LeaseRoutingReason
    let timestamp: Date

    init(
        id: UUID = UUID(),
        leaseId: UUID,
        workspaceId: UUID,
        agentId: String,
        conversationId: String,
        fromDeviceId: UUID? = nil,
        toDeviceId: UUID? = nil,
        reason: LeaseRoutingReason,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.leaseId = leaseId
        self.workspaceId = workspaceId
        self.agentId = agentId
        self.conversationId = conversationId
        self.fromDeviceId = fromDeviceId
        self.toDeviceId = toDeviceId
        self.reason = reason
        self.timestamp = timestamp
    }
}
