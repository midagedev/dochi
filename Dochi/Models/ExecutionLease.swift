import Foundation

// MARK: - LeaseStatus

enum LeaseStatus: String, Codable, Sendable, CaseIterable {
    case active
    case expired
    case reassigned
    case released
    case failed
}

// MARK: - ExecutionLease

struct ExecutionLease: Codable, Sendable, Identifiable, Equatable {
    static let defaultTTL: TimeInterval = 60

    let leaseId: UUID
    let workspaceId: UUID
    let agentId: String
    let conversationId: String
    var assignedDeviceId: UUID
    var status: LeaseStatus
    let createdAt: Date
    var expiresAt: Date
    var renewedAt: Date?
    var previousDeviceId: UUID?

    var id: UUID { leaseId }

    var isExpired: Bool {
        status == .expired || (status == .active && expiresAt < Date())
    }

    init(
        leaseId: UUID = UUID(),
        workspaceId: UUID,
        agentId: String,
        conversationId: String,
        assignedDeviceId: UUID,
        status: LeaseStatus = .active,
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        renewedAt: Date? = nil,
        previousDeviceId: UUID? = nil
    ) {
        self.leaseId = leaseId
        self.workspaceId = workspaceId
        self.agentId = agentId
        self.conversationId = conversationId
        self.assignedDeviceId = assignedDeviceId
        self.status = status
        self.createdAt = createdAt
        self.expiresAt = expiresAt ?? createdAt.addingTimeInterval(Self.defaultTTL)
        self.renewedAt = renewedAt
        self.previousDeviceId = previousDeviceId
    }
}
