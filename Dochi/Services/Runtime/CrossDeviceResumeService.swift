import Foundation
import os

/// Coordinates cross-device session resume.
///
/// When a conversation is opened from a different device, this service looks up the
/// existing session mapping (now keyed without `deviceId`) and reuses the SDK session
/// for seamless continuation. If no active session exists, it opens a new one via the
/// runtime bridge.
///
/// @MainActor rationale: Reads/writes SessionMappingService and RuntimeBridgeProtocol
/// state, both of which are MainActor-isolated. Keeping this service on MainActor
/// prevents data races without additional locking.
@MainActor
final class CrossDeviceResumeService: CrossDeviceResumeServiceProtocol {

    // MARK: - Dependencies

    private let sessionMappingService: SessionMappingService
    private let bridge: any RuntimeBridgeProtocol

    // MARK: - State

    private(set) var transferHistory: [DeviceTransferRecord] = []

    // MARK: - Init

    init(
        sessionMappingService: SessionMappingService,
        bridge: any RuntimeBridgeProtocol
    ) {
        self.sessionMappingService = sessionMappingService
        self.bridge = bridge
    }

    // MARK: - Resolve

    func resolveSession(
        workspaceId: String,
        agentId: String,
        conversationId: String,
        userId: String,
        deviceId: String
    ) async -> CrossDeviceResumeResult {
        // Guard: runtime must be ready
        guard bridge.runtimeState == .ready else {
            Log.runtime.error("Cross-device resume failed: runtime not ready (state=\(self.bridge.runtimeState.rawValue))")
            return .failed(reason: .runtimeNotReady)
        }

        // Step 1: Look up active session by conversation key (deviceId excluded)
        if let existing = sessionMappingService.findActive(
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId
        ) {
            // Security: Verify the requesting user owns this session.
            // If userId doesn't match, refuse to resume and create a new session instead
            // to prevent session hijacking via known conversationId.
            let userIdMismatch = !existing.userId.isEmpty && !userId.isEmpty && existing.userId != userId
            if userIdMismatch {
                Log.runtime.warning("Cross-device resume denied: userId mismatch (existing=\(existing.userId), requesting=\(userId)), creating new session")
                // Fall through to Step 2 to create a new session
            } else {
                // Determine if this is a cross-device resume or same-device resume
                let isCrossDevice = existing.deviceId != deviceId && !existing.deviceId.isEmpty && !deviceId.isEmpty
                let previousDeviceId: String? = isCrossDevice ? existing.deviceId : nil

                if isCrossDevice {
                    recordDeviceTransfer(
                        sessionId: existing.sessionId,
                        fromDeviceId: existing.deviceId,
                        toDeviceId: deviceId
                    )
                    Log.runtime.info("Cross-device resume: session=\(existing.sessionId), from=\(existing.deviceId), to=\(deviceId)")
                } else {
                    Log.runtime.info("Same-device resume: session=\(existing.sessionId)")
                }

                // Update the mapping: touch lastActiveAt and update deviceId for cross-device transfers.
                if isCrossDevice {
                    sessionMappingService.updateDeviceId(sessionId: existing.sessionId, newDeviceId: deviceId)
                } else {
                    sessionMappingService.touch(sessionId: existing.sessionId)
                }

                return .resumed(
                    sessionId: existing.sessionId,
                    sdkSessionId: existing.sdkSessionId,
                    previousDeviceId: previousDeviceId
                )
            }
        }

        // Step 2: No active session (or userId mismatch) — open a new one
        do {
            let result = try await bridge.openSession(params: SessionOpenParams(
                workspaceId: workspaceId,
                agentId: agentId,
                conversationId: conversationId,
                userId: userId,
                deviceId: deviceId,
                sdkSessionId: nil
            ))

            // Store the new mapping
            let mapping = SessionMapping(
                sessionId: result.sessionId,
                sdkSessionId: result.sdkSessionId,
                workspaceId: workspaceId,
                agentId: agentId,
                conversationId: conversationId,
                userId: userId,
                deviceId: deviceId,
                status: .active,
                createdAt: Date(),
                lastActiveAt: Date()
            )
            sessionMappingService.insert(mapping)

            Log.runtime.info("New session created: \(result.sessionId) for conversation=\(conversationId)")
            return .created(sessionId: result.sessionId, sdkSessionId: result.sdkSessionId)
        } catch {
            Log.runtime.error("Failed to open new session: \(error.localizedDescription)")
            return .failed(reason: .sessionOpenFailed)
        }
    }

    // MARK: - Device Transfer

    func recordDeviceTransfer(sessionId: String, fromDeviceId: String, toDeviceId: String) {
        let record = DeviceTransferRecord(
            sessionId: sessionId,
            fromDeviceId: fromDeviceId,
            toDeviceId: toDeviceId
        )
        transferHistory.append(record)
        Log.runtime.info("Device transfer recorded: session=\(sessionId), \(fromDeviceId) -> \(toDeviceId)")
    }
}
