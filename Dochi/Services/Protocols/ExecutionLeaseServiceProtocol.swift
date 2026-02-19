import Foundation

/// @MainActor required: lease state (active leases, routing records) is read/written
/// by ViewModel and HeartbeatService on the main actor. Isolating to MainActor prevents
/// data races on the in-memory stores without additional locking.
@MainActor
protocol ExecutionLeaseServiceProtocol {
    /// Acquire a new lease for a conversation execution.
    /// Selects the best available device based on capabilities, affinity, liveness, and user preference.
    func acquireLease(
        workspaceId: UUID,
        agentId: String,
        conversationId: String,
        requiredCapabilities: DeviceCapabilities?
    ) async throws -> ExecutionLease

    /// Renew an active lease, extending its expiration.
    func renewLease(leaseId: UUID) throws -> ExecutionLease

    /// Release a lease (normal completion).
    func releaseLease(leaseId: UUID) throws

    /// Reassign a lease to another device.
    func reassignLease(leaseId: UUID, reason: LeaseRoutingReason) throws -> ExecutionLease

    /// Get the active lease for a conversation, if any.
    func activeLease(for conversationId: String) -> ExecutionLease?

    /// Get routing history for a conversation.
    func routingHistory(for conversationId: String) -> [SessionRoutingRecord]

    /// Expire stale leases whose TTL has elapsed without renewal.
    func expireStaleLeases()
}
