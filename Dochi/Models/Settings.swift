import Foundation
import SwiftUI
import os

@MainActor
final class AppSettings: ObservableObject {
    @Published var wakeWordEnabled: Bool {
        didSet { defaults.set(wakeWordEnabled, forKey: Keys.wakeWordEnabled) }
    }
    @Published var wakeWord: String {
        didSet { defaults.set(wakeWord, forKey: Keys.wakeWord) }
    }

    // LLM settings
    @Published var llmProvider: LLMProvider {
        didSet {
            defaults.set(llmProvider.rawValue, forKey: Keys.llmProvider)
            if !llmProvider.models.contains(llmModel) {
                llmModel = llmProvider.models.first ?? ""
            }
        }
    }
    @Published var llmModel: String {
        didSet { defaults.set(llmModel, forKey: Keys.llmModel) }
    }

    // Model routing (beta)
    @Published var autoModelRoutingEnabled: Bool {
        didSet { defaults.set(autoModelRoutingEnabled, forKey: Keys.autoModelRoutingEnabled) }
    }

    // TTS settings
    @Published var supertonicVoice: SupertonicVoice {
        didSet { defaults.set(supertonicVoice.rawValue, forKey: Keys.supertonicVoice) }
    }
    @Published var ttsSpeed: Float {
        didSet { defaults.set(ttsSpeed, forKey: Keys.ttsSpeed) }
    }
    @Published var ttsDiffusionSteps: Int {
        didSet { defaults.set(ttsDiffusionSteps, forKey: Keys.ttsDiffusionSteps) }
    }

    // Display settings
    @Published var chatFontSize: Double {
        didSet { defaults.set(chatFontSize, forKey: Keys.chatFontSize) }
    }

    // STT settings
    @Published var sttSilenceTimeout: Double {
        didSet { defaults.set(sttSilenceTimeout, forKey: Keys.sttSilenceTimeout) }
    }

    // Memory compression
    @Published var contextAutoCompress: Bool {
        didSet { defaults.set(contextAutoCompress, forKey: Keys.contextAutoCompress) }
    }
    @Published var contextMaxSize: Int {
        didSet { defaults.set(contextMaxSize, forKey: Keys.contextMaxSize) }
    }

    // Agent
    @Published var activeAgentName: String {
        didSet { defaults.set(activeAgentName, forKey: Keys.activeAgentName) }
    }

    // Telegram bot
    @Published var telegramEnabled: Bool {
        didSet { defaults.set(telegramEnabled, forKey: Keys.telegramEnabled) }
    }
    @Published var telegramStreamReplies: Bool {
        didSet { defaults.set(telegramStreamReplies, forKey: Keys.telegramStreamReplies) }
    }

    // MCP servers
    @Published var mcpServers: [MCPServerConfig] {
        didSet { saveMCPServers() }
    }

    // Claude Code UI integration
    @Published var claudeUIEnabled: Bool {
        didSet { defaults.set(claudeUIEnabled, forKey: Keys.claudeUIEnabled) }
    }
    @Published var claudeUIBaseURL: String {
        didSet { defaults.set(claudeUIBaseURL, forKey: Keys.claudeUIBaseURL) }
    }

    // Workspace
    @Published var currentWorkspaceId: UUID? {
        didSet {
            if let id = currentWorkspaceId {
                defaults.set(id.uuidString, forKey: Keys.currentWorkspaceId)
            } else {
                defaults.removeObject(forKey: Keys.currentWorkspaceId)
            }
        }
    }

    // Tools Registry
    @Published var toolsRegistryAutoReset: Bool {
        didSet { defaults.set(toolsRegistryAutoReset, forKey: Keys.toolsRegistryAutoReset) }
    }

    // User profiles
    @Published var defaultUserId: UUID? {
        didSet {
            if let id = defaultUserId {
                defaults.set(id.uuidString, forKey: Keys.defaultUserId)
            } else {
                defaults.removeObject(forKey: Keys.defaultUserId)
            }
        }
    }

