import Foundation

/// Maps a Dochi session key to its SDK session ID for resume support.
///
/// The composite key (`workspaceId` + `agentId` + `conversationId`) uniquely
/// identifies a logical session. `deviceId` is stored for audit/debugging but
/// intentionally excluded from the lookup key so that the same conversation
/// can be resumed from a different device (cross-device resume).
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
    /// Device where the session was last active. Stored for audit only; not part of lookup key.
    /// Mutable: updated on cross-device resume so the mapping reflects the current device.
    var deviceId: String
    /// Session status.
    var status: SessionMappingStatus
    /// ISO 8601 creation timestamp.
    let createdAt: Date
    /// ISO 8601 last activity timestamp.
    var lastActiveAt: Date

    /// The composite lookup key (deviceId excluded for cross-device resume).
    var lookupKey: SessionLookupKey {
        SessionLookupKey(
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId
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
///
/// `deviceId` is intentionally excluded so that the same conversation can be
/// resumed across different devices (cross-device resume, Issue #291).
struct SessionLookupKey: Hashable, Sendable {
    let workspaceId: String
    let agentId: String
    let conversationId: String
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
