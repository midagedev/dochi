import Foundation
import os

// MARK: - ExecutionLeaseError

enum ExecutionLeaseError: Error, LocalizedError {
    case noDeviceAvailable
    case leaseNotFound(UUID)
    case leaseNotActive(UUID)
    case duplicateLeaseForConversation(String)
    case reassignmentFailed(UUID)

    var errorDescription: String? {
        switch self {
        case .noDeviceAvailable:
            return "No online device available for lease assignment"
        case .leaseNotFound(let id):
            return "Lease not found: \(id)"
        case .leaseNotActive(let id):
            return "Lease is not active: \(id)"
        case .duplicateLeaseForConversation(let conversationId):
            return "Active lease already exists for conversation: \(conversationId)"
        case .reassignmentFailed(let id):
            return "Failed to reassign lease \(id): no alternative device available"
        }
    }
}

// MARK: - ExecutionLeaseService

@MainActor
final class ExecutionLeaseService: ExecutionLeaseServiceProtocol {

    // MARK: - Dependencies

    private let devicePolicyService: any DevicePolicyServiceProtocol

    // MARK: - In-memory stores

    private var leases: [UUID: ExecutionLease] = [:]              // leaseId -> ExecutionLease
    private var conversationLeaseMap: [String: UUID] = [:]        // conversationId -> leaseId
    private var routingRecords: [SessionRoutingRecord] = []

    // MARK: - Init

    init(devicePolicyService: any DevicePolicyServiceProtocol) {
        self.devicePolicyService = devicePolicyService
    }

    // MARK: - Acquire

    func acquireLease(
        workspaceId: UUID,
        agentId: String,
        conversationId: String,
        requiredCapabilities: DeviceCapabilities?
    ) async throws -> ExecutionLease {
        // Check for existing active lease
        if let existingLeaseId = conversationLeaseMap[conversationId],
           let existingLease = leases[existingLeaseId],
           existingLease.status == .active,
           !existingLease.isExpired {
            Log.app.warning("Duplicate lease request for conversation \(conversationId)")
            throw ExecutionLeaseError.duplicateLeaseForConversation(conversationId)
        }

        // Select best device
        guard let selectedDevice = selectDevice(requiredCapabilities: requiredCapabilities) else {
            Log.app.error("No device available for lease — workspace=\(workspaceId), agent=\(agentId)")
            throw ExecutionLeaseError.noDeviceAvailable
        }

        let lease = ExecutionLease(
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            assignedDeviceId: selectedDevice.id
        )

        leases[lease.leaseId] = lease
        conversationLeaseMap[conversationId] = lease.leaseId

        let record = SessionRoutingRecord(
            leaseId: lease.leaseId,
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            fromDeviceId: nil,
            toDeviceId: selectedDevice.id,
            reason: .initialAssignment
        )
        routingRecords.append(record)

        Log.app.info("Lease acquired: \(lease.leaseId) → device \(selectedDevice.id) for conversation \(conversationId)")
        return lease
    }

    // MARK: - Renew

    func renewLease(leaseId: UUID) throws -> ExecutionLease {
        guard var lease = leases[leaseId] else {
            throw ExecutionLeaseError.leaseNotFound(leaseId)
        }
        guard lease.status == .active else {
            throw ExecutionLeaseError.leaseNotActive(leaseId)
        }

        let now = Date()
        lease.expiresAt = now.addingTimeInterval(ExecutionLease.defaultTTL)
        lease.renewedAt = now
        leases[leaseId] = lease

        Log.app.debug("Lease renewed: \(leaseId), new expiry: \(lease.expiresAt)")
        return lease
    }

    // MARK: - Release

    func releaseLease(leaseId: UUID) throws {
        guard var lease = leases[leaseId] else {
            throw ExecutionLeaseError.leaseNotFound(leaseId)
        }
        guard lease.status == .active else {
            throw ExecutionLeaseError.leaseNotActive(leaseId)
        }

        lease.status = .released
        leases[leaseId] = lease
        conversationLeaseMap.removeValue(forKey: lease.conversationId)

        let record = SessionRoutingRecord(
            leaseId: leaseId,
            workspaceId: lease.workspaceId,
            agentId: lease.agentId,
            conversationId: lease.conversationId,
            fromDeviceId: lease.assignedDeviceId,
            toDeviceId: lease.assignedDeviceId,
            reason: .released
        )
        routingRecords.append(record)

        Log.app.info("Lease released: \(leaseId)")
    }

    // MARK: - Reassign