    private enum Keys {
        static let wakeWordEnabled = "settings.wakeWordEnabled"
        static let wakeWord = "settings.wakeWord"
        static let llmProvider = "settings.llmProvider"
        static let llmModel = "settings.llmModel"
        static let supertonicVoice = "settings.supertonicVoice"
        static let ttsSpeed = "settings.ttsSpeed"
        static let ttsDiffusionSteps = "settings.ttsDiffusionSteps"
        static let chatFontSize = "settings.chatFontSize"
        static let sttSilenceTimeout = "settings.sttSilenceTimeout"
        static let contextAutoCompress = "settings.contextAutoCompress"
        static let contextMaxSize = "settings.contextMaxSize"
        static let mcpServers = "settings.mcpServers"
        static let defaultUserId = "settings.defaultUserId"
        static let activeAgentName = "settings.activeAgentName"
        static let currentWorkspaceId = "settings.currentWorkspaceId"
        static let migratedToWorkspaceStructure = "settings.migratedToWorkspaceStructure"
        static let telegramEnabled = "settings.telegramEnabled"
        static let toolsRegistryAutoReset = "settings.toolsRegistryAutoReset"
        static let autoModelRoutingEnabled = "settings.autoModelRoutingEnabled"
        static let telegramStreamReplies = "settings.telegramStreamReplies"
        static let claudeUIEnabled = "settings.claudeUIEnabled"
        static let claudeUIBaseURL = "settings.claudeUIBaseURL"
    }

    // MARK: - Dependencies

    private let keychainService: KeychainServiceProtocol
    let contextService: ContextServiceProtocol
    private let defaults: UserDefaults

    /// KeychainService 참조 (SupabaseService 등 외부에서 공유)
    var keychainServiceRef: KeychainServiceProtocol { keychainService }

    init(
        keychainService: KeychainServiceProtocol = KeychainService(),
        contextService: ContextServiceProtocol = ContextService(),
        defaults: UserDefaults = .standard
    ) {
        self.keychainService = keychainService
        self.contextService = contextService
        self.defaults = defaults

        // 마이그레이션
        Self.migrateToFileBasedContext(defaults: defaults, contextService: contextService)

        self.wakeWordEnabled = defaults.bool(forKey: Keys.wakeWordEnabled)
        self.wakeWord = defaults.string(forKey: Keys.wakeWord) ?? Constants.Defaults.wakeWord

        let providerRaw = defaults.string(forKey: Keys.llmProvider) ?? LLMProvider.openai.rawValue
        let provider = LLMProvider(rawValue: providerRaw) ?? .openai
        self.llmProvider = provider
        self.llmModel = defaults.string(forKey: Keys.llmModel) ?? provider.models.first ?? ""

        let voiceRaw = defaults.string(forKey: Keys.supertonicVoice) ?? Constants.Defaults.supertonicVoice
        self.supertonicVoice = SupertonicVoice(rawValue: voiceRaw) ?? .F1
        self.ttsSpeed = defaults.object(forKey: Keys.ttsSpeed) as? Float ?? Constants.Defaults.ttsSpeed
        self.ttsDiffusionSteps = defaults.object(forKey: Keys.ttsDiffusionSteps) as? Int ?? Constants.Defaults.ttsDiffusionSteps

        self.chatFontSize = defaults.object(forKey: Keys.chatFontSize) as? Double ?? Constants.Defaults.chatFontSize
        self.sttSilenceTimeout = defaults.object(forKey: Keys.sttSilenceTimeout) as? Double ?? Constants.Defaults.sttSilenceTimeout
        self.contextAutoCompress = defaults.object(forKey: Keys.contextAutoCompress) as? Bool ?? true
        self.contextMaxSize = defaults.object(forKey: Keys.contextMaxSize) as? Int ?? Constants.Defaults.contextMaxSize

        self.activeAgentName = defaults.string(forKey: Keys.activeAgentName) ?? Constants.Agent.defaultName
        self.telegramEnabled = defaults.bool(forKey: Keys.telegramEnabled)
        self.telegramStreamReplies = defaults.object(forKey: Keys.telegramStreamReplies) as? Bool ?? true
        self.toolsRegistryAutoReset = defaults.object(forKey: Keys.toolsRegistryAutoReset) as? Bool ?? true
        self.autoModelRoutingEnabled = defaults.object(forKey: Keys.autoModelRoutingEnabled) as? Bool ?? false
        self.claudeUIEnabled = defaults.object(forKey: Keys.claudeUIEnabled) as? Bool ?? false
        self.claudeUIBaseURL = defaults.string(forKey: Keys.claudeUIBaseURL) ?? "http://localhost:3001"

        // MCP servers
        if let data = defaults.data(forKey: Keys.mcpServers) {
            do {
                self.mcpServers = try JSONDecoder().decode([MCPServerConfig].self, from: data)
            } catch {
                Log.storage.warning("MCP 서버 설정 파싱 실패: \(error, privacy: .public)")
                self.mcpServers = []
            }
        } else {
            self.mcpServers = []
        }



        // Workspace
        if let idString = defaults.string(forKey: Keys.currentWorkspaceId),
           let id = UUID(uuidString: idString) {
            self.currentWorkspaceId = id
        } else {
            // 없으면 첫 번째 워크스페이스 사용하거나 nil
            self.currentWorkspaceId = contextService.listWorkspaces().first?.id
        }
    }

