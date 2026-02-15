import Foundation
import os

@MainActor
final class BuiltInToolService: BuiltInToolServiceProtocol {
    private let registry = ToolRegistry()
    private let sessionContext: SessionContext
    var confirmationHandler: ToolConfirmationHandler? {
        didSet {
            // Forward to ShellCommandTool for its own confirm-level handling
            if let shellTool = registry.tool(named: "shell.execute") as? ShellCommandTool {
                shellTool.confirmationHandler = confirmationHandler
            }
            // Forward to TerminalRunTool for confirmAlways handling (C-4)
            if let terminalTool = registry.tool(named: "terminal.run") as? TerminalRunTool {
                terminalTool.confirmationHandler = confirmationHandler
            }
        }
    }

    private let mcpService: MCPServiceProtocol

    init(
        contextService: ContextServiceProtocol,
        keychainService: KeychainServiceProtocol,
        sessionContext: SessionContext,
        settings: AppSettings,
        supabaseService: SupabaseServiceProtocol,
        telegramService: TelegramServiceProtocol,
        mcpService: MCPServiceProtocol,
        llmService: LLMServiceProtocol? = nil,
        delegationManager: DelegationManager? = nil
    ) {
        self.sessionContext = sessionContext
        self.mcpService = mcpService

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
        registry.register(TelegramSendPhotoTool(telegramService: telegramService))
        registry.register(TelegramSendMediaGroupTool(telegramService: telegramService))

        // Clipboard (conditional: read=safe, write=sensitive)
        registry.register(ClipboardReadTool())
        registry.register(ClipboardWriteTool())

        // Screenshot (conditional, sensitive)
        registry.register(ScreenshotCaptureTool())

        // File management (conditional: read/list/search=safe, write/move/copy=sensitive, delete=restricted)
        registry.register(FileReadTool())
        registry.register(FileWriteTool())
        registry.register(FileListTool())
        registry.register(FileSearchTool())
        registry.register(FileMoveTool())
        registry.register(FileCopyTool())
        registry.register(FileDeleteTool())

        // Timer (baseline, safe)
        registry.register(SetTimerTool())
        registry.register(ListTimersTool())
        registry.register(CancelTimerTool())

        // Calculator (baseline, safe)
        registry.register(CalculatorTool())

        // DateTime (baseline, safe)
        registry.register(DateTimeTool())

        // Open URL (conditional, sensitive)
        registry.register(OpenURLTool())

        // Shell command (conditional, restricted)
        registry.register(ShellCommandTool(
            contextService: contextService,
            sessionContext: sessionContext,
            settings: settings
        ))

        // Calendar (baseline: list, conditional: create/delete)
        registry.register(ListCalendarEventsTool())
        registry.register(CreateCalendarEventTool())
        registry.register(DeleteCalendarEventTool())

        // Contacts (baseline, safe)
        registry.register(ContactsSearchTool())
        registry.register(ContactsGetDetailTool())

        // Music (baseline, safe)
        registry.register(MusicNowPlayingTool())
        registry.register(MusicPlayPauseTool())
        registry.register(MusicNextTrackTool())
        registry.register(MusicSearchPlayTool())

        // Finder (baseline, safe)
        registry.register(FinderRevealTool())
        registry.register(FinderGetSelectionTool())
        registry.register(FinderListDirectoryTool())

        // Kanban (baseline, safe)
        registry.register(KanbanCreateBoardTool())
        registry.register(KanbanListBoardsTool())
        registry.register(KanbanListCardsTool())
        registry.register(KanbanAddCardTool())
        registry.register(KanbanMoveCardTool())
        registry.register(KanbanUpdateCardTool())
        registry.register(KanbanDeleteCardTool())
        registry.register(KanbanCardHistoryTool())

        // Workflow (baseline, safe/sensitive)
        registry.register(WorkflowCreateTool())
        registry.register(WorkflowListTool())
        registry.register(WorkflowRunTool(toolExecutor: { [weak self] name, args in
            guard let self else {
                return ToolResult(toolCallId: "", content: "서비스를 사용할 수 없습니다.", isError: true)
            }
            // Convert [String: String] to [String: Any] for tool execution
            let toolArgs: [String: Any] = Dictionary(uniqueKeysWithValues: args.map { ($0.key, $0.value as Any) })
            return await self.execute(name: name, arguments: toolArgs)
        }))
        registry.register(WorkflowDeleteTool())
        registry.register(WorkflowAddStepTool())
        registry.register(WorkflowHistoryTool())

        // Git (conditional, safe/restricted)
        registry.register(GitStatusTool())
        registry.register(GitLogTool())
        registry.register(GitDiffTool())
        registry.register(GitCommitTool())
        registry.register(GitBranchTool())

        // GitHub (conditional, safe/sensitive)
        registry.register(GitHubListIssuesTool())
        registry.register(GitHubCreateIssueTool())
        registry.register(GitHubCreatePRTool())
        registry.register(GitHubViewTool())

        // Agent orchestration (conditional, sensitive)
        registry.register(AgentDelegateTaskTool(
            contextService: contextService,
            sessionContext: sessionContext,
            settings: settings,
            llmService: llmService,
            keychainService: keychainService,
            delegationManager: delegationManager
        ))
        registry.register(AgentCheckStatusTool(contextService: contextService, sessionContext: sessionContext, settings: settings))
        registry.register(AgentDelegationStatusTool(delegationManager: delegationManager))

        // Coding agent (conditional, restricted/sensitive)
        registry.register(CodingRunTaskTool())
        registry.register(CodingReviewTool())

        // Coding session management (conditional, safe/restricted)
        let codingSessionManager = CodingSessionManager()
        registry.register(CodingSessionListTool(sessionManager: codingSessionManager))
        registry.register(CodingSessionStartTool(sessionManager: codingSessionManager))
        registry.register(CodingSessionPauseTool(sessionManager: codingSessionManager))
        registry.register(CodingSessionEndTool(sessionManager: codingSessionManager))

        // Terminal (conditional, restricted) (K-1)
        registry.register(TerminalRunTool(settings: settings, terminalService: nil))

        // MCP settings (conditional, sensitive)
        registry.register(MCPAddServerTool(mcpService: mcpService))
        registry.register(MCPUpdateServerTool(mcpService: mcpService))
        registry.register(MCPRemoveServerTool(mcpService: mcpService))

        let toolCount = registry.allToolNames.count
        Log.tool.info("BuiltInToolService initialized with \(toolCount) tools")
    }

