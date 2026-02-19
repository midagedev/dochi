import Foundation

// MARK: - SessionChannel

/// Input channel through which a session request originates.
enum SessionChannel: String, Codable, Sendable, CaseIterable {
    case voice
    case text
    case messenger
}

// MARK: - SessionResumeRequest

/// Request to resume an existing session or start a new one.
///
/// The session is identified by the combination of `workspaceId`, `agentId`,
/// and `conversationId`. The `requestingDeviceId` indicates which device is
/// requesting the resume, enabling cross-device handoff.
struct SessionResumeRequest: Codable, Sendable, Equatable {
    /// Input channel that initiated this resume request.
    let sourceChannel: SessionChannel
    /// Workspace owning the session.
    let workspaceId: UUID
    /// Agent handling the session.
    let agentId: String
    /// Conversation to resume.
    let conversationId: String
    /// User requesting the resume.
    let userId: String
    /// Device requesting the resume.
    let requestingDeviceId: UUID
    /// Previous session ID if known (used as hint for faster lookup).
    let previousSessionId: String?

    init(
        sourceChannel: SessionChannel,
        workspaceId: UUID,
        agentId: String,
        conversationId: String,
        userId: String,
        requestingDeviceId: UUID,
        previousSessionId: String? = nil
    ) {
        self.sourceChannel = sourceChannel
        self.workspaceId = workspaceId
        self.agentId = agentId
        self.conversationId = conversationId
        self.userId = userId
        self.requestingDeviceId = requestingDeviceId
        self.previousSessionId = previousSessionId
    }
}
