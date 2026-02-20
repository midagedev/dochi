import Foundation
import os
import CryptoKit

/// Orchestrates pre-tool, post-tool, and session lifecycle hooks.
@MainActor
final class HookPipeline {
    private(set) var preHooks: [any PreToolUseHook] = []
    private(set) var postHooks: [any PostToolUseHook] = []
    private(set) var lifecycleHooks: [any SessionLifecycleHook] = []

    private let ruleset: HookRuleset

    init(ruleset: HookRuleset = .default) {
        self.ruleset = ruleset
        registerDefaultHooks()
    }

    private func registerDefaultHooks() {
        preHooks.append(ForbiddenPatternHook(patterns: ruleset.forbiddenPatterns))
        preHooks.append(PIIMaskingHook(patterns: ruleset.piiPatterns))
        postHooks.append(MetricsRecordingHook())
        postHooks.append(MemoryCandidateHook())
        lifecycleHooks.append(AuditFlushHook())
    }

    // MARK: - Registration

    func registerPreHook(_ hook: any PreToolUseHook) {
        preHooks.append(hook)
    }

    func registerPostHook(_ hook: any PostToolUseHook) {
        postHooks.append(hook)
    }

    func registerLifecycleHook(_ hook: any SessionLifecycleHook) {
        lifecycleHooks.append(hook)
    }

    // MARK: - Pre-Tool Hooks

    /// Run all pre-tool hooks in order. First blocking decision wins.
    func runPreHooks(context: ToolHookContext) -> PreHookResult {
        for hook in preHooks {
            let decision = hook.evaluate(context: context)
            switch decision {
            case .block:
                Log.runtime.info("PreToolUse hook '\(hook.name)' blocked \(context.toolName)")
                return PreHookResult(decision: decision, hookName: hook.name)
            case .mask:
                Log.runtime.info("PreToolUse hook '\(hook.name)' masked arguments for \(context.toolName)")
                return PreHookResult(decision: decision, hookName: hook.name)
            case .allow:
                continue
            }
        }
        return PreHookResult(decision: .allow, hookName: nil)
    }

    // MARK: - Post-Tool Hooks

    /// Run all post-tool hooks and aggregate outputs.
    func runPostHooks(context: ToolHookContext, result: ToolResult, latencyMs: Int) -> [PostHookOutput] {
        var outputs: [PostHookOutput] = []
        for hook in postHooks {
            if let output = hook.process(context: context, result: result, latencyMs: latencyMs) {
                outputs.append(output)
            }
        }
        return outputs
    }

    // MARK: - Session Lifecycle Hooks

    /// Run hooks on session close.
    func runSessionCloseHooks(sessionId: String, auditLog: [ToolAuditEvent]) {
        for hook in lifecycleHooks {
            hook.onSessionClose(sessionId: sessionId, auditLog: auditLog)
        }
    }

    /// Run hooks on app stop / runtime shutdown.
    func runStopHooks(auditLog: [ToolAuditEvent]) {
        for hook in lifecycleHooks {
            hook.onStop(auditLog: auditLog)
        }
    }

    // MARK: - Memory Pipeline Integration

    /// Attach a memory pipeline to the MemoryCandidateHook for structured processing.
    func attachMemoryPipeline(_ pipeline: any MemoryPipelineProtocol, workspaceId: String) {
        for hook in postHooks {
            if let memoryHook = hook as? MemoryCandidateHook {
                memoryHook.memoryPipeline = pipeline
                memoryHook.currentWorkspaceId = workspaceId
                Log.runtime.info("Memory pipeline attached to MemoryCandidateHook for workspace \(workspaceId)")
                return
            }
        }
        Log.runtime.warning("MemoryCandidateHook not found in post hooks — memory pipeline not attached")
    }

    // MARK: - Utility

