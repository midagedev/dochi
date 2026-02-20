import Foundation

/// Cross-device session resume service.
///
/// Coordinates session lookup, lease management, and channel mapping to allow
/// a session started on one device/channel to be seamlessly continued on
/// another. Session identity is based on the normalized key
/// (`workspaceId + agentId + conversationId`), which is device-independent.
///
/// Resume flow:
/// 1. Normalize the session key (device-independent).
/// 2. Search for an active session mapping for the conversation.
/// 3. If found on the same device -> return existing session (`.resumed`).
/// 4. If found on a different device -> reassign lease, then return (`.resumed`).
/// 5. If closed/interrupted -> create new session with context reuse (`.newSession`).
/// 6. If not found at all -> create new session (`.newSession` with `.sessionNotFound`).
///
/// @MainActor required: accesses SessionMappingService and ExecutionLeaseService
/// which are MainActor-isolated.
@MainActor
final class SessionResumeService: SessionResumeServiceProtocol {

    // MARK: - Dependencies

    private let sessionMappingService: any SessionMappingServiceProtocol
    private let leaseService: any ExecutionLeaseServiceProtocol
    private let channelMapper: ChannelSessionMapper

    // MARK: - Init

    init(
        sessionMappingService: any SessionMappingServiceProtocol,
        leaseService: any ExecutionLeaseServiceProtocol,
        channelMapper: ChannelSessionMapper
    ) {
        self.sessionMappingService = sessionMappingService
        self.leaseService = leaseService
        self.channelMapper = channelMapper
    }

    // MARK: - SessionResumeServiceProtocol

    func resumeSession(_ request: SessionResumeRequest) async throws -> SessionResumeResult {
        Log.app.info("SessionResume: attempting resume — conversation=\(request.conversationId), channel=\(request.sourceChannel.rawValue), device=\(request.requestingDeviceId)")

        // Resolve the conversationId through the channel mapper for messenger channels.
        // For voice/text, this returns the input as-is; for messenger, it translates the
        // external chat ID (e.g. Telegram chatId) to the internal conversationId.
        let resolvedRequest: SessionResumeRequest
        if request.sourceChannel == .messenger {
            guard let mapped = channelMapper.resolveConversationId(
                channel: .messenger,
                identifier: request.conversationId
            ) else {
                Log.app.info("SessionResume: no channel mapping for messenger identifier=\(request.conversationId), creating new session")
                return await createNewSession(request: request, reason: .sessionNotFound)
            }
            resolvedRequest = SessionResumeRequest(
                sourceChannel: request.sourceChannel,
                workspaceId: request.workspaceId,
                agentId: request.agentId,
                conversationId: mapped,
                userId: request.userId,
                requestingDeviceId: request.requestingDeviceId,
                previousSessionId: request.previousSessionId
            )
            Log.app.debug("SessionResume: messenger identifier=\(request.conversationId) resolved to conversationId=\(mapped)")
        } else {
            resolvedRequest = request
        }

        let sessionKey = normalizeSessionKey(
            workspaceId: resolvedRequest.workspaceId,
            agentId: resolvedRequest.agentId,
            conversationId: resolvedRequest.conversationId
        )

        // Step 1: Search for an active session mapping across all devices.
        let activeMapping = findActiveMapping(
            workspaceId: resolvedRequest.workspaceId,
            agentId: resolvedRequest.agentId,
            conversationId: resolvedRequest.conversationId
        )

        if let mapping = activeMapping {
            // Security: Verify the requesting user owns this session (hijack prevention).
            let userIdMismatch = !mapping.userId.isEmpty && !resolvedRequest.userId.isEmpty && mapping.userId != resolvedRequest.userId
            if userIdMismatch {
                Log.app.warning("SessionResume: userId mismatch (existing=\(mapping.userId), requesting=\(resolvedRequest.userId)), creating new session to prevent hijack")
                return await createNewSession(request: resolvedRequest, reason: .sessionNotFound)
            }
            return try await handleActiveMapping(mapping, request: resolvedRequest, sessionKey: sessionKey)
        }

        // Step 2: Check for any mapping (closed/interrupted) to build metadata.
        let anyMapping = findAnyMapping(conversationId: resolvedRequest.conversationId)

        if let mapping = anyMapping {
            return await handleClosedMapping(mapping, request: resolvedRequest, sessionKey: sessionKey)
        }

        // Step 3: No session found at all.
        Log.app.info("SessionResume: no session found for key=\(sessionKey), creating new session")
        return await createNewSession(request: resolvedRequest, reason: .sessionNotFound)
    }

    func canResume(conversationId: String) -> Bool {
        let mappings = sessionMappingService.allMappings
        return mappings.contains { $0.conversationId == conversationId }
    }

    func normalizeSessionKey(workspaceId: UUID, agentId: String, conversationId: String) -> String {
        "\(workspaceId.uuidString):\(agentId):\(conversationId)"
    }

    // MARK: - Private: Handle Active Mapping

