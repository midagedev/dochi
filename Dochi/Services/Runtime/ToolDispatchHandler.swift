import Foundation
import os

/// Handles `tool.dispatch` notifications from the runtime by executing local tools
/// and sending `tool.result` RPC responses back.
@MainActor
final class ToolDispatchHandler {

    private let toolService: any BuiltInToolServiceProtocol
    private weak var connection: RuntimeUDSConnection?
    private var requestIdCounter: Int = 10_000  // Offset to avoid collision with session RPCs

    init(toolService: any BuiltInToolServiceProtocol) {
        self.toolService = toolService
    }

    /// Attach the UDS connection for sending tool.result RPCs.
    func setConnection(_ connection: RuntimeUDSConnection) {
        self.connection = connection
    }

    /// Handle a `tool.dispatch` bridge event.
    /// Decodes the payload, executes the tool, and sends back `tool.result`.
    func handleDispatch(event: BridgeEvent) {
        guard let payload = event.payload,
              case .object(let dict) = payload,
              case .string(let toolCallId) = dict["toolCallId"],
              case .string(let toolName) = dict["toolName"],
              let sessionId = event.sessionId else {
            Log.runtime.warning("Invalid tool.dispatch payload")
            return
        }

        // Extract arguments
        let arguments: [String: Any]
        if case .object(let argsDict) = dict["arguments"] {
            arguments = argsDict.toNativeDict()
        } else {
            arguments = [:]
        }

        // Extract risk level for timeout
        let riskLevel: String
        if case .string(let risk) = dict["riskLevel"] {
            riskLevel = risk
        } else {
            riskLevel = "safe"
        }

        let timeout = Self.timeout(for: riskLevel)

        Log.runtime.info("Tool dispatch: \(toolName) (\(toolCallId)), risk=\(riskLevel), timeout=\(timeout)s")

        Task { @MainActor in
            let result = await executeWithTimeout(
                toolName: toolName,
                toolCallId: toolCallId,
                arguments: arguments,
                timeout: timeout
            )

            await sendToolResult(
                toolCallId: toolCallId,
                sessionId: sessionId,
                result: result
            )

            Log.runtime.info("Tool result sent: \(toolName) (\(toolCallId)), success=\(!result.isError)")
        }
    }

    // MARK: - Private

    private func executeWithTimeout(
        toolName: String,
        toolCallId: String,
        arguments: [String: Any],
        timeout: TimeInterval
    ) async -> ToolResult {
        // Execute tool on MainActor with a timeout via Task.sleep race
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

        // Race: whichever finishes first wins
        let result = await executionTask.value
        timeoutTask.cancel()
        return result
    }

    private func sendToolResult(
        toolCallId: String,
        sessionId: String,
        result: ToolResult
    ) async {
        guard let connection else {
            Log.runtime.warning("Cannot send tool.result: no UDS connection")
            return
        }

        requestIdCounter += 1
        let requestId = requestIdCounter

        var params: [String: AnyCodableValue] = [
            "toolCallId": .string(toolCallId),
            "sessionId": .string(sessionId),
            "success": .bool(!result.isError),
            "content": .string(result.content),
        ]
        if result.isError {
            params["errorCode"] = .int(BridgeErrorCode.toolExecutionFailed.rawValue)
        }

        let request = JsonRpcRequest(
            id: requestId,
            method: "tool.result",
            params: params
        )

        do {
            _ = try await connection.send(request)
        } catch {
            Log.runtime.error("Failed to send tool.result: \(error.localizedDescription)")
        }
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
    /// Convert AnyCodableValue to native Swift dictionary for tool arguments.
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