    /// Compute SHA-256 hash of tool arguments for audit logging.
    static func argumentsHash(_ arguments: [String: AnyCodableValue]) -> String {
        guard !arguments.isEmpty else { return "" }
        let sortedKeys = arguments.keys.sorted()
        let parts = sortedKeys.map { key in
            "\(key)=\(arguments[key].map(String.init(describing:)) ?? "nil")"
        }
        let joined = parts.joined(separator: "&")
        let data = Data(joined.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ForbiddenPatternHook

/// PreToolUse hook that blocks tool execution when arguments match forbidden patterns.
@MainActor
final class ForbiddenPatternHook: PreToolUseHook {
    let name = "ForbiddenPattern"
    private let patterns: [ForbiddenPattern]

    init(patterns: [ForbiddenPattern]) {
        self.patterns = patterns
    }

    func evaluate(context: ToolHookContext) -> PreHookDecision {
        for pattern in patterns {
            // Check if this pattern applies to this tool
            if !pattern.tools.isEmpty && !pattern.tools.contains(context.toolName) {
                continue
            }

            // Check arguments for the forbidden pattern
            for (_, value) in context.arguments {
                let stringValue: String
                switch value {
                case .string(let s): stringValue = s
                default: continue
                }

                if stringValue.lowercased().contains(pattern.pattern.lowercased()) {
                    return .block(reason: pattern.reason)
                }
            }
        }
        return .allow
    }
}

// MARK: - PIIMaskingHook

/// PreToolUse hook that masks PII in tool arguments.
@MainActor
final class PIIMaskingHook: PreToolUseHook {
    let name = "PIIMasking"
    private let patterns: [PIIPattern]
    private let compiledPatterns: [(PIIPattern, NSRegularExpression)]

    init(patterns: [PIIPattern]) {
        self.patterns = patterns
        self.compiledPatterns = patterns.compactMap { p in
            guard let regex = try? NSRegularExpression(pattern: p.regex, options: []) else {
                return nil
            }
            return (p, regex)
        }
    }

    func evaluate(context: ToolHookContext) -> PreHookDecision {
        var masked = context.arguments
        var didMask = false

        for (key, value) in context.arguments {
            guard case .string(let s) = value else { continue }

            var result = s
            for (pattern, regex) in compiledPatterns {
                let range = NSRange(result.startIndex..., in: result)
                let newResult = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: range,
                    withTemplate: pattern.replacement
                )
                if newResult != result {
                    result = newResult
                    didMask = true
                }
            }

            if didMask {
                masked[key] = .string(result)
            }
        }

        return didMask ? .mask(maskedArguments: masked) : .allow
    }
}

// MARK: - MetricsRecordingHook

/// PostToolUse hook that logs execution metrics.
@MainActor
final class MetricsRecordingHook: PostToolUseHook {
    let name = "MetricsRecording"

    /// Aggregated tool execution counts per tool name for the session.
    private(set) var toolCallCounts: [String: Int] = [:]
    /// Aggregated latencies per tool name.
    private(set) var toolLatencies: [String: [Int]] = [:]

    func process(context: ToolHookContext, result: ToolResult, latencyMs: Int) -> PostHookOutput? {
        toolCallCounts[context.toolName, default: 0] += 1
        toolLatencies[context.toolName, default: []].append(latencyMs)

        Log.runtime.debug(
            "PostToolUse metrics: \(context.toolName) — \(latencyMs)ms, success=\(!result.isError), count=\(self.toolCallCounts[context.toolName] ?? 0)"
        )
        return nil
    }
}

// MARK: - MemoryCandidateHook

/// PostToolUse hook that extracts memory-worthy content from tool results.
///
/// When a `memoryPipeline` is attached, extracted candidates are forwarded
/// for classification and storage. Otherwise, candidates are only returned
/// in the `PostHookOutput` for upstream consumers.
@MainActor
final class MemoryCandidateHook: PostToolUseHook {
    let name = "MemoryCandidate"

    /// Optional pipeline for structured memory processing.
    var memoryPipeline: (any MemoryPipelineProtocol)?

    /// The workspace ID for the current session (set by runtime before use).
    var currentWorkspaceId: String?

    /// Tools whose results may contain memory-worthy information.
    private let memoryToolNames: Set<String> = [
        "calendar.today", "calendar.list", "reminders.list",
        "contacts.search", "web.search",
    ]

    func process(context: ToolHookContext, result: ToolResult, latencyMs: Int) -> PostHookOutput? {
        guard !result.isError,
              memoryToolNames.contains(context.toolName),
              result.content.count > 20 else {
            return nil
        }

        // Extract first meaningful line as summary
        let summary = String(result.content.prefix(200))
        let candidateContent = "\(context.toolName): \(summary)"

        // Forward to memory pipeline if available
        if let pipeline = memoryPipeline, let workspaceId = currentWorkspaceId {
            let candidate = MemoryCandidate(
                content: candidateContent,
                source: .toolResult,
                sessionId: context.sessionId,
                workspaceId: workspaceId,
                agentId: context.agentId
            )
            Task { @MainActor in
                await pipeline.submitCandidate(candidate)
            }
        }

        return PostHookOutput(
            resultSummary: summary,
            memoryCandidates: [candidateContent]
        )
    }
}

// MARK: - AuditFlushHook

/// Session lifecycle hook that flushes audit log entries via os.Logger.
@MainActor
final class AuditFlushHook: SessionLifecycleHook {
    let name = "AuditFlush"

    func onSessionClose(sessionId: String, auditLog: [ToolAuditEvent]) {
        let sessionEvents = auditLog.filter { $0.sessionId == sessionId }
        guard !sessionEvents.isEmpty else { return }

        let allowed = sessionEvents.filter { $0.decision == .allowed }.count
        let approved = sessionEvents.filter { $0.decision == .approved }.count
        let denied = sessionEvents.filter { $0.decision == .denied }.count
        let blocked = sessionEvents.filter {
            $0.decision == .policyBlocked || $0.decision == .hookBlocked
        }.count
        let avgLatency = sessionEvents.isEmpty ? 0 : sessionEvents.map(\.latencyMs).reduce(0, +) / sessionEvents.count

        Log.runtime.info(
            "Audit flush [session=\(sessionId)]: \(sessionEvents.count) events — allowed=\(allowed), approved=\(approved), denied=\(denied), blocked=\(blocked), avgLatency=\(avgLatency)ms"
        )
    }

    func onStop(auditLog: [ToolAuditEvent]) {
        guard !auditLog.isEmpty else { return }

        let sessions = Set(auditLog.map(\.sessionId))
        let totalTools = auditLog.count
        let errorCount = auditLog.filter { $0.resultCode != nil }.count

        Log.runtime.info(
            "Audit flush [stop]: \(totalTools) events across \(sessions.count) sessions, \(errorCount) errors"
        )
    }
}
