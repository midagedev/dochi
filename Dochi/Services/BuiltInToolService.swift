import Foundation

/// 내장 도구 라우터 - 각 도구 모듈을 통합 관리
@MainActor
final class BuiltInToolService: ObservableObject {
    @Published private(set) var error: String?

    let webSearchTool = WebSearchTool()
    let remindersTool = RemindersTool()
    let alarmTool = AlarmTool()
    let imageGenerationTool = ImageGenerationTool()
    let printImageTool = PrintImageTool()
    let memoryTool = MemoryTool()
    let profileTool = ProfileTool()
    let settingsTool = SettingsTool()
    let agentTool = AgentTool()
    let agentEditorTool = AgentEditorTool()
    let contextEditTool = ContextEditTool()
    let profileAdminTool = ProfileAdminTool()
    let workspaceTool = WorkspaceTool()
    let telegramTool = TelegramTool()
    let toolsRegistryTool = ToolsRegistryTool()

    // Optional shared services for tools that need them
    private(set) weak var conversationService: ConversationServiceProtocol?
    private(set) weak var supabaseService: (any SupabaseServiceProtocol)?
    private(set) weak var telegramService: TelegramService?

    // Registry-based enablement: if set, only these names (plus baseline) are exposed
    private var enabledToolNames: Set<String>? = nil
    private var enabledSince: Date? = nil
    private var registryTTLMinutes: Int = 10

    // Baseline tools always included to serve common conversational needs
    private let baselineAllowlist: Set<String> = [
        // Registry
        "tools.list", "tools.enable",
        // Reminders
        "create_reminder", "list_reminders", "complete_reminder",
        // Alarm
        "set_alarm", "list_alarms", "cancel_alarm",
        // Memory + Profile basics
        "save_memory", "update_memory", "set_current_user",
        // Utility
        "web_search", "print_image", "generate_image"
    ]

    /// 활성 알람 (AlarmTool에서 포워딩)
    var activeAlarms: [AlarmTool.AlarmEntry] {
        alarmTool.activeAlarms
    }

    /// 알람 발동 콜백 (AlarmTool에서 포워딩)
    var onAlarmFired: ((String) -> Void)? {
        get { alarmTool.onAlarmFired }
        set { alarmTool.onAlarmFired = newValue }
    }

    func configure(tavilyApiKey: String, falaiApiKey: String) {
        webSearchTool.apiKey = tavilyApiKey
        imageGenerationTool.apiKey = falaiApiKey
    }

    /// 사용자 컨텍스트 설정 (MemoryTool, ProfileTool에 contextService와 현재 사용자 전달)
    func configureUserContext(contextService: (any ContextServiceProtocol)?, currentUserId: UUID?) {
        memoryTool.contextService = contextService
        memoryTool.currentUserId = currentUserId
        profileTool.contextService = contextService
        agentTool.contextService = contextService
        contextEditTool.contextService = contextService
        profileAdminTool.contextService = contextService
        agentEditorTool.contextService = contextService
    }

    /// 앱 설정 참조 주입 (SettingsTool에서 사용)
    func configureSettings(_ settings: AppSettings) {
        settingsTool.settings = settings
        agentTool.settings = settings
        contextEditTool.settings = settings
        profileAdminTool.settings = settings
        workspaceTool.settings = settings
        agentEditorTool.settings = settings
        telegramTool.settings = settings
        toolsRegistryTool.registryHost = self
    }

    /// 대화 저장소 주입 (프로필 병합 시 userId 이관에 사용)
    func configureConversations(_ service: ConversationServiceProtocol) {
        self.conversationService = service
        profileAdminTool.conversationService = service
    }

    /// Supabase 주입 (워크스페이스 도구)
    func configureSupabase(_ service: any SupabaseServiceProtocol) {
        self.supabaseService = service
        workspaceTool.supabase = service
    }

    /// Telegram 주입
    func configureTelegram(_ service: TelegramService) {
        self.telegramService = service
        telegramTool.telegram = service
    }