    // MARK: - MCP Servers

    private func saveMCPServers() {
        do {
            let data = try JSONEncoder().encode(mcpServers)
            defaults.set(data, forKey: Keys.mcpServers)
        } catch {
            Log.storage.error("MCP 서버 설정 저장 실패: \(error, privacy: .public)")
        }
    }

    func addMCPServer(_ config: MCPServerConfig) {
        mcpServers.append(config)
    }

    func removeMCPServer(id: UUID) {
        mcpServers.removeAll { $0.id == id }
    }

    func updateMCPServer(_ config: MCPServerConfig) {
        if let index = mcpServers.firstIndex(where: { $0.id == config.id }) {
            mcpServers[index] = config
        }
    }

    // MARK: - API Keys

    var apiKey: String {
        get { keychainService.load(account: "openai") ?? "" }
        set {
            keychainService.save(account: "openai", value: newValue)
            objectWillChange.send()
        }
    }

    var anthropicApiKey: String {
        get { keychainService.load(account: "anthropic") ?? "" }
        set {
            keychainService.save(account: "anthropic", value: newValue)
            objectWillChange.send()
        }
    }

    var zaiApiKey: String {
        get { keychainService.load(account: "zai") ?? "" }
        set {
            keychainService.save(account: "zai", value: newValue)
            objectWillChange.send()
        }
    }

    var tavilyApiKey: String {
        get { keychainService.load(account: "tavily") ?? "" }
        set {
            keychainService.save(account: "tavily", value: newValue)
            objectWillChange.send()
        }
    }

    var falaiApiKey: String {
        get { keychainService.load(account: "falai") ?? "" }
        set {
            keychainService.save(account: "falai", value: newValue)
            objectWillChange.send()
        }
    }

    func apiKey(for provider: LLMProvider) -> String {
        switch provider {
        case .openai: apiKey
        case .anthropic: anthropicApiKey
        case .zai: zaiApiKey
        }
    }

    // MARK: - Telegram

    var telegramBotToken: String {
        get { keychainService.load(account: "telegram_bot_token") ?? "" }
        set {
            keychainService.save(account: "telegram_bot_token", value: newValue)
            objectWillChange.send()
        }
    }

    // MARK: - Claude Code UI

    var claudeUIToken: String {
        get { keychainService.load(account: "claude_ui_token") ?? "" }
        set {
            keychainService.save(account: "claude_ui_token", value: newValue)
            objectWillChange.send()
        }
    }

    // MARK: - Build Instructions

    func buildInstructions() -> String {
        buildInstructions(currentUserName: nil, currentUserId: nil, recentSummaries: nil)
    }

