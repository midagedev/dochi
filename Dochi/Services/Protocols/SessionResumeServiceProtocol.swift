import Foundation

/// @MainActor required: resume operations read/write shared session state
/// (SessionMappingService, ExecutionLeaseService) which are MainActor-isolated.
/// Isolating here prevents data races without additional locking.
@MainActor
protocol SessionResumeServiceProtocol {
    /// Attempt to resume an existing session or create a new one.
    ///
    /// The resume logic follows this priority:
    /// 1. Find active session on the same device -> return it
    /// 2. Find active session on another device -> reassign lease
    /// 3. Find closed session -> create new session reusing context
    /// 4. No session found -> create new session with failure reason
    func resumeSession(_ request: SessionResumeRequest) async throws -> SessionResumeResult

    /// Check whether a session for the given conversation can potentially be resumed.
    ///
    /// Returns `true` if there is at least one mapping (active or closed) for
    /// the conversation. This is a lightweight pre-check — the actual resume
    /// may still fail if, for example, lease reassignment is not possible.
    func canResume(conversationId: String) -> Bool

    /// Build the device-independent session key used for cross-device lookup.
    ///
    /// The key is composed of `workspaceId + agentId + conversationId`,
    /// deliberately excluding `deviceId` so the same conversation produces
    /// the same key regardless of which device initiates the resume.
    func normalizeSessionKey(workspaceId: UUID, agentId: String, conversationId: String) -> String
}
