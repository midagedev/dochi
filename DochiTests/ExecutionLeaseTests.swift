import XCTest
@testable import Dochi

// MARK: - ExecutionLease Model Tests

final class ExecutionLeaseModelTests: XCTestCase {

    func testDefaultInitialization() {
        let lease = ExecutionLease(
            workspaceId: UUID(),
            agentId: "assistant",
            conversationId: "conv-1",
            assignedDeviceId: UUID()
        )
        XCTAssertEqual(lease.status, .active)
        XCTAssertNil(lease.renewedAt)
        XCTAssertNil(lease.previousDeviceId)
        XCTAssertEqual(lease.id, lease.leaseId)
    }

    func testDefaultTTL() {
        let before = Date()
        let lease = ExecutionLease(
            workspaceId: UUID(),
            agentId: "assistant",
            conversationId: "conv-1",
            assignedDeviceId: UUID()
        )
        let expectedExpiry = before.addingTimeInterval(ExecutionLease.defaultTTL)
        // Allow 1-second tolerance
        XCTAssertTrue(lease.expiresAt.timeIntervalSince(expectedExpiry) < 1.0)
        XCTAssertEqual(ExecutionLease.defaultTTL, 60)
    }

    func testIsExpiredWhenStatusActive() {
        let lease = ExecutionLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "c",
            assignedDeviceId: UUID(),
            expiresAt: Date().addingTimeInterval(-10)
        )
        XCTAssertTrue(lease.isExpired)
    }

    func testIsNotExpiredWhenStatusActiveAndFutureExpiry() {
        let lease = ExecutionLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "c",
            assignedDeviceId: UUID(),
            expiresAt: Date().addingTimeInterval(30)
        )
        XCTAssertFalse(lease.isExpired)
    }

    func testIsExpiredWhenStatusIsExpired() {
        let lease = ExecutionLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "c",
            assignedDeviceId: UUID(),
            status: .expired,
            expiresAt: Date().addingTimeInterval(30)
        )
        XCTAssertTrue(lease.isExpired)
    }

    func testCodableRoundtrip() throws {
        let original = ExecutionLease(
            workspaceId: UUID(),
            agentId: "agent-x",
            conversationId: "conv-42",
            assignedDeviceId: UUID(),
            renewedAt: Date(),
            previousDeviceId: UUID()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ExecutionLease.self, from: data)

        XCTAssertEqual(decoded.leaseId, original.leaseId)
        XCTAssertEqual(decoded.workspaceId, original.workspaceId)
        XCTAssertEqual(decoded.agentId, original.agentId)
        XCTAssertEqual(decoded.conversationId, original.conversationId)
        XCTAssertEqual(decoded.assignedDeviceId, original.assignedDeviceId)
        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.previousDeviceId, original.previousDeviceId)
    }

    func testEquatable() {
        let id = UUID()
        let wsId = UUID()
        let deviceId = UUID()
        let date = Date()

        let lease1 = ExecutionLease(
            leaseId: id,
            workspaceId: wsId,
            agentId: "a",
            conversationId: "c",
            assignedDeviceId: deviceId,
            createdAt: date,
            expiresAt: date.addingTimeInterval(60)
        )
        let lease2 = ExecutionLease(
            leaseId: id,
            workspaceId: wsId,
            agentId: "a",
            conversationId: "c",
            assignedDeviceId: deviceId,
            createdAt: date,
            expiresAt: date.addingTimeInterval(60)
        )
        XCTAssertEqual(lease1, lease2)
    }

    func testLeaseStatusAllCases() {
        XCTAssertEqual(LeaseStatus.allCases.count, 5)
        XCTAssertTrue(LeaseStatus.allCases.contains(.active))
        XCTAssertTrue(LeaseStatus.allCases.contains(.expired))
        XCTAssertTrue(LeaseStatus.allCases.contains(.reassigned))
        XCTAssertTrue(LeaseStatus.allCases.contains(.released))
        XCTAssertTrue(LeaseStatus.allCases.contains(.failed))
    }

    func testLeaseStatusCodable() throws {
        for status in LeaseStatus.allCases {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(LeaseStatus.self, from: data)
            XCTAssertEqual(decoded, status)
        }
    }
}

// MARK: - SessionRoutingRecord Model Tests

final class SessionRoutingRecordModelTests: XCTestCase {

    func testDefaultInitialization() {
        let record = SessionRoutingRecord(
            leaseId: UUID(),
            workspaceId: UUID(),
            agentId: "agent",
            conversationId: "conv",
            toDeviceId: UUID(),
            reason: .initialAssignment
        )
        XCTAssertNil(record.fromDeviceId)
        XCTAssertEqual(record.reason, .initialAssignment)
    }

