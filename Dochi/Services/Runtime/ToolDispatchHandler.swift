import Foundation
import os

/// Callback to request user approval for a sensitive/restricted tool.
/// Returns (approved, scope) where scope is "once" or "session".
typealias ToolApprovalHandler = @MainActor (ApprovalRequestParams) async -> (approved: Bool, scope: ApprovalScope)

/// Handles `tool.dispatch` and `approval.required` notifications from the runtime
/// by executing local tools and sending results/decisions back.
@available(*, deprecated, message: "Legacy SDK sidecar dispatch path. Native loop uses in-process tool dispatch.")
@MainActor
final class ToolDispatchHandler {

    private let toolService: any BuiltInToolServiceProtocol
    private weak var connection: RuntimeUDSConnection?
    private var requestIdCounter: Int = 10_000

    /// Callback for requesting user approval (wired to UI confirmation banner).
    var approvalHandler: ToolApprovalHandler?

    /// Session-scoped approvals: sessionId → Set of approved tool names.
    private var sessionApprovals: [String: Set<String>] = [:]

    /// Audit log entries for the current session.
    private(set) var auditLog: [ToolAuditEvent] = []

    /// Hook pipeline for pre/post tool hooks and session lifecycle.
    let hookPipeline: HookPipeline

    init(toolService: any BuiltInToolServiceProtocol, hookPipeline: HookPipeline = HookPipeline()) {
        self.toolService = toolService
        self.hookPipeline = hookPipeline
    }

    /// Attach the UDS connection for sending RPCs.
    func setConnection(_ connection: RuntimeUDSConnection) {
        self.connection = connection
    }

    /// Clear session-scoped approvals and run session close hooks.
    func clearSessionApprovals(sessionId: String) {
        sessionApprovals.removeValue(forKey: sessionId)
        hookPipeline.runSessionCloseHooks(sessionId: sessionId, auditLog: auditLog)
    }

    /// Run stop hooks and flush audit log.
    func runStopHooks() {
        hookPipeline.runStopHooks(auditLog: auditLog)
    }

    // MARK: - Payload Decoding