    func reassignLease(leaseId: UUID, reason: LeaseRoutingReason) throws -> ExecutionLease {
        guard var oldLease = leases[leaseId] else {
            throw ExecutionLeaseError.leaseNotFound(leaseId)
        }
        guard oldLease.status == .active else {
            throw ExecutionLeaseError.leaseNotActive(leaseId)
        }

        // Find an alternative device (exclude the currently assigned one)
        guard let newDevice = selectDevice(
            requiredCapabilities: nil,
            excludingDeviceId: oldLease.assignedDeviceId
        ) else {
            // No alternative — mark as failed
            oldLease.status = .failed
            leases[leaseId] = oldLease
            conversationLeaseMap.removeValue(forKey: oldLease.conversationId)
            Log.app.error("Lease reassignment failed — no alternative device: \(leaseId)")
            throw ExecutionLeaseError.reassignmentFailed(leaseId)
        }

        // Mark old lease as reassigned
        let previousDeviceId = oldLease.assignedDeviceId
        oldLease.status = .reassigned
        leases[leaseId] = oldLease

        // Create new lease
        let newLease = ExecutionLease(
            workspaceId: oldLease.workspaceId,
            agentId: oldLease.agentId,
            conversationId: oldLease.conversationId,
            assignedDeviceId: newDevice.id,
            previousDeviceId: previousDeviceId
        )

        leases[newLease.leaseId] = newLease
        conversationLeaseMap[oldLease.conversationId] = newLease.leaseId

        let record = SessionRoutingRecord(
            leaseId: newLease.leaseId,
            workspaceId: oldLease.workspaceId,
            agentId: oldLease.agentId,
            conversationId: oldLease.conversationId,
            fromDeviceId: previousDeviceId,
            toDeviceId: newDevice.id,
            reason: reason
        )
        routingRecords.append(record)

        Log.app.info("Lease reassigned: \(leaseId) → \(newLease.leaseId), device \(previousDeviceId) → \(newDevice.id), reason=\(reason.rawValue)")
        return newLease
    }

    // MARK: - Query

    func activeLease(for conversationId: String) -> ExecutionLease? {
        guard let leaseId = conversationLeaseMap[conversationId],
              let lease = leases[leaseId],
              lease.status == .active,
              !lease.isExpired else {
            return nil
        }
        return lease
    }

    func routingHistory(for conversationId: String) -> [SessionRoutingRecord] {
        routingRecords
            .filter { $0.conversationId == conversationId }
            .sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Expire Stale

    func expireStaleLeases() {
        let now = Date()
        var expiredCount = 0

        for (leaseId, var lease) in leases {
            guard lease.status == .active, lease.expiresAt < now else { continue }

            // Try to reassign first
            if let newDevice = selectDevice(
                requiredCapabilities: nil,
                excludingDeviceId: lease.assignedDeviceId
            ) {
                let previousDeviceId = lease.assignedDeviceId
                lease.status = .reassigned
                leases[leaseId] = lease

                let newLease = ExecutionLease(
                    workspaceId: lease.workspaceId,
                    agentId: lease.agentId,
                    conversationId: lease.conversationId,
                    assignedDeviceId: newDevice.id,
                    previousDeviceId: previousDeviceId
                )
                leases[newLease.leaseId] = newLease
                conversationLeaseMap[lease.conversationId] = newLease.leaseId

                let record = SessionRoutingRecord(
                    leaseId: newLease.leaseId,
                    workspaceId: lease.workspaceId,
                    agentId: lease.agentId,
                    conversationId: lease.conversationId,
                    fromDeviceId: previousDeviceId,
                    toDeviceId: newDevice.id,
                    reason: .reassignmentExpired
                )
                routingRecords.append(record)

                Log.app.info("Stale lease reassigned: \(leaseId) → \(newLease.leaseId)")
            } else {
                // No alternative — expire
                lease.status = .expired
                leases[leaseId] = lease
                conversationLeaseMap.removeValue(forKey: lease.conversationId)

                Log.app.warning("Lease expired with no alternative device: \(leaseId)")
            }
            expiredCount += 1
        }

        if expiredCount > 0 {
            Log.app.info("Expired/reassigned \(expiredCount) stale lease(s)")
        }
    }

    // MARK: - Device Selection

    /// Select the best available device based on capability, affinity, liveness, and user preference.
    private func selectDevice(
        requiredCapabilities: DeviceCapabilities? = nil,
        excludingDeviceId: UUID? = nil
    ) -> DeviceInfo? {
        var candidates = devicePolicyService.registeredDevices
            .filter { $0.isOnline || $0.isCurrentDevice }

        // Exclude specific device (for reassignment)
        if let excludeId = excludingDeviceId {
            candidates.removeAll { $0.id == excludeId }
        }

        // Filter by required capabilities
        if let required = requiredCapabilities {
            candidates = candidates.filter { device in
                capabilitiesSatisfied(device: device.capabilities, required: required)
            }
        }

        guard !candidates.isEmpty else { return nil }

        // Sort by priority (lower is better) as primary, then by lastSeen (more recent is better)
        candidates.sort { a, b in
            if a.priority != b.priority {
                return a.priority < b.priority
            }
            return a.lastSeen > b.lastSeen
        }

        return candidates.first
    }

    /// Check if a device's capabilities satisfy the required capabilities.
    private func capabilitiesSatisfied(device: DeviceCapabilities, required: DeviceCapabilities) -> Bool {
        if required.supportsVoice && !device.supportsVoice { return false }
        if required.supportsTTS && !device.supportsTTS { return false }
        if required.supportsNotifications && !device.supportsNotifications { return false }
        if required.supportsTools && !device.supportsTools { return false }
        return true
    }
}