    func testCodableRoundtrip() throws {
        let original = SessionRoutingRecord(
            leaseId: UUID(),
            workspaceId: UUID(),
            agentId: "agent-1",
            conversationId: "conv-1",
            fromDeviceId: UUID(),
            toDeviceId: UUID(),
            reason: .reassignmentOffline
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionRoutingRecord.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.leaseId, original.leaseId)
        XCTAssertEqual(decoded.fromDeviceId, original.fromDeviceId)
        XCTAssertEqual(decoded.toDeviceId, original.toDeviceId)
        XCTAssertEqual(decoded.reason, original.reason)
    }

    func testCodableRoundtripWithNilToDeviceId() throws {
        let original = SessionRoutingRecord(
            leaseId: UUID(),
            workspaceId: UUID(),
            agentId: "agent-1",
            conversationId: "conv-1",
            fromDeviceId: UUID(),
            toDeviceId: nil,
            reason: .released
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionRoutingRecord.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertNil(decoded.toDeviceId, "toDeviceId should be nil for release records")
        XCTAssertEqual(decoded.reason, original.reason)
    }

    func testLeaseRoutingReasonAllCases() {
        XCTAssertEqual(LeaseRoutingReason.allCases.count, 5)
        XCTAssertTrue(LeaseRoutingReason.allCases.contains(.initialAssignment))
        XCTAssertTrue(LeaseRoutingReason.allCases.contains(.reassignmentOffline))
        XCTAssertTrue(LeaseRoutingReason.allCases.contains(.reassignmentExpired))
        XCTAssertTrue(LeaseRoutingReason.allCases.contains(.reassignmentManual))
        XCTAssertTrue(LeaseRoutingReason.allCases.contains(.released))
    }

    func testLeaseRoutingReasonCodable() throws {
        for reason in LeaseRoutingReason.allCases {
            let data = try JSONEncoder().encode(reason)
            let decoded = try JSONDecoder().decode(LeaseRoutingReason.self, from: data)
            XCTAssertEqual(decoded, reason)
        }
    }
}

// MARK: - ExecutionLeaseService Tests

@MainActor
final class ExecutionLeaseServiceTests: XCTestCase {
    var mockDevicePolicy: MockDevicePolicyService!
    var service: ExecutionLeaseService!

    // Test device IDs
    var desktopId: UUID!
    var mobileId: UUID!
    var cliId: UUID!

    override func setUp() {
        super.setUp()
        mockDevicePolicy = MockDevicePolicyService()
        service = ExecutionLeaseService(devicePolicyService: mockDevicePolicy)

        desktopId = UUID()
        mobileId = UUID()
        cliId = UUID()

        // Register devices — desktop is current, all online
        mockDevicePolicy.registeredDevices = [
            DeviceInfo(
                id: desktopId,
                name: "Mac Studio",
                deviceType: .desktop,
                platform: .macos,
                lastSeen: Date(),
                isCurrentDevice: true,
                priority: 0
            ),
            DeviceInfo(
                id: mobileId,
                name: "iPhone",
                deviceType: .mobile,
                platform: .ios,
                lastSeen: Date(),
                isCurrentDevice: false,
                priority: 1
            ),
            DeviceInfo(
                id: cliId,
                name: "CLI Agent",
                deviceType: .cli,
                platform: .cli,
                lastSeen: Date(),
                isCurrentDevice: false,
                priority: 2
            ),
        ]
        mockDevicePolicy.currentDevice = mockDevicePolicy.registeredDevices[0]
    }

    // MARK: - Acquire Tests

    func testAcquireLeaseActive() async throws {
        let lease = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "assistant",
            conversationId: "conv-1",
            requiredCapabilities: nil
        )

        XCTAssertEqual(lease.status, .active)
        XCTAssertEqual(lease.assignedDeviceId, desktopId, "Should pick highest priority (desktop, priority=0)")
        XCTAssertEqual(lease.agentId, "assistant")
        XCTAssertEqual(lease.conversationId, "conv-1")
        XCTAssertNil(lease.previousDeviceId)
    }

    func testAcquireLeaseRecordsRoutingHistory() async throws {
        let lease = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "assistant",
            conversationId: "conv-1",
            requiredCapabilities: nil
        )

