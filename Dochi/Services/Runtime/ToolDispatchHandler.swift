import Foundation
import os

/// Callback to request user approval for a sensitive/restricted tool.
/// Returns (approved, scope) where scope is "once" or "session".
typealias ToolApprovalHandler = @MainActor (ApprovalRequestParams) async -> (approved: Bool, scope: ApprovalScope)

/// Handles `tool.dispatch` and `approval.required` notifications from the runtime
/// by executing local tools and sending results/decisions back.
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

    init(toolService: any BuiltInToolServiceProtocol) {
        self.toolService = toolService
    }

    /// Attach the UDS connection for sending RPCs.
    func setConnection(_ connection: RuntimeUDSConnection) {
        self.connection = connection
    }

    /// Clear session-scoped approvals (e.g., on session close).
    func clearSessionApprovals(sessionId: String) {
        sessionApprovals.removeValue(forKey: sessionId)
    }

    // MARK: - Tool Dispatch

    /// Handle a `tool.dispatch` bridge event.
    /// Checks permission, requests approval if needed, executes the tool, and sends back `tool.result`.
    func handleDispatch(event: BridgeEvent) {
        guard let payload = event.payload,
              case .object(let dict) = payload,
              case .string(let toolCallId) = dict["toolCallId"],
              case .string(let toolName) = dict["toolName"],
              let sessionId = event.sessionId else {
            Log.runtime.warning("Invalid tool.dispatch payload")
            return
        }

        let arguments: [String: Any]
        if case .object(let argsDict) = dict["arguments"] {
            arguments = argsDict.toNativeDict()
        } else {
            arguments = [:]
        }

        let riskLevel: String
        if case .string(let risk) = dict["riskLevel"] {
            riskLevel = risk
        } else {
            riskLevel = "safe"
        }

        let timeout = Self.timeout(for: riskLevel)

        Log.runtime.info("Tool dispatch: \(toolName) (\(toolCallId)), risk=\(riskLevel), timeout=\(timeout)s")

        Task { @MainActor in
            let startTime = Date()

            // Permission check for sensitive/restricted tools
            if riskLevel != "safe" {
                let approved = await checkPermission(
                    toolCallId: toolCallId,
                    sessionId: sessionId,
                    toolName: toolName,
                    riskLevel: riskLevel,
                    arguments: arguments
                )

                if !approved {
                    let deniedResult = ToolResult(
                        toolCallId: toolCallId,
                        content: "도구 '\(toolName)' 실행이 사용자에 의해 거부되었습니다.",
                        isError: true
                    )
                    await sendToolResult(toolCallId: toolCallId, sessionId: sessionId, result: deniedResult, errorCode: BridgeErrorCode.toolPermissionDenied.rawValue)
                    recordAudit(toolCallId: toolCallId, sessionId: sessionId, agentId: event.agentId, toolName: toolName, riskLevel: riskLevel, decision: .denied, startTime: startTime, resultCode: BridgeErrorCode.toolPermissionDenied.rawValue)
                    return
                }
            }

            let result = await executeWithTimeout(
                toolName: toolName,
                toolCallId: toolCallId,
                arguments: arguments,
                timeout: timeout
            )

            await sendToolResult(toolCallId: toolCallId, sessionId: sessionId, result: result)

            let decision: ToolAuditDecision = riskLevel == "safe" ? .allowed : .approved
            recordAudit(toolCallId: toolCallId, sessionId: sessionId, agentId: event.agentId, toolName: toolName, riskLevel: riskLevel, decision: result.isError ? .policyBlocked : decision, startTime: startTime, resultCode: result.isError ? BridgeErrorCode.toolExecutionFailed.rawValue : nil)

            Log.runtime.info("Tool result sent: \(toolName) (\(toolCallId)), success=\(!result.isError)")
        }
    }

    // MARK: - Approval Request (from runtime)

    /// Handle an `approval.required` bridge event from the runtime.
    /// Shows approval UI and sends `approval.resolve` RPC back.
    func handleApprovalRequest(event: BridgeEvent) {
        guard let payload = event.payload,
              case .object(let dict) = payload,
              case .string(let approvalId) = dict["approvalId"],
              case .string(let toolCallId) = dict["toolCallId"],
              case .string(let toolName) = dict["toolName"],
              case .string(let riskLevel) = dict["riskLevel"],
              let sessionId = event.sessionId else {
            Log.runtime.warning("Invalid approval.required payload")
            return
        }

        let reason: String
        if case .string(let r) = dict["reason"] { reason = r } else { reason = "" }
        let argumentsSummary: String
        if case .string(let s) = dict["argumentsSummary"] { argumentsSummary = s } else { argumentsSummary = "" }

        let params = ApprovalRequestParams(
            approvalId: approvalId,
            toolCallId: toolCallId,
            sessionId: sessionId,
            toolName: toolName,
            riskLevel: riskLevel,
            reason: reason,
            argumentsSummary: argumentsSummary
        )

        Task { @MainActor in
            let startTime = Date()

            guard let handler = approvalHandler else {
                Log.runtime.warning("No approval handler — auto-denying \(toolName)")
                await sendApprovalResolve(approvalId: approvalId, toolCallId: toolCallId, sessionId: sessionId, approved: false, scope: .once, note: "No approval handler available")
                recordAudit(toolCallId: toolCallId, sessionId: sessionId, agentId: event.agentId, toolName: toolName, riskLevel: riskLevel, decision: .denied, startTime: startTime, resultCode: nil)
                return
            }

            // Check session-scoped approval
            if let approved = sessionApprovals[sessionId], approved.contains(toolName) {
                Log.runtime.info("Session-scoped approval for \(toolName)")
                await sendApprovalResolve(approvalId: approvalId, toolCallId: toolCallId, sessionId: sessionId, approved: true, scope: .session, note: nil)
                recordAudit(toolCallId: toolCallId, sessionId: sessionId, agentId: event.agentId, toolName: toolName, riskLevel: riskLevel, decision: .approved, startTime: startTime, resultCode: nil)
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
            recordAudit(toolCallId: toolCallId, sessionId: sessionId, agentId: event.agentId, toolName: toolName, riskLevel: riskLevel, decision: decision, startTime: startTime, resultCode: nil)

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

    private func executeWithTimeout(
        toolName: String,
        toolCallId: String,
        arguments: [String: Any],
        timeout: TimeInterval
    ) async -> ToolResult {
        let executionTask = Task { @MainActor in
            await self.toolService.execute(name: toolName, arguments: arguments)
        }

        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(timeout))
            executionTask.cancel()
            return ToolResult(
                toolCallId: toolCallId,
                content: "Tool '\(toolName)' timed out after \(Int(timeout))s",
                isError: true
            )
        }

        let result = await executionTask.value
        timeoutTask.cancel()
        return result
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
        riskLevel: String,
        decision: ToolAuditDecision,
        startTime: Date,
        resultCode: Int?
    ) {
        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
        let event = ToolAuditEvent(
            toolCallId: toolCallId,
            sessionId: sessionId,
            agentId: agentId,
            toolName: toolName,
            riskLevel: riskLevel,
            decision: decision,
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
