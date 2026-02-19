import Foundation

/// Maps a Dochi session key to its SDK session ID for resume support.
///
/// The composite key (`workspaceId` + `agentId` + `conversationId` + `deviceId`)
/// uniquely identifies a logical session. When the same key is used to open a session,
/// the existing SDK session is reused instead of creating a new one.
struct SessionMapping: Codable, Sendable, Equatable {
    /// Dochi-side session identifier.
    let sessionId: String
    /// Claude Agent SDK session identifier (for resume).
    let sdkSessionId: String
    /// Workspace that owns this session.
    let workspaceId: String
    /// Agent handling this session.
    let agentId: String
    /// Conversation this session belongs to.
    let conversationId: String
    /// User who initiated this session.
    let userId: String
    /// Device where the session was created. Empty string if not specified.
    let deviceId: String
    /// Session status.
    var status: SessionMappingStatus
    /// ISO 8601 creation timestamp.
    let createdAt: Date
    /// ISO 8601 last activity timestamp.
    var lastActiveAt: Date

    /// The composite lookup key.
    var lookupKey: SessionLookupKey {
        SessionLookupKey(
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            deviceId: deviceId
        )
    }
}

/// Status of a session mapping entry.
enum SessionMappingStatus: String, Codable, Sendable {
    case active
    case closed
    case interrupted
}

/// Composite key for session lookup.
struct SessionLookupKey: Hashable, Sendable {
    let workspaceId: String
    let agentId: String
    let conversationId: String
    let deviceId: String
}

/// Persistent container for all session mappings.
struct SessionMappingStore: Codable, Sendable {
    var mappings: [SessionMapping]
    var version: Int

    init(mappings: [SessionMapping] = [], version: Int = 1) {
        self.mappings = mappings
        self.version = version
    }
}
