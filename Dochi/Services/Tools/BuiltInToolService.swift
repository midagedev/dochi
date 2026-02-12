import Foundation
import os

@MainActor
final class BuiltInToolService: BuiltInToolServiceProtocol {
    private let registry = ToolRegistry()
    private let sessionContext: SessionContext

    init(
        contextService: ContextServiceProtocol,
        keychainService: KeychainServiceProtocol,
        sessionContext: SessionContext
    ) {
        self.sessionContext = sessionContext

        // Registry meta-tools
        registry.register(ToolsListTool(registry: registry))
        registry.register(ToolsEnableTool(registry: registry))
        registry.register(ToolsEnableTTLTool(registry: registry))
        registry.register(ToolsResetTool(registry: registry))

        // Reminders
        registry.register(CreateReminderTool())
        registry.register(ListRemindersTool())
        registry.register(CompleteReminderTool())

        // Alarms
        registry.register(SetAlarmTool())
        registry.register(ListAlarmsTool())
        registry.register(CancelAlarmTool())

        // Memory
        registry.register(SaveMemoryTool(contextService: contextService, sessionContext: sessionContext))
        registry.register(UpdateMemoryTool(contextService: contextService, sessionContext: sessionContext))

        // Profile
        registry.register(SetCurrentUserTool(contextService: contextService, sessionContext: sessionContext))

        // Web search
        registry.register(WebSearchTool(keychainService: keychainService))

        // Image generation
        registry.register(GenerateImageTool(keychainService: keychainService))

        // Print image
        registry.register(PrintImageTool())

        let toolCount = registry.allToolNames.count
        Log.tool.info("BuiltInToolService initialized with \(toolCount) tools")
    }

    // MARK: - BuiltInToolServiceProtocol

    func availableToolSchemas(for permissions: [String]) -> [[String: Any]] {
        let tools = registry.availableTools(for: permissions)
        return tools.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": tool.inputSchema
                ] as [String: Any]
            ]
        }
    }

    func execute(name: String, arguments: [String: Any]) async -> ToolResult {
        guard let tool = registry.tool(named: name) else {
            Log.tool.warning("Tool not found: \(name)")
            return ToolResult(
                toolCallId: "",
                content: "오류: '\(name)' 도구를 찾을 수 없습니다. tools.list로 사용 가능한 도구를 확인해주세요.",
                isError: true
            )
        }

        Log.tool.info("Executing tool: \(name)")
        let result = await tool.execute(arguments: arguments)

        if result.isError {
            Log.tool.warning("Tool \(name) returned error: \(result.content)")
        } else {
            Log.tool.debug("Tool \(name) completed successfully")
        }

        return result
    }

    func enableTools(names: [String]) {
        registry.enable(names: names)
    }

    func enableToolsTTL(minutes: Int) {
        registry.enableTTL(minutes: minutes)
    }

    func resetRegistry() {
        registry.reset()
    }
}