    /// An active mapping exists. Decide whether to return as-is or reassign the lease.
    private func handleActiveMapping(
        _ mapping: SessionMapping,
        request: SessionResumeRequest,
        sessionKey: String
    ) async throws -> SessionResumeResult {
        let mappingDeviceId = UUID(uuidString: mapping.deviceId)

        // Case A: Active session on the same device.
        if mappingDeviceId == request.requestingDeviceId {
            Log.app.info("SessionResume: resumed on same device — session=\(mapping.sessionId)")
            sessionMappingService.touch(sessionId: mapping.sessionId)

            let metadata = ResumeMetadata(
                previousDeviceId: mappingDeviceId,
                previousChannel: nil,
                lastActivityAt: mapping.lastActiveAt
            )
            return .resumed(sessionId: mapping.sessionId, deviceId: request.requestingDeviceId, metadata: metadata)
        }

        // Case B: Active session on a different device — try lease reassignment.
        Log.app.info("SessionResume: active session on different device (\(mapping.deviceId)), attempting lease reassignment")

        if let activeLease = leaseService.activeLease(for: request.conversationId) {
            do {
                let newLease = try leaseService.reassignLease(
                    leaseId: activeLease.leaseId,
                    reason: .reassignmentManual
                )

                // Update the session mapping to reflect the new device.
                sessionMappingService.updateStatus(sessionId: mapping.sessionId, status: .closed)

                let newMapping = SessionMapping(
                    sessionId: UUID().uuidString,
                    sdkSessionId: mapping.sdkSessionId,
                    workspaceId: mapping.workspaceId,
                    agentId: mapping.agentId,
                    conversationId: mapping.conversationId,
                    userId: mapping.userId,
                    deviceId: request.requestingDeviceId.uuidString,
                    status: .active,
                    createdAt: Date(),
                    lastActiveAt: Date()
                )
                sessionMappingService.insert(newMapping)

                let metadata = ResumeMetadata(
                    previousDeviceId: mappingDeviceId,
                    previousChannel: nil,
                    lastActivityAt: mapping.lastActiveAt
                )

                Log.app.info("SessionResume: lease reassigned — old device=\(mapping.deviceId), new device=\(request.requestingDeviceId), new lease=\(newLease.leaseId)")
                return .resumed(sessionId: newMapping.sessionId, deviceId: request.requestingDeviceId, metadata: metadata)
            } catch {
                Log.app.warning("SessionResume: lease reassignment failed — \(error.localizedDescription)")
                return await createNewSession(request: request, reason: .leaseReassignmentFailed)
            }
        }

        // No active lease found for the conversation despite active mapping — treat as new.
        Log.app.warning("SessionResume: active mapping but no active lease for conversation=\(request.conversationId)")
        sessionMappingService.updateStatus(sessionId: mapping.sessionId, status: .interrupted)
        return await createNewSession(request: request, reason: .sessionClosed)
    }

    // MARK: - Private: Handle Closed Mapping

    /// A closed/interrupted mapping exists. Create a new session, reusing context info from the old mapping.
    private func handleClosedMapping(
        _ mapping: SessionMapping,
        request: SessionResumeRequest,
        sessionKey: String
    ) async -> SessionResumeResult {
        Log.app.info("SessionResume: found closed session (\(mapping.status.rawValue)) for key=\(sessionKey), creating new session with context reuse")

        let previousDeviceId = UUID(uuidString: mapping.deviceId)
        return await createNewSession(
            request: request,
            reason: .sessionClosed,
            previousDeviceId: previousDeviceId,
            lastActivityAt: mapping.lastActiveAt
        )
    }

    // MARK: - Private: Create New Session

    /// Create a new session and lease, returning a `.newSession` result.
    private func createNewSession(
        request: SessionResumeRequest,
        reason: ResumeFailureReason,
        previousDeviceId: UUID? = nil,
        lastActivityAt: Date? = nil
    ) async -> SessionResumeResult {
        do {
            let lease = try await leaseService.acquireLease(
                workspaceId: request.workspaceId,
                agentId: request.agentId,
                conversationId: request.conversationId,
                requiredCapabilities: nil
            )

            let newSessionId = UUID().uuidString
            let newMapping = SessionMapping(
                sessionId: newSessionId,
                sdkSessionId: "sdk-\(newSessionId)",
                workspaceId: request.workspaceId.uuidString,
                agentId: request.agentId,
                conversationId: request.conversationId,
                userId: request.userId,
                deviceId: request.requestingDeviceId.uuidString,
                status: .active,
                createdAt: Date(),
                lastActiveAt: Date()
            )
            sessionMappingService.insert(newMapping)

            Log.app.info("SessionResume: new session created — session=\(newSessionId), reason=\(reason.rawValue), lease=\(lease.leaseId)")
            return .newSession(sessionId: newSessionId, deviceId: lease.assignedDeviceId, reason: reason)
        } catch {
            Log.app.error("SessionResume: failed to create new session — \(error.localizedDescription)")
            return .failed(error: .leaseAcquisitionFailed(error.localizedDescription))
        }
    }

    // MARK: - Private: Lookup Helpers

    /// Find an active session mapping for the given conversation across all devices.
    private func findActiveMapping(
        workspaceId: UUID,
        agentId: String,
        conversationId: String
    ) -> SessionMapping? {
        sessionMappingService.activeMappings.first { mapping in
            mapping.workspaceId == workspaceId.uuidString
            && mapping.agentId == agentId
            && mapping.conversationId == conversationId
        }
    }

    /// Find any mapping (active, closed, or interrupted) for the given conversation.
    /// Returns the most recently active one.
    private func findAnyMapping(conversationId: String) -> SessionMapping? {
        sessionMappingService.allMappings
            .filter { $0.conversationId == conversationId }
            .sorted { $0.lastActiveAt > $1.lastActiveAt }
            .first
    }
}
