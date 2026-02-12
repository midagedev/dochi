import Foundation
import os

@MainActor
final class BuiltInToolService: BuiltInToolServiceProtocol {
    func availableTools(for permissions: [String]) -> [[String: Any]] {
        // TODO: Phase 1 — return tool schemas filtered by permissions
        return []
    }

    func execute(name: String, arguments: [String: Any]) async -> ToolResult {
        // TODO: Phase 1
        Log.tool.info("Tool execution stub: \(name)")
        return ToolResult(toolCallId: "", content: "도구가 아직 구현되지 않았습니다.", isError: true)
    }

    func resetRegistry() {
        // TODO: Phase 1
        Log.tool.info("Tool registry reset")
    }
}