        let history = service.routingHistory(for: "conv-1")
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].leaseId, lease.leaseId)
        XCTAssertEqual(history[0].reason, .initialAssignment)
        XCTAssertNil(history[0].fromDeviceId)
        XCTAssertEqual(history[0].toDeviceId, desktopId)
    }

    func testAcquireLeaseDuplicatePrevented() async throws {
        _ = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "assistant",
            conversationId: "conv-1",
            requiredCapabilities: nil
        )

        do {
            _ = try await service.acquireLease(
                workspaceId: UUID(),
                agentId: "assistant",
                conversationId: "conv-1",
                requiredCapabilities: nil
            )
            XCTFail("Expected duplicate lease error")
        } catch let error as ExecutionLeaseError {
            if case .duplicateLeaseForConversation(let convId) = error {
                XCTAssertEqual(convId, "conv-1")
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    func testAcquireLeaseNoDeviceAvailable() async throws {
        mockDevicePolicy.registeredDevices = []

        do {
            _ = try await service.acquireLease(
                workspaceId: UUID(),
                agentId: "assistant",
                conversationId: "conv-1",
                requiredCapabilities: nil
            )
            XCTFail("Expected noDeviceAvailable error")
        } catch let error as ExecutionLeaseError {
            if case .noDeviceAvailable = error {
                // Expected
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    func testAcquireLeaseWithCapabilityFiltering() async throws {
        // Require voice — CLI doesn't support it
        let voiceRequired = DeviceCapabilities(
            supportsVoice: true,
            supportsTTS: false,
            supportsNotifications: false,
            supportsTools: false
        )

        let lease = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "assistant",
            conversationId: "conv-voice",
            requiredCapabilities: voiceRequired
        )

        // Desktop (priority 0) supports voice, should be selected
        XCTAssertEqual(lease.assignedDeviceId, desktopId)
    }

    func testAcquireLeaseCapabilityFilteringExcludesNonMatching() async throws {
        // Only CLI is online, require tools + voice (CLI has tools but no voice)
        mockDevicePolicy.registeredDevices = [
            DeviceInfo(
                id: cliId,
                name: "CLI Agent",
                deviceType: .cli,
                platform: .cli,
                lastSeen: Date(),
                isCurrentDevice: true,
                priority: 0
            ),
        ]
        mockDevicePolicy.currentDevice = mockDevicePolicy.registeredDevices[0]

        let voiceAndTools = DeviceCapabilities(
            supportsVoice: true,
            supportsTTS: false,
            supportsNotifications: false,
            supportsTools: true
        )

        do {
            _ = try await service.acquireLease(
                workspaceId: UUID(),
                agentId: "assistant",
                conversationId: "conv-2",
                requiredCapabilities: voiceAndTools
            )
            XCTFail("Expected noDeviceAvailable error")
        } catch let error as ExecutionLeaseError {
            if case .noDeviceAvailable = error {
                // Expected — CLI lacks voice
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    // MARK: - Renew Tests

    func testRenewLease() async throws {
        let lease = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-1",
            requiredCapabilities: nil
        )
        let originalExpiry = lease.expiresAt

        // Small delay to ensure time difference
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        let renewed = try service.renewLease(leaseId: lease.leaseId)
        XCTAssertEqual(renewed.status, .active)
        XCTAssertTrue(renewed.expiresAt > originalExpiry, "Expiry should be extended")
        XCTAssertNotNil(renewed.renewedAt)
    }

    func testRenewLeaseNotFound() {
        do {
            _ = try service.renewLease(leaseId: UUID())
            XCTFail("Expected leaseNotFound error")
        } catch let error as ExecutionLeaseError {
            if case .leaseNotFound = error {
                // Expected
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testRenewLeaseNotActive() async throws {
        let lease = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-1",
            requiredCapabilities: nil
        )
        try service.releaseLease(leaseId: lease.leaseId)

        do {
            _ = try service.renewLease(leaseId: lease.leaseId)
            XCTFail("Expected leaseNotActive error")
        } catch let error as ExecutionLeaseError {
            if case .leaseNotActive = error {
                // Expected
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    // MARK: - Release Tests

    func testReleaseLease() async throws {
        let lease = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-1",
            requiredCapabilities: nil
        )

        try service.releaseLease(leaseId: lease.leaseId)

        let active = service.activeLease(for: "conv-1")
        XCTAssertNil(active, "Released lease should not appear as active")

        let history = service.routingHistory(for: "conv-1")
        XCTAssertEqual(history.count, 2) // initial + release
        XCTAssertEqual(history[1].reason, .released)
    }

    func testReleaseLeaseNotFound() {
        do {
            try service.releaseLease(leaseId: UUID())
            XCTFail("Expected leaseNotFound error")
        } catch let error as ExecutionLeaseError {
            if case .leaseNotFound = error {
                // Expected
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Reassign Tests

    func testReassignLease() async throws {
        let lease = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "assistant",
            conversationId: "conv-1",
            requiredCapabilities: nil
        )
        // Lease is assigned to desktopId (priority 0)
        XCTAssertEqual(lease.assignedDeviceId, desktopId)

        let newLease = try service.reassignLease(leaseId: lease.leaseId, reason: .reassignmentOffline)

        XCTAssertEqual(newLease.status, .active)
        XCTAssertNotEqual(newLease.assignedDeviceId, desktopId, "Should be assigned to different device")
        XCTAssertEqual(newLease.previousDeviceId, desktopId)
        XCTAssertEqual(newLease.conversationId, "conv-1")

        // Original lease should be reassigned
        let active = service.activeLease(for: "conv-1")
        XCTAssertNotNil(active)
        XCTAssertEqual(active?.leaseId, newLease.leaseId)
    }

    func testReassignLeaseRoutingHistory() async throws {
        let lease = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-1",
            requiredCapabilities: nil
        )

        let newLease = try service.reassignLease(leaseId: lease.leaseId, reason: .reassignmentOffline)

        let history = service.routingHistory(for: "conv-1")
        XCTAssertEqual(history.count, 2) // initial + reassignment
        XCTAssertEqual(history[0].reason, .initialAssignment)
        XCTAssertEqual(history[1].reason, .reassignmentOffline)
        XCTAssertEqual(history[1].fromDeviceId, desktopId)
        XCTAssertEqual(history[1].leaseId, newLease.leaseId)
    }

    func testReassignLeaseFailsWhenNoAlternativeDevice() async throws {
        // Only one device
        mockDevicePolicy.registeredDevices = [
            DeviceInfo(
                id: desktopId,
                name: "Mac",
                deviceType: .desktop,
                platform: .macos,
                lastSeen: Date(),
                isCurrentDevice: true,
                priority: 0
            ),
        ]
        mockDevicePolicy.currentDevice = mockDevicePolicy.registeredDevices[0]

        let lease = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-1",
            requiredCapabilities: nil
        )

        do {
            _ = try service.reassignLease(leaseId: lease.leaseId, reason: .reassignmentOffline)
            XCTFail("Expected reassignmentFailed error")
        } catch let error as ExecutionLeaseError {
            if case .reassignmentFailed = error {
                // Expected
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }

        // Original lease should be marked as failed
        let active = service.activeLease(for: "conv-1")
        XCTAssertNil(active, "Failed lease should not appear as active")
    }

    // MARK: - Expire Stale Tests

    func testExpireStaleLeases_noExpiredLeases_doesNothing() async throws {
        // Acquire a fresh lease — expiresAt is 60s in the future
        let lease = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-stale",
            requiredCapabilities: nil
        )

        service.expireStaleLeases()

        // Lease should still be active (expiresAt is in the future)
        let active = service.activeLease(for: "conv-stale")
        XCTAssertNotNil(active)
        XCTAssertEqual(active?.leaseId, lease.leaseId)
    }

    func testExpireStaleLeases_expiredLease_reassignedToAlternativeDevice() {
        // Inject a lease with past expiry via DEBUG helper
        let expiredLease = ExecutionLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-expire-reassign",
            assignedDeviceId: desktopId,
            expiresAt: Date().addingTimeInterval(-10) // already expired
        )
        service.injectLease(expiredLease)

        // Before expire: activeLease returns nil because isExpired check
        XCTAssertNil(service.activeLease(for: "conv-expire-reassign"))

        // Run expire — should reassign to another device (mobile or CLI)
        service.expireStaleLeases()

        // A new active lease should exist for the same conversation
        let active = service.activeLease(for: "conv-expire-reassign")
        XCTAssertNotNil(active, "Expired lease should be reassigned to an alternative device")
        XCTAssertNotEqual(active?.leaseId, expiredLease.leaseId, "Should be a new lease")
        XCTAssertNotEqual(active?.assignedDeviceId, desktopId, "Should be on a different device")

        // Routing history should contain the reassignment record
        let history = service.routingHistory(for: "conv-expire-reassign")
        XCTAssertTrue(history.contains(where: { $0.reason == .reassignmentExpired }))
    }

    func testExpireStaleLeases_expiredLease_noAlternative_markedExpired() {
        // Only one device available
        mockDevicePolicy.registeredDevices = [
            DeviceInfo(
                id: desktopId,
                name: "Mac",
                deviceType: .desktop,
                platform: .macos,
                lastSeen: Date(),
                isCurrentDevice: true,
                priority: 0
            ),
        ]
        mockDevicePolicy.currentDevice = mockDevicePolicy.registeredDevices[0]

        // Inject an expired lease on the only device
        let expiredLease = ExecutionLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-expire-only",
            assignedDeviceId: desktopId,
            expiresAt: Date().addingTimeInterval(-10)
        )
        service.injectLease(expiredLease)

        service.expireStaleLeases()

        // No alternative device -> lease should be fully expired, not reassigned
        let active = service.activeLease(for: "conv-expire-only")
        XCTAssertNil(active, "Expired lease with no alternative should remain nil")
    }

    func testExpireStaleLeases_multipleExpired_allProcessed() {
        // Inject two expired leases on different devices
        let lease1 = ExecutionLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-multi-1",
            assignedDeviceId: desktopId,
            expiresAt: Date().addingTimeInterval(-10)
        )
        let lease2 = ExecutionLease(
            workspaceId: UUID(),
            agentId: "b",
            conversationId: "conv-multi-2",
            assignedDeviceId: mobileId,
            expiresAt: Date().addingTimeInterval(-5)
        )
        service.injectLease(lease1)
        service.injectLease(lease2)

        service.expireStaleLeases()

        // Both should have been processed (reassigned or expired)
        let active1 = service.activeLease(for: "conv-multi-1")
        XCTAssertNotNil(active1, "First expired lease should be reassigned")
        XCTAssertNotEqual(active1?.assignedDeviceId, desktopId)

        let active2 = service.activeLease(for: "conv-multi-2")
        XCTAssertNotNil(active2, "Second expired lease should be reassigned")
        XCTAssertNotEqual(active2?.assignedDeviceId, mobileId)
    }

    // MARK: - Active Lease Query Tests

    func testActiveLeaseReturnsNilForUnknownConversation() {
        let result = service.activeLease(for: "nonexistent")
        XCTAssertNil(result)
    }

    func testActiveLeaseReturnsNilAfterRelease() async throws {
        let lease = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-1",
            requiredCapabilities: nil
        )
        try service.releaseLease(leaseId: lease.leaseId)

        let active = service.activeLease(for: "conv-1")
        XCTAssertNil(active)
    }

    // MARK: - Routing History Tests

    func testRoutingHistoryEmpty() {
        let history = service.routingHistory(for: "nonexistent")
        XCTAssertTrue(history.isEmpty)
    }

    func testRoutingHistoryFullLifecycle() async throws {
        let wsId = UUID()

        // Acquire
        let lease = try await service.acquireLease(
            workspaceId: wsId,
            agentId: "a",
            conversationId: "conv-lifecycle",
            requiredCapabilities: nil
        )

        // Reassign
        let newLease = try service.reassignLease(leaseId: lease.leaseId, reason: .reassignmentManual)

        // Release the new lease
        try service.releaseLease(leaseId: newLease.leaseId)

        let history = service.routingHistory(for: "conv-lifecycle")
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history[0].reason, .initialAssignment)
        XCTAssertEqual(history[1].reason, .reassignmentManual)
        XCTAssertEqual(history[2].reason, .released)
    }

    func testRoutingHistorySortedByTimestamp() async throws {
        _ = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-sorted",
            requiredCapabilities: nil
        )

        let history = service.routingHistory(for: "conv-sorted")
        for i in 1..<history.count {
            XCTAssertTrue(history[i].timestamp >= history[i-1].timestamp)
        }
    }

    // MARK: - Device Selection Priority Tests

    func testDeviceSelectionRespectsPriority() async throws {
        // Desktop has priority 0 (highest), should be selected
        let lease = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-priority",
            requiredCapabilities: nil
        )
        XCTAssertEqual(lease.assignedDeviceId, desktopId)
    }

    func testDeviceSelectionSkipsOfflineDevices() async throws {
        // Make desktop offline
        mockDevicePolicy.registeredDevices[0] = DeviceInfo(
            id: desktopId,
            name: "Mac Studio",
            deviceType: .desktop,
            platform: .macos,
            lastSeen: Date().addingTimeInterval(-300),
            isCurrentDevice: false,
            priority: 0
        )
        mockDevicePolicy.registeredDevices[1] = DeviceInfo(
            id: mobileId,
            name: "iPhone",
            deviceType: .mobile,
            platform: .ios,
            lastSeen: Date(),
            isCurrentDevice: true,
            priority: 1
        )
        mockDevicePolicy.currentDevice = mockDevicePolicy.registeredDevices[1]

        let lease = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-offline",
            requiredCapabilities: nil
        )
        XCTAssertEqual(lease.assignedDeviceId, mobileId, "Should skip offline desktop and pick mobile")
    }

    // MARK: - Error Description Tests

    func testErrorDescriptions() {
        let noDevice = ExecutionLeaseError.noDeviceAvailable
        XCTAssertNotNil(noDevice.errorDescription)
        XCTAssertTrue(noDevice.errorDescription!.contains("No online device"))

        let notFound = ExecutionLeaseError.leaseNotFound(UUID())
        XCTAssertNotNil(notFound.errorDescription)
        XCTAssertTrue(notFound.errorDescription!.contains("not found"))

        let notActive = ExecutionLeaseError.leaseNotActive(UUID())
        XCTAssertNotNil(notActive.errorDescription)
        XCTAssertTrue(notActive.errorDescription!.contains("not active"))

        let expired = ExecutionLeaseError.leaseExpired(UUID())
        XCTAssertNotNil(expired.errorDescription)
        XCTAssertTrue(expired.errorDescription!.contains("expired"))

        let duplicate = ExecutionLeaseError.duplicateLeaseForConversation("conv-1")
        XCTAssertNotNil(duplicate.errorDescription)
        XCTAssertTrue(duplicate.errorDescription!.contains("conv-1"))

        let reassignFailed = ExecutionLeaseError.reassignmentFailed(UUID())
        XCTAssertNotNil(reassignFailed.errorDescription)
        XCTAssertTrue(reassignFailed.errorDescription!.contains("reassign"))
    }

    // MARK: - Conversation Isolation Tests

    func testMultipleConversationsIndependent() async throws {
        let wsId = UUID()

        let lease1 = try await service.acquireLease(
            workspaceId: wsId,
            agentId: "a",
            conversationId: "conv-A",
            requiredCapabilities: nil
        )
        let lease2 = try await service.acquireLease(
            workspaceId: wsId,
            agentId: "a",
            conversationId: "conv-B",
            requiredCapabilities: nil
        )

        XCTAssertNotEqual(lease1.leaseId, lease2.leaseId)

        // Release conv-A, conv-B should still be active
        try service.releaseLease(leaseId: lease1.leaseId)

        XCTAssertNil(service.activeLease(for: "conv-A"))
        XCTAssertNotNil(service.activeLease(for: "conv-B"))

        // Routing histories should be separate
        let historyA = service.routingHistory(for: "conv-A")
        let historyB = service.routingHistory(for: "conv-B")
        XCTAssertEqual(historyA.count, 2) // acquire + release
        XCTAssertEqual(historyB.count, 1) // acquire only
    }

    // MARK: - After Release, Can Re-acquire Tests

    func testCanReAcquireAfterRelease() async throws {
        let wsId = UUID()

        let lease1 = try await service.acquireLease(
            workspaceId: wsId,
            agentId: "a",
            conversationId: "conv-reacquire",
            requiredCapabilities: nil
        )
        try service.releaseLease(leaseId: lease1.leaseId)

        // Should be able to acquire a new lease for the same conversation
        let lease2 = try await service.acquireLease(
            workspaceId: wsId,
            agentId: "a",
            conversationId: "conv-reacquire",
            requiredCapabilities: nil
        )
        XCTAssertNotEqual(lease1.leaseId, lease2.leaseId)
        XCTAssertEqual(lease2.status, .active)
    }

    // MARK: - C2: Renew Expired Lease Tests

    func testRenewExpiredLeaseThrowsLeaseExpired() {
        // Inject a lease with past expiry directly into the service
        let expiredLease = ExecutionLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-expired-renew",
            assignedDeviceId: desktopId,
            expiresAt: Date().addingTimeInterval(-10)
        )
        service.injectLease(expiredLease)

        // Lease has status .active but TTL has passed
        XCTAssertEqual(expiredLease.status, .active)
        XCTAssertTrue(expiredLease.isExpired)

        do {
            _ = try service.renewLease(leaseId: expiredLease.leaseId)
            XCTFail("Expected leaseExpired error")
        } catch let error as ExecutionLeaseError {
            if case .leaseExpired(let id) = error {
                XCTAssertEqual(id, expiredLease.leaseId)
            } else {
                XCTFail("Expected .leaseExpired, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testRenewNonExpiredLeaseSucceeds() async throws {
        let lease = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-non-expired",
            requiredCapabilities: nil
        )

        // Fresh lease with future expiry should succeed
        XCTAssertFalse(lease.isExpired)
        let renewed = try service.renewLease(leaseId: lease.leaseId)
        XCTAssertEqual(renewed.status, .active)
        XCTAssertNotNil(renewed.renewedAt)
    }

    func testLeaseExpiredErrorDescription() {
        let id = UUID()
        let error = ExecutionLeaseError.leaseExpired(id)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("expired"))
        XCTAssertTrue(error.errorDescription!.contains(id.uuidString))
    }

    // MARK: - C3: Device Selection Policy Tests

    func testDeviceSelectionPriorityBasedPolicy() async throws {
        mockDevicePolicy.currentPolicy = .priorityBased

        let lease = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-priority-policy",
            requiredCapabilities: nil
        )

        // Desktop has priority 0 (highest)
        XCTAssertEqual(lease.assignedDeviceId, desktopId)
    }

    func testDeviceSelectionLastActivePolicy() async throws {
        mockDevicePolicy.currentPolicy = .lastActive

        // Make mobile the most recently seen device
        let now = Date()
        mockDevicePolicy.registeredDevices[0] = DeviceInfo(
            id: desktopId,
            name: "Mac Studio",
            deviceType: .desktop,
            platform: .macos,
            lastSeen: now.addingTimeInterval(-60),
            isCurrentDevice: true,
            priority: 0
        )
        mockDevicePolicy.registeredDevices[1] = DeviceInfo(
            id: mobileId,
            name: "iPhone",
            deviceType: .mobile,
            platform: .ios,
            lastSeen: now,
            isCurrentDevice: false,
            priority: 1
        )
        mockDevicePolicy.registeredDevices[2] = DeviceInfo(
            id: cliId,
            name: "CLI Agent",
            deviceType: .cli,
            platform: .cli,
            lastSeen: now.addingTimeInterval(-120),
            isCurrentDevice: false,
            priority: 2
        )

        let lease = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-last-active",
            requiredCapabilities: nil
        )

        // Mobile has the most recent lastSeen
        XCTAssertEqual(lease.assignedDeviceId, mobileId)
    }

    func testDeviceSelectionManualPolicy() async throws {
        mockDevicePolicy.currentPolicy = .manual
        mockDevicePolicy.setManualDevice(id: cliId)

        let lease = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-manual",
            requiredCapabilities: nil
        )

        // Manual policy should prefer the manually set device (CLI)
        XCTAssertEqual(lease.assignedDeviceId, cliId)
    }

    func testDeviceSelectionManualPolicyFallsBackWhenManualDeviceDoesNotSatisfyCapabilities() async throws {
        mockDevicePolicy.currentPolicy = .manual
        mockDevicePolicy.setManualDevice(id: cliId)

        // CLI doesn't support voice
        let voiceRequired = DeviceCapabilities(
            supportsVoice: true,
            supportsTTS: false,
            supportsNotifications: false,
            supportsTools: false
        )

        let lease = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-manual-fallback",
            requiredCapabilities: voiceRequired
        )

        // CLI can't satisfy voice — should fallback to desktop
        XCTAssertEqual(lease.assignedDeviceId, desktopId)
    }

    // MARK: - Agent Affinity Tests

    func testAgentAffinityBreaksTieBetweenSamePriorityDevices() async throws {
        // Set up two devices with same priority
        let deviceA = UUID()
        let deviceB = UUID()
        let now = Date()
        mockDevicePolicy.registeredDevices = [
            DeviceInfo(
                id: deviceA,
                name: "Device A",
                deviceType: .desktop,
                platform: .macos,
                lastSeen: now,
                isCurrentDevice: true,
                priority: 0
            ),
            DeviceInfo(
                id: deviceB,
                name: "Device B",
                deviceType: .desktop,
                platform: .macos,
                lastSeen: now,
                isCurrentDevice: false,
                priority: 0
            ),
        ]
        mockDevicePolicy.currentDevice = mockDevicePolicy.registeredDevices[0]

        // First acquire goes to device A (or B — either is fine, but with same lastSeen and priority
        // the sort is stable so first in array wins).
        let lease1 = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "special-agent",
            conversationId: "conv-aff-1",
            requiredCapabilities: nil
        )
        try service.releaseLease(leaseId: lease1.leaseId)
        let firstDevice = lease1.assignedDeviceId

        // Now routing history has an affinity record for "special-agent" → firstDevice.
        // The second acquire for the same agent should prefer firstDevice due to affinity.
        let lease2 = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "special-agent",
            conversationId: "conv-aff-2",
            requiredCapabilities: nil
        )
        XCTAssertEqual(lease2.assignedDeviceId, firstDevice,
                        "Same agent should have affinity to the device it previously ran on")
    }

    // MARK: - Release Routing Record Tests

    func testReleaseRoutingRecordHasNilToDeviceId() async throws {
        let lease = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-release-record",
            requiredCapabilities: nil
        )

        try service.releaseLease(leaseId: lease.leaseId)

        let history = service.routingHistory(for: "conv-release-record")
        let releaseRecord = history.first(where: { $0.reason == .released })
        XCTAssertNotNil(releaseRecord)
        XCTAssertNil(releaseRecord?.toDeviceId, "Release record should have nil toDeviceId")
        XCTAssertEqual(releaseRecord?.fromDeviceId, lease.assignedDeviceId)
    }

    func testDeviceSelectionLastActivePolicyTiebreaker() async throws {
        mockDevicePolicy.currentPolicy = .lastActive

        let sameTime = Date()
        mockDevicePolicy.registeredDevices[0] = DeviceInfo(
            id: desktopId,
            name: "Mac Studio",
            deviceType: .desktop,
            platform: .macos,
            lastSeen: sameTime,
            isCurrentDevice: true,
            priority: 0
        )
        mockDevicePolicy.registeredDevices[1] = DeviceInfo(
            id: mobileId,
            name: "iPhone",
            deviceType: .mobile,
            platform: .ios,
            lastSeen: sameTime,
            isCurrentDevice: false,
            priority: 1
        )

        let lease = try await service.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-tie",
            requiredCapabilities: nil
        )

        // Same lastSeen — tiebreak by priority (desktop = 0 wins)
        XCTAssertEqual(lease.assignedDeviceId, desktopId)
    }
}

