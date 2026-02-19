import Foundation
import os

// MARK: - ExecutionLeaseError

enum ExecutionLeaseError: Error, LocalizedError {
    case noDeviceAvailable
    case leaseNotFound(UUID)
    case leaseNotActive(UUID)
    case leaseExpired(UUID)
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
        case .leaseExpired(let id):
            return "Lease has expired: \(id)"
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

    #if DEBUG
    /// Inject a lease directly for testing purposes only.
    func injectLease(_ lease: ExecutionLease) {
        leases[lease.leaseId] = lease
        if lease.status == .active {
            conversationLeaseMap[lease.conversationId] = lease.leaseId
        }
    }
    #endif

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

        // Select best device (includes agent affinity scoring)
        guard let selectedDevice = selectDevice(requiredCapabilities: requiredCapabilities, agentId: agentId) else {
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
        guard !lease.isExpired else {
            throw ExecutionLeaseError.leaseExpired(leaseId)
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
            toDeviceId: nil,
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
            excludingDeviceId: oldLease.assignedDeviceId,
            agentId: oldLease.agentId
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

        // Phase 1: Collect expired lease IDs to avoid dictionary mutation during iteration
        let staleLeaseIds = leases
            .filter { $0.value.status == .active && $0.value.expiresAt < now }
            .map(\.key)

        guard !staleLeaseIds.isEmpty else { return }

        // Phase 2: Process each stale lease in a separate loop
        var expiredCount = 0
        for leaseId in staleLeaseIds {
            guard var lease = leases[leaseId], lease.status == .active else { continue }

            // Try to reassign first
            if let newDevice = selectDevice(
                requiredCapabilities: nil,
                excludingDeviceId: lease.assignedDeviceId,
                agentId: lease.agentId
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

    /// Select the best available device based on the 4-stage strategy:
    /// 1. Capability filtering  2. Agent affinity  3. Liveness  4. Load (policy-based)
    ///
    /// Agent affinity gives a bonus to the device that most recently executed the
    /// given agent. When two candidates are otherwise tied, the device with more
    /// recent affinity wins.
    private func selectDevice(
        requiredCapabilities: DeviceCapabilities? = nil,
        excludingDeviceId: UUID? = nil,
        agentId: String? = nil
    ) -> DeviceInfo? {
        // Stage 1: Capability filtering
        var candidates = devicePolicyService.registeredDevices
            .filter { $0.isOnline || $0.isCurrentDevice }

        // Exclude specific device (for reassignment)
        if let excludeId = excludingDeviceId {
            candidates.removeAll { $0.id == excludeId }
        }

        if let required = requiredCapabilities {
            candidates = candidates.filter { device in
                capabilitiesSatisfied(device: device.capabilities, required: required)
            }
        }

        guard !candidates.isEmpty else { return nil }

        // Stage 2: Compute agent affinity scores from routing history
        let affinityMap = buildAffinityMap(agentId: agentId)

        // Stage 3 + 4: Sort by policy, breaking ties with affinity
        let policy = devicePolicyService.currentPolicy

        switch policy {
        case .priorityBased:
            // Lower priority value is better → affinity bonus → most recent lastSeen
            candidates.sort { a, b in
                let aAffinity = affinityMap[a.id]
                let bAffinity = affinityMap[b.id]
                let aHasAffinity = aAffinity != nil
                let bHasAffinity = bAffinity != nil

                if a.priority != b.priority {
                    return a.priority < b.priority
                }
                // Same priority: prefer device with agent affinity
                if aHasAffinity != bHasAffinity {
                    return aHasAffinity
                }
                // Both have affinity: prefer more recent
                if let aDate = aAffinity, let bDate = bAffinity, aDate != bDate {
                    return aDate > bDate
                }
                return a.lastSeen > b.lastSeen
            }

        case .lastActive:
            // Most recently seen device first → affinity → priority
            candidates.sort { a, b in
                let aAffinity = affinityMap[a.id]
                let bAffinity = affinityMap[b.id]
                let aHasAffinity = aAffinity != nil
                let bHasAffinity = bAffinity != nil

                if a.lastSeen != b.lastSeen {
                    return a.lastSeen > b.lastSeen
                }
                if aHasAffinity != bHasAffinity {
                    return aHasAffinity
                }
                if let aDate = aAffinity, let bDate = bAffinity, aDate != bDate {
                    return aDate > bDate
                }
                return a.priority < b.priority
            }

        case .manual:
            // Prefer the device chosen by evaluateResponder (i.e. the manual device)
            let negotiation = devicePolicyService.evaluateResponder()
            let manualDeviceId: UUID? = {
                switch negotiation {
                case .thisDevice:
                    return devicePolicyService.currentDevice?.id
                case .otherDevice(let device):
                    return device.id
                case .noDeviceAvailable, .singleDevice:
                    return nil
                }
            }()

            if let manualId = manualDeviceId,
               let manualDevice = candidates.first(where: { $0.id == manualId }) {
                // Manual device satisfies capabilities — prefer it
                return manualDevice
            }
            // Fallback: sort by priority + affinity if manual device not in candidates
            candidates.sort { a, b in
                let aAffinity = affinityMap[a.id]
                let bAffinity = affinityMap[b.id]
                let aHasAffinity = aAffinity != nil
                let bHasAffinity = bAffinity != nil

                if a.priority != b.priority {
                    return a.priority < b.priority
                }
                if aHasAffinity != bHasAffinity {
                    return aHasAffinity
                }
                if let aDate = aAffinity, let bDate = bAffinity, aDate != bDate {
                    return aDate > bDate
                }
                return a.lastSeen > b.lastSeen
            }
        }

        return candidates.first
    }

    /// Build a map of deviceId → most recent routing timestamp for the given agent.
    /// Used to compute agent affinity: a device that recently ran the same agent
    /// is preferred (tiebreaker) in device selection.
    private func buildAffinityMap(agentId: String?) -> [UUID: Date] {
        guard let agentId, !agentId.isEmpty else { return [:] }

        var map: [UUID: Date] = [:]
        for record in routingRecords where record.agentId == agentId {
            guard let deviceId = record.toDeviceId else { continue }
            if let existing = map[deviceId] {
                if record.timestamp > existing {
                    map[deviceId] = record.timestamp
                }
            } else {
                map[deviceId] = record.timestamp
            }
        }
        return map
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