    func buildInstructions(currentUserName: String?, currentUserId: UUID?, recentSummaries: String?) -> String {
        let profiles = contextService.loadProfiles()
        let hasProfiles = !profiles.isEmpty
        let agentName = activeAgentName

        var parts: [String] = []

        // 1) system_prompt.md — 앱 레벨 기본 규칙
        let basePrompt = contextService.loadBaseSystemPrompt()
        if !basePrompt.isEmpty {
            parts.append(basePrompt)
        }

        // 2) agents/{name}/persona.md — 에이전트 페르소나
        // 2) agents/{name}/persona.md — 에이전트 페르소나
        if let workspaceId = currentWorkspaceId {
            let persona = contextService.loadAgentPersona(workspaceId: workspaceId, agentName: agentName)
            if !persona.isEmpty {
                parts.append(persona)
            }
        } else {
            // 워크스페이스 없는 경우 (fallback)
            let persona = contextService.loadAgentPersona(agentName: agentName)
            if !persona.isEmpty {
                parts.append(persona)
            }
        }



        // 3) 현재 날짜/시각 정보
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 EEEE a h시 m분"
        parts.append("현재 시각: \(formatter.string(from: Date()))")

        if hasProfiles {
            // 다중 사용자 모드

            // 4) 사용자 식별 정보
            if let userName = currentUserName {
                parts.append("현재 대화 상대: \(userName)")
            } else {
                let profileNames = profiles.map { $0.name }.joined(separator: ", ")
                parts.append("현재 대화 상대가 확인되지 않았습니다. 등록된 가족 구성원: \(profileNames). 대화 초반에 자연스럽게 누구인지 파악하고 set_current_user를 호출해주세요.")
            }

            // 5) family.md -> workspace memory (공유 기억)
            if let workspaceId = currentWorkspaceId {
                let workspaceMemory = contextService.loadWorkspaceMemory(workspaceId: workspaceId)
                if !workspaceMemory.isEmpty {
                    parts.append("워크스페이스 공유 기억:\n\n\(workspaceMemory)")
                }
            } else {
                let familyMemory = contextService.loadFamilyMemory()
                if !familyMemory.isEmpty {
                    parts.append("가족 공유 기억:\n\n\(familyMemory)")
                }
            }

            // 6) agents/{name}/memory.md — 에이전트 기억
            if let workspaceId = currentWorkspaceId {
                let agentMemory = contextService.loadAgentMemory(workspaceId: workspaceId, agentName: agentName)
                if !agentMemory.isEmpty {
                    parts.append("에이전트 기억:\n\n\(agentMemory)")
                }
            } else {
                let agentMemory = contextService.loadAgentMemory(agentName: agentName)
                if !agentMemory.isEmpty {
                    parts.append("에이전트 기억:\n\n\(agentMemory)")
                }
            }
            
            // 7) memory/{userId}.md — 개인 기억
            if let userId = currentUserId {
                let userMemory = contextService.loadUserMemory(userId: userId)
                if !userMemory.isEmpty {
                    parts.append("\(currentUserName ?? "사용자")의 개인 기억:\n\n\(userMemory)")
                }
            }

            // 기억 관리 안내
            parts.append("대화 중 중요한 정보를 알게 되면 save_memory 도구로 즉시 저장하세요. 기존 기억을 수정하거나 삭제할 때는 update_memory를 사용하세요. 가족 전체에 해당하는 정보는 scope='workspace', 개인 정보는 scope='personal'로 저장하세요.")
        } else {
            // 레거시/단일 사용자 모드 (임시)
            
            // 에이전트 기억
            if let workspaceId = currentWorkspaceId {
                let agentMemory = contextService.loadAgentMemory(workspaceId: workspaceId, agentName: agentName)
                if !agentMemory.isEmpty {
                    parts.append("에이전트 기억:\n\n\(agentMemory)")
                }
            } else {
                let agentMemory = contextService.loadAgentMemory(agentName: agentName)
                if !agentMemory.isEmpty {
                    parts.append("에이전트 기억:\n\n\(agentMemory)")
                }
            }
        }

        // 8) 최근 대화 요약
        if let summaries = recentSummaries, !summaries.isEmpty {
            parts.append("최근 대화 요약:\n\n\(summaries)")
        }

        return parts.isEmpty ? "You are a helpful assistant. Respond in Korean." : parts.joined(separator: "\n\n")
    }

    // MARK: - Migration

    private static func migrateToFileBasedContext(defaults: UserDefaults, contextService: ContextServiceProtocol) {
        let migrationKey = "settings.migratedToFileContext"
        if !defaults.bool(forKey: migrationKey) {
            if let oldInstructions = defaults.string(forKey: "settings.instructions"),
               !oldInstructions.isEmpty,
               contextService.loadSystem().isEmpty {
                contextService.saveSystem(oldInstructions)
            }
            defaults.set(true, forKey: migrationKey)
        }
    }
}