    // MARK: - Terminal Service Injection (C-6)

    /// TerminalRunTool이 nil로 등록되므로, 이후 서비스 생성 후 주입
    func configureTerminalService(_ service: TerminalServiceProtocol) {
        if let terminalTool = registry.tool(named: "terminal.run") as? TerminalRunTool {
            terminalTool.updateTerminalService(service)
            Log.tool.info("TerminalService injected into TerminalRunTool")
        }
    }

    // MARK: - Tool Info (for UI)

    var allToolInfos: [ToolInfo] {
        registry.allToolInfos
    }

    // MARK: - BuiltInToolServiceProtocol

    var nonBaselineToolSummaries: [(name: String, description: String, category: ToolCategory)] {
        registry.nonBaselineToolSummaries
    }

    func availableToolSchemas(for permissions: [String]) -> [[String: Any]] {
        var schemas: [[String: Any]] = []

        // Built-in tools
        let tools = registry.availableTools(for: permissions)
        for tool in tools {
            // OpenAI requires tool names to match ^[a-zA-Z0-9_-]+$
            let sanitizedName = Self.sanitizeToolName(tool.name)
            schemas.append([
                "type": "function",
                "function": [
                    "name": sanitizedName,
                    "description": tool.description,
                    "parameters": tool.inputSchema
                ] as [String: Any]
            ])
        }

        // MCP tools (from connected servers)
        let mcpTools = mcpService.listTools()
        for mcpTool in mcpTools {
            let toolName = "mcp_\(mcpTool.serverName)_\(mcpTool.name)"
            schemas.append([
                "type": "function",
                "function": [
                    "name": toolName,
                    "description": "[MCP:\(mcpTool.serverName)] \(mcpTool.description)",
                    "parameters": mcpTool.inputSchema
                ] as [String: Any]
            ])
        }

        return schemas
    }

    func execute(name: String, arguments: [String: Any]) async -> ToolResult {
        // Route MCP tool calls
        if name.hasPrefix("mcp_") {
            return await executeMCPTool(name: name, arguments: arguments)
        }

        // Desanitize: LLM returns sanitized name (dots replaced), restore original
        let resolvedName = Self.desanitizeToolName(name)
        guard let tool = registry.tool(named: resolvedName) else {
            Log.tool.warning("Tool not found: \(name)")
            return ToolResult(
                toolCallId: "",
                content: "오류: '\(name)' 도구를 찾을 수 없습니다. tools.list로 사용 가능한 도구를 확인해주세요.",
                isError: true
            )
        }

        // Sensitive/restricted tools require user confirmation
        // ShellCommandTool handles its own permission flow (allowed/confirm/blocked/default)
        // TerminalRunTool handles its own confirm flow via terminalLLMConfirmAlways (C-4)
        let skipConfirmation = resolvedName == "shell.execute" || resolvedName == "terminal.run"
        if !skipConfirmation && (tool.category == .sensitive || tool.category == .restricted) {
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

    // MARK: - MCP Tool Routing

    // MARK: - Tool Name Sanitization

    /// Replace dots with underscores for OpenAI compatibility (^[a-zA-Z0-9_-]+$)
    static func sanitizeToolName(_ name: String) -> String {
        name.replacingOccurrences(of: ".", with: "-_-")
    }

    /// Restore original tool name from sanitized version
    static func desanitizeToolName(_ name: String) -> String {
        name.replacingOccurrences(of: "-_-", with: ".")
    }

    // MARK: - MCP Tool Routing

    private func executeMCPTool(name: String, arguments: [String: Any]) async -> ToolResult {
        // Parse mcp_{serverName}_{toolName} — find the original tool name
        let mcpTools = mcpService.listTools()
        var matchedToolName: String?

        for mcpTool in mcpTools {
            let expectedName = "mcp_\(mcpTool.serverName)_\(mcpTool.name)"
            if expectedName == name {
                matchedToolName = mcpTool.name
                break
            }
        }

        guard let originalName = matchedToolName else {
            Log.tool.warning("MCP tool not found: \(name)")
            return ToolResult(
                toolCallId: "",
                content: "오류: MCP 도구 '\(name)'을(를) 찾을 수 없습니다.",
                isError: true
            )
        }

        do {
            let result = try await mcpService.callTool(name: originalName, arguments: arguments)
            return ToolResult(
                toolCallId: "",
                content: result.content,
                isError: result.isError
            )
        } catch {
            Log.tool.error("MCP tool execution failed: \(name) — \(error.localizedDescription)")
            return ToolResult(
                toolCallId: "",
                content: "MCP 도구 실행 실패: \(error.localizedDescription)",
                isError: true
            )
        }
    }
}
