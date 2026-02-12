import Foundation
import os

@MainActor
final class BuiltInToolService: BuiltInToolServiceProtocol {
    private let registry = ToolRegistry()
    private let sessionContext: SessionContext
    var confirmationHandler: ToolConfirmationHandler?

    init(
        contextService: ContextServiceProtocol,
        keychainService: KeychainServiceProtocol,
        sessionContext: SessionContext,
        settings: AppSettings,
        supabaseService: SupabaseServiceProtocol,
        telegramService: TelegramServiceProtocol,
        mcpService: MCPServiceProtocol
    ) {
        self.sessionContext = sessionContext

        // Registry meta-tools (baseline, safe)
        registry.register(ToolsListTool(registry: registry))
        registry.register(ToolsEnableTool(registry: registry))
        registry.register(ToolsEnableTTLTool(registry: registry))
        registry.register(ToolsResetTool(registry: registry))

        // Reminders (baseline, safe)
        registry.register(CreateReminderTool())
        registry.register(ListRemindersTool())
        registry.register(CompleteReminderTool())

        // Alarms (baseline, safe)
        registry.register(SetAlarmTool())
        registry.register(ListAlarmsTool())
        registry.register(CancelAlarmTool())

        // Memory (baseline, safe)
        registry.register(SaveMemoryTool(contextService: contextService, sessionContext: sessionContext))
        registry.register(UpdateMemoryTool(contextService: contextService, sessionContext: sessionContext))

        // Profile — set_current_user (baseline, safe)
        registry.register(SetCurrentUserTool(contextService: contextService, sessionContext: sessionContext))

        // Web search (baseline, safe)
        registry.register(WebSearchTool(keychainService: keychainService))

        // Image generation (baseline, safe)
        registry.register(GenerateImageTool(keychainService: keychainService))

        // Print image (baseline, safe)
        registry.register(PrintImageTool())

        // Settings (conditional, sensitive)
        registry.register(SettingsListTool(settings: settings, keychainService: keychainService))
        registry.register(SettingsGetTool(settings: settings, keychainService: keychainService))
        registry.register(SettingsSetTool(settings: settings, keychainService: keychainService))

        // Agent management (conditional, sensitive)
        registry.register(AgentCreateTool(contextService: contextService, sessionContext: sessionContext, settings: settings))
        registry.register(AgentListTool(contextService: contextService, sessionContext: sessionContext, settings: settings))
        registry.register(AgentSetActiveTool(contextService: contextService, sessionContext: sessionContext, settings: settings))

        // Agent editor — persona (conditional, sensitive)
        registry.register(AgentPersonaGetTool(contextService: contextService, sessionContext: sessionContext, settings: settings))
        registry.register(AgentPersonaSearchTool(contextService: contextService, sessionContext: sessionContext, settings: settings))
        registry.register(AgentPersonaUpdateTool(contextService: contextService, sessionContext: sessionContext, settings: settings))
        registry.register(AgentPersonaReplaceTool(contextService: contextService, sessionContext: sessionContext, settings: settings))
        registry.register(AgentPersonaDeleteLinesTool(contextService: contextService, sessionContext: sessionContext, settings: settings))

        // Agent editor — memory (conditional, sensitive)
        registry.register(AgentMemoryGetTool(contextService: contextService, sessionContext: sessionContext, settings: settings))
        registry.register(AgentMemoryAppendTool(contextService: contextService, sessionContext: sessionContext, settings: settings))
        registry.register(AgentMemoryReplaceTool(contextService: contextService, sessionContext: sessionContext, settings: settings))
        registry.register(AgentMemoryUpdateTool(contextService: contextService, sessionContext: sessionContext, settings: settings))

        // Agent editor — config (conditional, sensitive)
        registry.register(AgentConfigGetTool(contextService: contextService, sessionContext: sessionContext, settings: settings))
        registry.register(AgentConfigUpdateTool(contextService: contextService, sessionContext: sessionContext, settings: settings))

        // Profile admin (conditional, sensitive)
        registry.register(ProfileCreateTool(contextService: contextService, sessionContext: sessionContext))
        registry.register(ProfileAddAliasTool(contextService: contextService, sessionContext: sessionContext))
        registry.register(ProfileRenameTool(contextService: contextService, sessionContext: sessionContext))
        registry.register(ProfileMergeTool(contextService: contextService, sessionContext: sessionContext))

        // Context (conditional, sensitive)
        registry.register(UpdateBaseSystemPromptTool(contextService: contextService))

        // Workspace (conditional, sensitive)
        registry.register(WorkspaceCreateTool(supabaseService: supabaseService, settings: settings))
        registry.register(WorkspaceJoinByInviteTool(supabaseService: supabaseService, settings: settings))
        registry.register(WorkspaceListTool(supabaseService: supabaseService, settings: settings))
        registry.register(WorkspaceSwitchTool(supabaseService: supabaseService, settings: settings))
        registry.register(WorkspaceRegenerateInviteCodeTool(supabaseService: supabaseService, settings: settings))

        // Telegram (conditional, sensitive)
        registry.register(TelegramEnableTool(keychainService: keychainService, telegramService: telegramService, settings: settings))
        registry.register(TelegramSetTokenTool(keychainService: keychainService, telegramService: telegramService, settings: settings))
        registry.register(TelegramGetMeTool(keychainService: keychainService, telegramService: telegramService, settings: settings))
        registry.register(TelegramSendMessageTool(keychainService: keychainService, telegramService: telegramService, settings: settings))

        // MCP settings (conditional, sensitive)
        registry.register(MCPAddServerTool(mcpService: mcpService))
        registry.register(MCPUpdateServerTool(mcpService: mcpService))
        registry.register(MCPRemoveServerTool(mcpService: mcpService))

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

        // Sensitive/restricted tools require user confirmation
        if tool.category == .sensitive || tool.category == .restricted {
            if let handler = confirmationHandler {
                let approved = await handler(tool.name, tool.description)
                if !approved {
                    Log.tool.info("Tool \(name) denied by user")
                    return ToolResult(
                        toolCallId: "",
                        content: "도구 '\(name)' 실행이 사용자에 의해 거부되었습니다.",
                        isError: true
                    )
                }
            }
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
