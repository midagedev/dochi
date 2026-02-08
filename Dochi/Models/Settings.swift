import Foundation
import SwiftUI
import os

@MainActor
final class AppSettings: ObservableObject {
    @Published var wakeWordEnabled: Bool {
        didSet { UserDefaults.standard.set(wakeWordEnabled, forKey: Keys.wakeWordEnabled) }
    }
    @Published var wakeWord: String {
        didSet { UserDefaults.standard.set(wakeWord, forKey: Keys.wakeWord) }
    }

    // LLM settings
    @Published var llmProvider: LLMProvider {
        didSet {
            UserDefaults.standard.set(llmProvider.rawValue, forKey: Keys.llmProvider)
            if !llmProvider.models.contains(llmModel) {
                llmModel = llmProvider.models.first ?? ""
            }
        }
    }
    @Published var llmModel: String {
        didSet { UserDefaults.standard.set(llmModel, forKey: Keys.llmModel) }
    }

    // TTS settings
    @Published var supertonicVoice: SupertonicVoice {
        didSet { UserDefaults.standard.set(supertonicVoice.rawValue, forKey: Keys.supertonicVoice) }
    }
    @Published var ttsSpeed: Float {
        didSet { UserDefaults.standard.set(ttsSpeed, forKey: Keys.ttsSpeed) }
    }
    @Published var ttsDiffusionSteps: Int {
        didSet { UserDefaults.standard.set(ttsDiffusionSteps, forKey: Keys.ttsDiffusionSteps) }
    }

    // Display settings
    @Published var chatFontSize: Double {
        didSet { UserDefaults.standard.set(chatFontSize, forKey: Keys.chatFontSize) }
    }

    // STT settings
    @Published var sttSilenceTimeout: Double {
        didSet { UserDefaults.standard.set(sttSilenceTimeout, forKey: Keys.sttSilenceTimeout) }
    }

    // Memory compression
    @Published var contextAutoCompress: Bool {
        didSet { UserDefaults.standard.set(contextAutoCompress, forKey: Keys.contextAutoCompress) }
    }
    @Published var contextMaxSize: Int {
        didSet { UserDefaults.standard.set(contextMaxSize, forKey: Keys.contextMaxSize) }
    }

    // MCP servers
    @Published var mcpServers: [MCPServerConfig] {
        didSet { saveMCPServers() }
    }

    // User profiles
    @Published var defaultUserId: UUID? {
        didSet {
            if let id = defaultUserId {
                UserDefaults.standard.set(id.uuidString, forKey: Keys.defaultUserId)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.defaultUserId)
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
    }

    // MARK: - Dependencies

    private let keychainService: KeychainServiceProtocol
    let contextService: ContextServiceProtocol

    init(
        keychainService: KeychainServiceProtocol = KeychainService(),
        contextService: ContextServiceProtocol = ContextService()
    ) {
        self.keychainService = keychainService
        self.contextService = contextService

        let defaults = UserDefaults.standard

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

        // Default user
        if let idString = defaults.string(forKey: Keys.defaultUserId),
           let id = UUID(uuidString: idString) {
            self.defaultUserId = id
        } else {
            self.defaultUserId = nil
        }
    }

    // MARK: - MCP Servers

    private func saveMCPServers() {
        do {
            let data = try JSONEncoder().encode(mcpServers)
            UserDefaults.standard.set(data, forKey: Keys.mcpServers)
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

    // MARK: - Build Instructions

    func buildInstructions() -> String {
        buildInstructions(currentUserName: nil, currentUserId: nil, recentSummaries: nil)
    }

    func buildInstructions(currentUserName: String?, currentUserId: UUID?, recentSummaries: String?) -> String {
        let profiles = contextService.loadProfiles()
        let hasProfiles = !profiles.isEmpty

        var parts: [String] = []

        // 1) system.md — 공유 페르소나
        let systemPrompt = contextService.loadSystem()
        if !systemPrompt.isEmpty {
            parts.append(systemPrompt)
        }

        // 현재 날짜/시각 정보
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 EEEE a h시 m분"
        parts.append("현재 시각: \(formatter.string(from: Date()))")

        if hasProfiles {
            // 다중 사용자 모드

            // 사용자 식별 정보
            if let userName = currentUserName {
                parts.append("현재 대화 상대: \(userName)")
            } else {
                let profileNames = profiles.map { $0.name }.joined(separator: ", ")
                parts.append("현재 대화 상대가 확인되지 않았습니다. 등록된 가족 구성원: \(profileNames). 대화 초반에 자연스럽게 누구인지 파악하고 set_current_user를 호출해주세요.")
            }

            // 2) family.md — 가족 공유 기억
            let familyMemory = contextService.loadFamilyMemory()
            if !familyMemory.isEmpty {
                parts.append("가족 공유 기억:\n\n\(familyMemory)")
            }

            // 3) memory/{userId}.md — 개인 기억
            if let userId = currentUserId {
                let userMemory = contextService.loadUserMemory(userId: userId)
                if !userMemory.isEmpty {
                    parts.append("\(currentUserName ?? "사용자")의 개인 기억:\n\n\(userMemory)")
                }
            }

            // 기억 관리 안내
            parts.append("대화 중 중요한 정보를 알게 되면 save_memory 도구로 즉시 저장하세요. 기존 기억을 수정하거나 삭제할 때는 update_memory를 사용하세요. 가족 전체에 해당하는 정보는 scope='family', 개인 정보는 scope='personal'로 저장하세요.")
        } else {
            // 레거시 단일 사용자 모드 (프로필 없음)
            let userMemory = contextService.loadMemory()
            if !userMemory.isEmpty {
                parts.append("다음은 사용자에 대해 기억하고 있는 정보입니다:\n\n\(userMemory)")
            }
        }

        // 4) 최근 대화 요약
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
        contextService.migrateIfNeeded()
    }
}