    var availableTools: [MCPToolInfo] {
        // Expire enabled list if TTL passed
        if let since = enabledSince, Date().timeIntervalSince(since) > TimeInterval(registryTTLMinutes * 60) {
            enabledToolNames = nil
            enabledSince = nil
        }

        var tools: [MCPToolInfo] = []

        // 웹검색: API 키 있을 때만
        if !webSearchTool.apiKey.isEmpty {
            tools.append(contentsOf: webSearchTool.tools)
        }

        // 미리알림: 항상 사용 가능
        tools.append(contentsOf: remindersTool.tools)

        // 알람: 항상 사용 가능
        tools.append(contentsOf: alarmTool.tools)

        // 이미지 생성: API 키 있을 때만
        if !imageGenerationTool.apiKey.isEmpty {
            tools.append(contentsOf: imageGenerationTool.tools)
        }

        // 이미지 프린트: 항상 사용 가능
        tools.append(contentsOf: printImageTool.tools)

        // 기억 관리: 프로필이 있을 때만
        if memoryTool.contextService != nil {
            tools.append(contentsOf: memoryTool.tools)
        }

        // 사용자 식별: 프로필이 있을 때만
        if profileTool.contextService != nil {
            tools.append(contentsOf: profileTool.tools)
        }

        // 설정 변경: 설정 참조가 주입된 경우만 노출
        if settingsTool.settings != nil {
            tools.append(contentsOf: settingsTool.tools)
        }

        // 에이전트 관리: 컨텍스트/설정이 모두 준비된 경우 노출
        if agentTool.contextService != nil, agentTool.settings != nil {
            tools.append(contentsOf: agentTool.tools)
        }

        if agentEditorTool.contextService != nil, agentEditorTool.settings != nil {
            tools.append(contentsOf: agentEditorTool.tools)
        }

        // 컨텍스트 편집 (base system prompt)
        if contextEditTool.contextService != nil {
            tools.append(contentsOf: contextEditTool.tools)
        }

        // 프로필 관리(고급)
        if profileAdminTool.contextService != nil {
            tools.append(contentsOf: profileAdminTool.tools)
        }

        // 워크스페이스 관련 (Supabase 구성 시)
        if workspaceTool.supabase != nil {
            tools.append(contentsOf: workspaceTool.tools)
        }

        // 텔레그램 도구 (서비스/설정 존재 시)
        if telegramTool.telegram != nil, telegramTool.settings != nil {
            tools.append(contentsOf: telegramTool.tools)
        }

        // Registry tools always available
        tools.append(contentsOf: toolsRegistryTool.tools)

        // Apply registry filter if enabled
        if let enabled = enabledToolNames {
            let allowed = baselineAllowlist.union(enabled)
            return tools.filter { allowed.contains($0.name) }
        }
        // Default: expose only baseline to reduce token usage
        return tools.filter { baselineAllowlist.contains($0.name) }
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        // 각 도구 모듈에 라우팅
        let allModules: [any BuiltInTool] = [
            toolsRegistryTool,
            webSearchTool,
            remindersTool,
            alarmTool,
            imageGenerationTool,
            printImageTool,
            memoryTool,
            profileTool,
            settingsTool,
            agentTool,
            agentEditorTool,
            contextEditTool,
            profileAdminTool,
            workspaceTool,
            telegramTool
        ]

        for module in allModules {
            if module.tools.contains(where: { $0.name == name }) {
                return try await module.callTool(name: name, arguments: arguments)
            }
        }

        throw BuiltInToolError.unknownTool(name)
    }
}

// MARK: - Registry (public helpers for ToolsRegistryTool)

extension BuiltInToolService {
    func setEnabledToolNames(_ names: [String]?) {
        if let names {
            self.enabledToolNames = Set(names)
            self.enabledSince = Date()
        } else {
            self.enabledToolNames = nil
            self.enabledSince = nil
        }
    }

    func getEnabledToolNames() -> [String]? {
        enabledToolNames.map { Array($0) }
    }

    func setRegistryTTL(minutes: Int) {
        registryTTLMinutes = max(1, minutes)
    }

    func toolCatalogByCategory() -> [String: [String]] {
        var catalog: [String: [String]] = [:]
        func add(_ category: String, _ list: [MCPToolInfo]) {
            if list.isEmpty { return }
            let names = list.map { $0.name }
            catalog[category, default: []].append(contentsOf: names)
        }
        // Compute candidates (respecting current service availability but ignoring registry filter)
        var all: [MCPToolInfo] = []
        if !webSearchTool.apiKey.isEmpty { all.append(contentsOf: webSearchTool.tools) }
        all.append(contentsOf: remindersTool.tools)
        all.append(contentsOf: alarmTool.tools)
        if !imageGenerationTool.apiKey.isEmpty { all.append(contentsOf: imageGenerationTool.tools) }
        all.append(contentsOf: printImageTool.tools)
        if memoryTool.contextService != nil { all.append(contentsOf: memoryTool.tools) }
        if profileTool.contextService != nil { all.append(contentsOf: profileTool.tools) }
        if settingsTool.settings != nil { all.append(contentsOf: settingsTool.tools) }
        if agentTool.contextService != nil, agentTool.settings != nil { all.append(contentsOf: agentTool.tools) }
        if agentEditorTool.contextService != nil, agentEditorTool.settings != nil { all.append(contentsOf: agentEditorTool.tools) }
        if contextEditTool.contextService != nil { all.append(contentsOf: contextEditTool.tools) }
        if profileAdminTool.contextService != nil { all.append(contentsOf: profileAdminTool.tools) }
        if workspaceTool.supabase != nil { all.append(contentsOf: workspaceTool.tools) }
        if telegramTool.telegram != nil, telegramTool.settings != nil { all.append(contentsOf: telegramTool.tools) }

        let available = Set(all.map { $0.name })
        add("registry", toolsRegistryTool.tools)
        add("reminders", remindersTool.tools)
        add("alarm", alarmTool.tools)
        add("memory", memoryTool.tools)
        add("profile", profileTool.tools)
        add("search_image", webSearchTool.tools + imageGenerationTool.tools + printImageTool.tools)
        add("settings", settingsTool.tools)
        add("agent", agentTool.tools)
        add("agent_edit", agentEditorTool.tools)
        add("context", contextEditTool.tools)
        add("profile_admin", profileAdminTool.tools)
        add("workspace", workspaceTool.tools)
        add("telegram", telegramTool.tools)

        for (k, v) in catalog {
            catalog[k] = v.filter { available.contains($0) }
        }
        return catalog
    }
}

// MARK: - Errors

enum BuiltInToolError: LocalizedError {
    case unknownTool(String)
    case missingApiKey(String)
    case invalidArguments(String)
    case apiError(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "Unknown built-in tool: \(name)"
        case .missingApiKey(let service):
            return "\(service) API key is not configured"
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        case .apiError(let message):
            return message
        case .invalidResponse(let message):
            return message
        }
    }
}