// MARK: - MockExecutionLeaseService Tests

@MainActor
final class MockExecutionLeaseServiceTests: XCTestCase {

    func testAcquireLease() async throws {
        let mock = MockExecutionLeaseService()
        let deviceId = UUID()
        mock.setNextDeviceId(deviceId)

        let lease = try await mock.acquireLease(
            workspaceId: UUID(),
            agentId: "agent",
            conversationId: "conv-1",
            requiredCapabilities: nil
        )

        XCTAssertEqual(mock.acquireCallCount, 1)
        XCTAssertEqual(lease.assignedDeviceId, deviceId)
        XCTAssertEqual(mock.lastAcquireConversationId, "conv-1")
    }

    func testRenewLease() async throws {
        let mock = MockExecutionLeaseService()

        let lease = try await mock.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-1",
            requiredCapabilities: nil
        )

        let renewed = try mock.renewLease(leaseId: lease.leaseId)
        XCTAssertEqual(mock.renewCallCount, 1)
        XCTAssertNotNil(renewed.renewedAt)
    }

    func testReleaseLease() async throws {
        let mock = MockExecutionLeaseService()

        let lease = try await mock.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-1",
            requiredCapabilities: nil
        )

        try mock.releaseLease(leaseId: lease.leaseId)
        XCTAssertEqual(mock.releaseCallCount, 1)
        XCTAssertNil(mock.activeLease(for: "conv-1"))
    }

    func testReassignLease() async throws {
        let mock = MockExecutionLeaseService()
        let deviceA = UUID()
        let deviceB = UUID()
        mock.setNextDeviceId(deviceA)

        let lease = try await mock.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-1",
            requiredCapabilities: nil
        )

        mock.setNextDeviceId(deviceB)
        let newLease = try mock.reassignLease(leaseId: lease.leaseId, reason: .reassignmentOffline)

        XCTAssertEqual(mock.reassignCallCount, 1)
        XCTAssertEqual(newLease.assignedDeviceId, deviceB)
        XCTAssertEqual(newLease.previousDeviceId, deviceA)
    }

    func testRoutingHistory() async throws {
        let mock = MockExecutionLeaseService()

        _ = try await mock.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-1",
            requiredCapabilities: nil
        )

        let history = mock.routingHistory(for: "conv-1")
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].reason, .initialAssignment)
    }

    func testActiveLeaseReturnsNilForExpiredLease() async throws {
        let mock = MockExecutionLeaseService()

        let lease = try await mock.acquireLease(
            workspaceId: UUID(),
            agentId: "a",
            conversationId: "conv-mock-expire",
            requiredCapabilities: nil
        )

        // Manually set lease to have past expiry (simulating time passing)
        var expiredLease = lease
        expiredLease.expiresAt = Date().addingTimeInterval(-10)
        mock.leases[lease.leaseId] = expiredLease

        // Mock should check isExpired just like the real service
        let active = mock.activeLease(for: "conv-mock-expire")
        XCTAssertNil(active, "Mock should return nil for expired leases (isExpired parity with real service)")
    }

    func testStubbedError() async {
        let mock = MockExecutionLeaseService()
        mock.stubbedError = ExecutionLeaseError.noDeviceAvailable

        do {
            _ = try await mock.acquireLease(
                workspaceId: UUID(),
                agentId: "a",
                conversationId: "conv-1",
                requiredCapabilities: nil
            )
            XCTFail("Expected error")
        } catch {
            // Expected
        }
    }
}