    /// Decode a `Codable` type from a `BridgeEvent`'s payload, injecting `sessionId`
    /// from the event envelope when missing in the payload object.
    static func decodePayload<T: Decodable>(event: BridgeEvent) -> T? {
        guard let payload = event.payload,
              case .object(var dict) = payload else {
            return nil
        }

        // Inject sessionId from event envelope if not present in the payload
        if dict["sessionId"] == nil, let sessionId = event.sessionId {
            dict["sessionId"] = .string(sessionId)
        }

        do {
            let data = try JSONEncoder().encode(AnyCodableValue.object(dict))
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Log.runtime.warning("Failed to decode payload as \(T.self): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Tool Dispatch

    /// Handle a `tool.dispatch` bridge event.
    /// Runs PreToolUse hooks, checks permission, executes the tool, runs PostToolUse hooks,
    /// and sends back `tool.result`.
    func handleDispatch(event: BridgeEvent) {
        guard let params: ToolDispatchParams = Self.decodePayload(event: event) else {
            Log.runtime.warning("Invalid tool.dispatch payload")
            return
        }

        let toolCallId = params.toolCallId
        let toolName = params.toolName
        let sessionId = params.sessionId
        let codableArguments = params.arguments
        let riskLevel = params.riskLevel

        let timeout = Self.timeout(for: riskLevel)
        let argsHash = HookPipeline.argumentsHash(codableArguments)

        Log.runtime.info("Tool dispatch: \(toolName) (\(toolCallId)), risk=\(riskLevel), timeout=\(timeout)s")

        Task { @MainActor in
            let startTime = Date()

            // Build hook context
            let hookContext = ToolHookContext(
                toolCallId: toolCallId,
                sessionId: sessionId,
                agentId: event.agentId,
                toolName: toolName,
                arguments: codableArguments,
                riskLevel: riskLevel
            )

            // Run PreToolUse hooks (forbidden pattern check, PII masking)
            let preResult = hookPipeline.runPreHooks(context: hookContext)

            // Determine effective arguments after hooks
            let effectiveArguments: [String: Any]
            switch preResult.decision {
            case .block(let reason):
                let blockedResult = ToolResult(
                    toolCallId: toolCallId,
                    content: "도구 '\(toolName)' 실행이 정책에 의해 차단되었습니다: \(reason)",
                    isError: true
                )
                await sendToolResult(toolCallId: toolCallId, sessionId: sessionId, result: blockedResult, errorCode: BridgeErrorCode.toolPermissionDenied.rawValue)
                recordAudit(toolCallId: toolCallId, sessionId: sessionId, agentId: event.agentId, toolName: toolName, argumentsHash: argsHash, riskLevel: riskLevel, decision: .hookBlocked, hookName: preResult.hookName, startTime: startTime, resultCode: BridgeErrorCode.toolPermissionDenied.rawValue)
                return

            case .mask(let maskedArgs):
                effectiveArguments = maskedArgs.toNativeDict()

            case .allow:
                effectiveArguments = codableArguments.toNativeDict()
            }

            // Permission check for sensitive/restricted tools
            if riskLevel != "safe" {
                let approved = await checkPermission(
                    toolCallId: toolCallId,
                    sessionId: sessionId,
                    toolName: toolName,
                    riskLevel: riskLevel,
                    arguments: effectiveArguments
                )

                if !approved {
                    let deniedResult = ToolResult(
                        toolCallId: toolCallId,
                        content: "도구 '\(toolName)' 실행이 사용자에 의해 거부되었습니다.",
                        isError: true
                    )
                    await sendToolResult(toolCallId: toolCallId, sessionId: sessionId, result: deniedResult, errorCode: BridgeErrorCode.toolPermissionDenied.rawValue)
                    recordAudit(toolCallId: toolCallId, sessionId: sessionId, agentId: event.agentId, toolName: toolName, argumentsHash: argsHash, riskLevel: riskLevel, decision: .denied, hookName: nil, startTime: startTime, resultCode: BridgeErrorCode.toolPermissionDenied.rawValue)
                    return
                }
            }

            // Execute tool
            let result = await executeWithTimeout(
                toolName: toolName,
                toolCallId: toolCallId,
                arguments: effectiveArguments,
                timeout: timeout
            )

            await sendToolResult(toolCallId: toolCallId, sessionId: sessionId, result: result)

            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

            // Run PostToolUse hooks (metrics, memory candidates)
            let _ = hookPipeline.runPostHooks(context: hookContext, result: result, latencyMs: latencyMs)

            let decision: ToolAuditDecision = riskLevel == "safe" ? .allowed : .approved
            recordAudit(toolCallId: toolCallId, sessionId: sessionId, agentId: event.agentId, toolName: toolName, argumentsHash: argsHash, riskLevel: riskLevel, decision: result.isError ? .policyBlocked : decision, hookName: nil, startTime: startTime, resultCode: result.isError ? BridgeErrorCode.toolExecutionFailed.rawValue : nil)

            Log.runtime.info("Tool result sent: \(toolName) (\(toolCallId)), success=\(!result.isError)")
        }
    }

    // MARK: - Approval Request (from runtime)

    /// Handle an `approval.required` bridge event from the runtime.
    /// Shows approval UI and sends `approval.resolve` RPC back.
    func handleApprovalRequest(event: BridgeEvent) {
        guard let params: ApprovalRequestParams = Self.decodePayload(event: event) else {
            Log.runtime.warning("Invalid approval.required payload")
            return
        }

        let approvalId = params.approvalId
        let toolCallId = params.toolCallId
        let sessionId = params.sessionId
        let toolName = params.toolName
        let riskLevel = params.riskLevel

        Task { @MainActor in
            let startTime = Date()

            guard let handler = approvalHandler else {
                Log.runtime.warning("No approval handler — auto-denying \(toolName)")
                await sendApprovalResolve(approvalId: approvalId, toolCallId: toolCallId, sessionId: sessionId, approved: false, scope: .once, note: "No approval handler available")
                recordAudit(toolCallId: toolCallId, sessionId: sessionId, agentId: event.agentId, toolName: toolName, argumentsHash: "", riskLevel: riskLevel, decision: .denied, hookName: nil, startTime: startTime, resultCode: nil)
                return
            }

            // Check session-scoped approval
            if let approved = sessionApprovals[sessionId], approved.contains(toolName) {
                Log.runtime.info("Session-scoped approval for \(toolName)")
                await sendApprovalResolve(approvalId: approvalId, toolCallId: toolCallId, sessionId: sessionId, approved: true, scope: .session, note: nil)
                recordAudit(toolCallId: toolCallId, sessionId: sessionId, agentId: event.agentId, toolName: toolName, argumentsHash: "", riskLevel: riskLevel, decision: .approved, hookName: nil, startTime: startTime, resultCode: nil)
                return
            }

            let (approved, scope) = await handler(params)

            if approved && scope == .session {
                if sessionApprovals[sessionId] == nil {
                    sessionApprovals[sessionId] = []
                }
                sessionApprovals[sessionId]?.insert(toolName)
                Log.runtime.info("Session-scoped approval granted for \(toolName)")
            }

            await sendApprovalResolve(approvalId: approvalId, toolCallId: toolCallId, sessionId: sessionId, approved: approved, scope: scope, note: nil)

            let decision: ToolAuditDecision = approved ? .approved : .denied
            recordAudit(toolCallId: toolCallId, sessionId: sessionId, agentId: event.agentId, toolName: toolName, argumentsHash: "", riskLevel: riskLevel, decision: decision, hookName: nil, startTime: startTime, resultCode: nil)

            Log.runtime.info("Approval resolved: \(toolName) → \(approved ? "approved" : "denied") (scope=\(scope.rawValue))")
        }
    }

    // MARK: - Private

    /// Check if a sensitive/restricted tool is allowed.
    /// Uses the existing BuiltInToolService confirmation flow.
    private func checkPermission(
        toolCallId: String,
        sessionId: String,
        toolName: String,
        riskLevel: String,
        arguments: [String: Any]
    ) async -> Bool {
        // Check session-scoped approval
        if let approved = sessionApprovals[sessionId], approved.contains(toolName) {
            Log.runtime.info("Session-scoped approval for \(toolName)")
            return true
        }

        // Request user approval via the approval handler
        guard let handler = approvalHandler else {
            Log.runtime.warning("No approval handler — denying \(toolName)")
            return false
        }

        let argsSummary = arguments.keys.sorted().joined(separator: ", ")
        let params = ApprovalRequestParams(
            approvalId: UUID().uuidString,
            toolCallId: toolCallId,
            sessionId: sessionId,
            toolName: toolName,
            riskLevel: riskLevel,
            reason: "도구 실행 승인이 필요합니다",
            argumentsSummary: argsSummary.isEmpty ? "(인자 없음)" : argsSummary
        )

        let (approved, scope) = await handler(params)

        if approved && scope == .session {
            if sessionApprovals[sessionId] == nil {
                sessionApprovals[sessionId] = []
            }
            sessionApprovals[sessionId]?.insert(toolName)
        }

        return approved
    }

    /// Execute a tool with a timeout by racing execution and timeout tasks.
    /// The first published result wins, then both tasks are canceled.
    func executeWithTimeout(
        toolName: String,
        toolCallId: String,
        arguments: [String: Any],
        timeout: TimeInterval
    ) async -> ToolResult {
        let raceResultBox = ToolExecutionRaceResultBox()

        let executionTask = Task { @MainActor in
            let result = await self.toolService.execute(name: toolName, arguments: arguments)
            await raceResultBox.publish(result)
        }

        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(timeout))
            let timeoutResult = ToolResult(
                toolCallId: toolCallId,
                content: "Tool '\(toolName)' timed out after \(Int(timeout))s",
                isError: true
            )
            await raceResultBox.publish(timeoutResult)
        }

        let firstResult = await raceResultBox.waitForFirstResult()
        executionTask.cancel()
        timeoutTask.cancel()
        return firstResult
    }

    private func sendToolResult(
        toolCallId: String,
        sessionId: String,
        result: ToolResult,
        errorCode: Int? = nil
    ) async {
        guard let connection else {
            Log.runtime.warning("Cannot send tool.result: no UDS connection")
            return
        }

        requestIdCounter += 1

        var params: [String: AnyCodableValue] = [
            "toolCallId": .string(toolCallId),
            "sessionId": .string(sessionId),
            "success": .bool(!result.isError),
            "content": .string(result.content),
        ]
        if let code = errorCode ?? (result.isError ? BridgeErrorCode.toolExecutionFailed.rawValue : nil) {
            params["errorCode"] = .int(code)
        }

        let request = JsonRpcRequest(
            id: requestIdCounter,
            method: "tool.result",
            params: params
        )

        do {
            _ = try await connection.send(request)
        } catch {
            Log.runtime.error("Failed to send tool.result: \(error.localizedDescription)")
        }
    }

    private func sendApprovalResolve(
        approvalId: String,
        toolCallId: String,
        sessionId: String,
        approved: Bool,
        scope: ApprovalScope,
        note: String?
    ) async {
        guard let connection else {
            Log.runtime.warning("Cannot send approval.resolve: no UDS connection")
            return
        }

        requestIdCounter += 1

        var params: [String: AnyCodableValue] = [
            "approvalId": .string(approvalId),
            "toolCallId": .string(toolCallId),
            "sessionId": .string(sessionId),
            "approved": .bool(approved),
            "scope": .string(scope.rawValue),
        ]
        if let note {
            params["note"] = .string(note)
        }

        let request = JsonRpcRequest(
            id: requestIdCounter,
            method: "approval.resolve",
            params: params
        )

        do {
            _ = try await connection.send(request)
        } catch {
            Log.runtime.error("Failed to send approval.resolve: \(error.localizedDescription)")
        }
    }

    // MARK: - Audit

    private func recordAudit(
        toolCallId: String,
        sessionId: String,
        agentId: String?,
        toolName: String,
        argumentsHash: String,
        riskLevel: String,
        decision: ToolAuditDecision,
        hookName: String?,
        startTime: Date,
        resultCode: Int?
    ) {
        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
        let event = ToolAuditEvent(
            toolCallId: toolCallId,
            sessionId: sessionId,
            agentId: agentId,
            toolName: toolName,
            argumentsHash: argumentsHash,
            riskLevel: riskLevel,
            decision: decision,
            hookName: hookName,
            latencyMs: latencyMs,
            resultCode: resultCode,
            timestamp: Date()
        )
        auditLog.append(event)
        Log.runtime.info("Audit: \(toolName) → \(decision.rawValue) (\(latencyMs)ms)")
    }

    static func timeout(for riskLevel: String) -> TimeInterval {
        switch riskLevel {
        case "sensitive": return ToolTimeoutPolicy.sensitive
        case "restricted": return ToolTimeoutPolicy.restricted
        default: return ToolTimeoutPolicy.safe
        }
    }
}

private actor ToolExecutionRaceResultBox {
    private var firstResult: ToolResult?
    private var waiters: [CheckedContinuation<ToolResult, Never>] = []

    func publish(_ result: ToolResult) {
        guard firstResult == nil else { return }
        firstResult = result
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume(returning: result)
        }
    }

    func waitForFirstResult() async -> ToolResult {
        if let firstResult {
            return firstResult
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

// MARK: - AnyCodableValue → Native Dictionary

extension AnyCodableValue {
    func toNative() -> Any {
        switch self {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let arr): return arr.map { $0.toNative() }
        case .object(let dict): return dict.toNativeDict()
        }
    }
}

extension Dictionary where Key == String, Value == AnyCodableValue {
    func toNativeDict() -> [String: Any] {
        mapValues { $0.toNative() }
    }
}
