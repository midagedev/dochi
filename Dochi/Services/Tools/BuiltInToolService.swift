import Foundation
import os

@MainActor
final class BuiltInToolService: BuiltInToolServiceProtocol {
    private let registry = ToolRegistry()
    private let sessionContext: SessionContext
    private let settings: AppSettings
    private let capabilityRouter = CapabilityRouter()
    private let routingPolicy = ToolRoutingPolicy()
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
    private(set) var selectedCapabilityLabel: String?

    init(
        contextService: ContextServiceProtocol,
        keychainService: KeychainServiceProtocol,
        sessionContext: SessionContext,
        settings: AppSettings,
        supabaseService: SupabaseServiceProtocol,
        telegramService: TelegramServiceProtocol,
        mcpService: MCPServiceProtocol,
        delegationManager: DelegationManager? = nil
    ) {
        self.sessionContext = sessionContext
        self.settings = settings
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

        // App guide (baseline, safe) (K-5)
        if settings.appGuideEnabled {
            registry.register(AppGuideTool(toolRegistry: registry))
        }

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
        registry.register(GitStatusTool(sessionContext: sessionContext))
        registry.register(GitLogTool(sessionContext: sessionContext))
        registry.register(GitDiffTool(sessionContext: sessionContext))
        registry.register(GitCommitTool(sessionContext: sessionContext))
        registry.register(GitBranchTool(sessionContext: sessionContext))

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
            keychainService: keychainService,
            delegationManager: delegationManager
        ))
        registry.register(AgentCheckStatusTool(contextService: contextService, sessionContext: sessionContext, settings: settings))
        registry.register(AgentDelegationStatusTool(delegationManager: delegationManager))

        // Coding agent (conditional, restricted/sensitive)
        registry.register(CodingRunTaskTool(sessionContext: sessionContext))
        registry.register(CodingReviewTool(sessionContext: sessionContext))

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
    /// Register an external tool with the registry.
    func registerTool(_ tool: any BuiltInToolProtocol) {
        registry.register(tool)
    }

    func configureTerminalService(_ service: TerminalServiceProtocol) {
        if let terminalTool = registry.tool(named: "terminal.run") as? TerminalRunTool {
            terminalTool.updateTerminalService(service)
            Log.tool.info("TerminalService injected into TerminalRunTool")
        }
    }

    // MARK: - Tool Info (for UI)

    var allToolInfos: [ToolInfo] {
        let builtinInfos = registry.allToolInfos
        let mcpInfos = mcpService.listTools().map { tool in
            let routedName = routingPolicy.mcpToolName(for: tool)
            let risk = routingPolicy.classifyMCPRisk(
                serverName: tool.serverName,
                toolName: tool.name,
                description: tool.description
            )
            return ToolInfo(
                name: routedName,
                description: "[MCP:\(tool.serverName)] \(tool.description)",
                category: risk,
                isBaseline: false,
                isEnabled: true,
                parameters: []
            )
        }
        return (builtinInfos + mcpInfos).sorted { $0.name < $1.name }
    }

    // MARK: - BuiltInToolServiceProtocol

    var nonBaselineToolSummaries: [(name: String, description: String, category: ToolCategory)] {
        registry.nonBaselineToolSummaries
    }

    func availableToolSchemas(for permissions: [String]) -> [[String: Any]] {
        availableToolSchemas(for: permissions, preferredToolGroups: [])
    }

    func availableToolSchemas(for permissions: [String], preferredToolGroups: [String]) -> [[String: Any]] {
        var schemas: [[String: Any]] = []
        selectedCapabilityLabel = nil

        // Built-in tools
        let availableTools = registry.availableTools(for: permissions)
        let tools: [any BuiltInToolProtocol]
        if settings.capabilityRouterV2Enabled {
            let filtered = capabilityRouter.filter(
                tools: availableTools,
                enabledToolNames: registry.enabledToolNames,
                permissions: permissions
            )
            tools = filtered.filteredTools
            selectedCapabilityLabel = filtered.selectedLabel
        } else {
            tools = availableTools
        }

        let orderedTools = orderedToolsByPreference(tools, preferredToolGroups: preferredToolGroups)
        for tool in orderedTools {
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

    private func orderedToolsByPreference(
        _ tools: [any BuiltInToolProtocol],
        preferredToolGroups: [String]
    ) -> [any BuiltInToolProtocol] {
        var orderedGroups: [String] = []
        var seen: Set<String> = []
        for raw in preferredToolGroups {
            let normalized = ToolGroupResolver.normalizeGroupName(raw)
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                orderedGroups.append(normalized)
            }
        }
        guard !orderedGroups.isEmpty else { return tools.sorted { $0.name < $1.name } }

        let priorities = Dictionary(uniqueKeysWithValues: orderedGroups.enumerated().map { ($0.element, $0.offset) })

        return tools.sorted { lhs, rhs in
            let lhsPriority = priorities[ToolGroupResolver.group(forToolName: lhs.name)] ?? Int.max
            let rhsPriority = priorities[ToolGroupResolver.group(forToolName: rhs.name)] ?? Int.max
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            return lhs.name < rhs.name
        }
    }

    func execute(name: String, arguments: [String: Any]) async -> ToolResult {
        // Desanitize: LLM returns sanitized name (dots replaced), restore original
        let resolvedName = Self.desanitizeToolName(name)
        let mcpTools = mcpService.listTools()
        let builtInTool = registry.tool(named: resolvedName)

        guard let route = routingPolicy.resolve(
            requestedName: name,
            resolvedName: resolvedName,
            builtInTool: builtInTool,
            mcpTools: mcpTools
        ) else {
            Log.tool.warning("Tool not found: \(name)")
            return ToolResult(
                toolCallId: "",
                content: "오류: '\(name)' 도구를 찾을 수 없습니다. tools.list로 사용 가능한 도구를 확인해주세요.",
                isError: true
            )
        }

        switch route {
        case .builtIn(let tool, let reason):
            logRoutingDecision(
                requestedName: name,
                source: .builtIn,
                resolvedName: tool.name,
                risk: tool.category,
                reason: reason
            )
            return await executeBuiltInTool(
                requestedName: name,
                tool: tool,
                arguments: arguments
            )

        case .mcp(
            let requestedName,
            let originalName,
            let serverName,
            let description,
            let risk,
            let reason
        ):
            logRoutingDecision(
                requestedName: requestedName,
                source: .mcp,
                resolvedName: originalName,
                risk: risk,
                reason: reason
            )
            return await executeMCPTool(
                requestedName: requestedName,
                originalName: originalName,
                serverName: serverName,
                description: description,
                risk: risk,
                arguments: arguments
            )
        }
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

    // MARK: - Tool Name Sanitization

    /// Replace dots with underscores for OpenAI compatibility (^[a-zA-Z0-9_-]+$)
    static func sanitizeToolName(_ name: String) -> String {
        name.replacingOccurrences(of: ".", with: "-_-")
    }

    /// Restore original tool name from sanitized version
    static func desanitizeToolName(_ name: String) -> String {
        name.replacingOccurrences(of: "-_-", with: ".")
    }

    private enum ApprovalOutcome {
        case approved
        case deniedByUser
        case unavailable
    }

    private func executeBuiltInTool(
        requestedName: String,
        tool: any BuiltInToolProtocol,
        arguments: [String: Any]
    ) async -> ToolResult {
        let approval = await requestApprovalIfNeeded(
            requestedToolName: requestedName,
            toolNameForPrompt: tool.name,
            toolDescription: tool.description,
            category: tool.category,
            skipConfirmation: tool.name == "shell.execute" || tool.name == "terminal.run"
        )
        switch approval {
        case .approved:
            break

        case .deniedByUser:
            return ToolResult(
                toolCallId: "",
                content: "도구 '\(requestedName)' 실행이 사용자에 의해 거부되었습니다.",
                isError: true
            )

        case .unavailable:
            return ToolResult(
                toolCallId: "",
                content: "도구 '\(requestedName)' 실행을 위한 사용자 확인 채널을 사용할 수 없습니다.",
                isError: true
            )
        }

        Log.tool.info("Executing tool: \(requestedName)")
        let result = await tool.execute(arguments: arguments)

        if result.isError {
            Log.tool.warning("Tool \(requestedName) returned error: \(result.content)")
        } else {
            Log.tool.debug("Tool \(requestedName) completed successfully")
        }

        return result
    }

    private func executeMCPTool(
        requestedName: String,
        originalName: String,
        serverName: String,
        description: String,
        risk: ToolCategory,
        arguments: [String: Any]
    ) async -> ToolResult {
        let promptName = "[MCP:\(serverName)] \(originalName)"
        let approval = await requestApprovalIfNeeded(
            requestedToolName: requestedName,
            toolNameForPrompt: promptName,
            toolDescription: description,
            category: risk,
            skipConfirmation: false
        )
        switch approval {
        case .approved:
            break

        case .deniedByUser:
            return ToolResult(
                toolCallId: "",
                content: "도구 '\(requestedName)' 실행이 사용자에 의해 거부되었습니다.",
                isError: true
            )

        case .unavailable:
            return ToolResult(
                toolCallId: "",
                content: "도구 '\(requestedName)' 실행을 위한 사용자 확인 채널을 사용할 수 없습니다.",
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
            Log.tool.error("MCP tool execution failed: \(requestedName) — \(error.localizedDescription)")
            return ToolResult(
                toolCallId: "",
                content: mcpFallbackMessage(for: requestedName, error: error),
                isError: true
            )
        }
    }

    private func requestApprovalIfNeeded(
        requestedToolName: String,
        toolNameForPrompt: String,
        toolDescription: String,
        category: ToolCategory,
        skipConfirmation: Bool
    ) async -> ApprovalOutcome {
        guard !skipConfirmation else { return .approved }
        guard category == .sensitive || category == .restricted else { return .approved }

        guard let handler = confirmationHandler else {
            Log.tool.warning("Tool \(requestedToolName) blocked: confirmation handler unavailable")
            return .unavailable
        }

        let approved = await handler(toolNameForPrompt, toolDescription)
        if !approved {
            Log.tool.info("Tool \(requestedToolName) denied by user")
            return .deniedByUser
        }
        return .approved
    }

    private func logRoutingDecision(
        requestedName: String,
        source: ToolRouteSource,
        resolvedName: String,
        risk: ToolCategory,
        reason: String
    ) {
        Log.tool.info(
            "Routing decision: requested=\(requestedName), source=\(source.rawValue), resolved=\(resolvedName), risk=\(risk.rawValue), reason=\(reason)"
        )
    }

    private func mcpFallbackMessage(for toolName: String, error: Error) -> String {
        if let mcpError = error as? MCPServiceError {
            switch mcpError {
            case .notConnected, .connectionFailed:
                return """
                MCP 서버가 현재 비가용 상태입니다.
                설정 > 통합 > MCP에서 서버 상태를 확인한 뒤 다시 시도해주세요.
                필요하면 내장 도구(terminal.run, git.*)로 임시 진행할 수 있습니다.
                """

            case .toolNotFound:
                return "오류: MCP 도구 '\(toolName)'을(를) 찾을 수 없습니다."

            case .serverNotFound, .executionFailed:
                break
            }
        }

        return "MCP 도구 실행 실패: \(error.localizedDescription)"
    }
}
