import Foundation

// MARK: - Hook Context

/// Context passed to all tool hooks for decision making.
struct ToolHookContext: Sendable {
    let toolCallId: String
    let sessionId: String
    let agentId: String?
    let toolName: String
    let arguments: [String: AnyCodableValue]
    let riskLevel: String
}

// MARK: - Hook Decisions

/// Decision from a PreToolUse hook.
enum PreHookDecision: Sendable {
    /// Allow the tool to proceed.
    case allow
    /// Block the tool with a reason.
    case block(reason: String)
    /// Allow but with masked arguments (PII redaction).
    case mask(maskedArguments: [String: AnyCodableValue])
}

/// Result from running all pre-hooks.
struct PreHookResult: Sendable {
    let decision: PreHookDecision
    /// Which hook produced the decision (for audit).
    let hookName: String?
}

/// Data extracted by PostToolUse hooks.
struct PostHookOutput: Sendable {
    /// Short summary of the tool result.
    let resultSummary: String?
    /// Memory candidates extracted from the result.
    let memoryCandidates: [String]
}

// MARK: - Hook Protocols

/// Evaluates tool arguments before execution.
/// Runs synchronously — must be fast (no I/O).
@MainActor
protocol PreToolUseHook {
    var name: String { get }
    func evaluate(context: ToolHookContext) -> PreHookDecision
}

/// Processes tool results after execution.
@MainActor
protocol PostToolUseHook {
    var name: String { get }
    func process(context: ToolHookContext, result: ToolResult, latencyMs: Int) -> PostHookOutput?
}

/// Handles session lifecycle events (close, stop).
@MainActor
protocol SessionLifecycleHook {
    var name: String { get }
    func onSessionClose(sessionId: String, auditLog: [ToolAuditEvent])
    func onStop(auditLog: [ToolAuditEvent])
}
