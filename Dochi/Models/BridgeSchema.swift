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
    case toolNotFound = -32010
    case toolExecutionFailed = -32011
    case toolTimeout = -32012
    case toolPermissionDenied = -32013
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

// MARK: - Tool Dispatch RPC Types

/// Parameters for `tool.dispatch` (runtime → app notification).
struct ToolDispatchParams: Codable, Sendable {
    let toolCallId: String
    let toolName: String
    let arguments: [String: AnyCodableValue]
    let sessionId: String
    let riskLevel: String  // "safe", "sensitive", "restricted"
}

/// Parameters for `tool.result` (app → runtime RPC).
struct ToolResultParams: Codable, Sendable {
    let toolCallId: String
    let sessionId: String
    let success: Bool
    let content: String
    let errorCode: Int?
}

/// Result from `tool.result` ack.
struct ToolResultAck: Codable, Sendable {
    let received: Bool
    let toolCallId: String
}

/// Timeout budget per tool category (seconds).
enum ToolTimeoutPolicy {
    static let safe: TimeInterval = 30
    static let sensitive: TimeInterval = 60
    static let restricted: TimeInterval = 120
}

// MARK: - Approval RPC Types

/// Parameters for `approval.request` (runtime → app notification).
struct ApprovalRequestParams: Codable, Sendable {
    let approvalId: String
    let toolCallId: String
    let sessionId: String
    let toolName: String
    let riskLevel: String     // "sensitive", "restricted"
    let reason: String        // Why the tool is being called
    let argumentsSummary: String  // Human-readable arguments summary
}

/// Parameters for `approval.resolve` (app → runtime RPC).
struct ApprovalResolveParams: Codable, Sendable {
    let approvalId: String
    let toolCallId: String
    let sessionId: String
    let approved: Bool
    let scope: ApprovalScope
    let note: String?
}

/// Scope of an approval decision.
enum ApprovalScope: String, Codable, Sendable {
    case once = "once"
    case session = "session"
}

/// Result from `approval.resolve` ack.
struct ApprovalResolveAck: Codable, Sendable {
    let received: Bool
    let approvalId: String
}

/// Audit event for tool execution decisions.
struct ToolAuditEvent: Sendable {
    let toolCallId: String
    let sessionId: String
    let agentId: String?
    let toolName: String
    let riskLevel: String
    let decision: ToolAuditDecision
    let latencyMs: Int
    let resultCode: Int?
    let timestamp: Date
}

/// Decision recorded in audit log.
enum ToolAuditDecision: String, Sendable {
    case allowed       // safe tool, auto-approved
    case approved      // user approved sensitive/restricted tool
    case denied        // user denied
    case timeout       // approval timed out
    case policyBlocked // policy rejected
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
    case toolDispatch = "tool.dispatch"
    case approvalRequired = "approval.required"
    case policyBlocked = "policy.blocked"
}

/// Ack sent back to runtime to confirm event receipt (for replay support).
struct EventAck: Codable, Sendable {
    let lastEventId: String
}
