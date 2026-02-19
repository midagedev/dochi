import Foundation

// MARK: - Bridge RPC Error Codes

/// Standard JSON-RPC 2.0 error codes plus Dochi-specific codes.
enum BridgeErrorCode: Int, Codable, Sendable {
    // JSON-RPC 2.0 standard
    case parseError = -32700
    case invalidRequest = -32600
    case methodNotFound = -32601
    case invalidParams = -32602
    case internalError = -32603

    // Dochi-specific (application error range: -32000 to -32099)
    case sessionNotFound = -32001
    case sessionAlreadyClosed = -32002
    case runtimeNotReady = -32003
    case sessionLimitExceeded = -32004
}

// MARK: - Session RPC Types

/// Parameters for `session.open`.
struct SessionOpenParams: Codable, Sendable {
    let workspaceId: String
    let agentId: String
    let conversationId: String
    let userId: String
    let deviceId: String?
    let sdkSessionId: String?
}

/// Result from `session.open`.
struct SessionOpenResult: Codable, Sendable {
    let sessionId: String
    let sdkSessionId: String
    let created: Bool
}

/// Parameters for `session.run`.
struct SessionRunParams: Codable, Sendable {
    let sessionId: String
    let input: String
    let contextSnapshotRef: String?
    let permissionMode: String?
}

/// Result from `session.run` (ack).
struct SessionRunResult: Codable, Sendable {
    let accepted: Bool
    let sessionId: String
}

/// Parameters for `session.interrupt`.
struct SessionInterruptParams: Codable, Sendable {
    let sessionId: String
}

/// Result from `session.interrupt`.
struct SessionInterruptResult: Codable, Sendable {
    let interrupted: Bool
    let sessionId: String
}

/// Parameters for `session.close`.
struct SessionCloseParams: Codable, Sendable {
    let sessionId: String
}

/// Result from `session.close`.
struct SessionCloseResult: Codable, Sendable {
    let closed: Bool
    let sessionId: String
}

/// A summary of a single session, returned by `session.list`.
struct SessionSummary: Codable, Sendable {
    let sessionId: String
    let sdkSessionId: String
    let workspaceId: String
    let agentId: String
    let conversationId: String
    let status: String
    let createdAt: String
}

/// Result from `session.list`.
struct SessionListResult: Codable, Sendable {
    let sessions: [SessionSummary]
}

// MARK: - Event Envelope

/// Common envelope for all runtime events (spec §5).
struct BridgeEvent: Codable, Sendable {
    let eventId: String
    let timestamp: String
    let sessionId: String?
    let workspaceId: String?
    let agentId: String?
    let eventType: BridgeEventType
    let payload: AnyCodableValue?
}

/// Known event types emitted by the runtime.
enum BridgeEventType: String, Codable, Sendable {
    case runtimeReady = "runtime.ready"
    case sessionStarted = "session.started"
    case sessionPartial = "session.partial"
    case sessionToolCall = "session.tool_call"
    case sessionToolResult = "session.tool_result"
    case sessionCompleted = "session.completed"
    case sessionFailed = "session.failed"
    case approvalRequired = "approval.required"
    case policyBlocked = "policy.blocked"
}

/// Ack sent back to runtime to confirm event receipt (for replay support).
struct EventAck: Codable, Sendable {
    let lastEventId: String
}
