import Foundation
import SwiftUI

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

    // Memory compression
    @Published var contextAutoCompress: Bool {
        didSet { UserDefaults.standard.set(contextAutoCompress, forKey: Keys.contextAutoCompress) }
    }
    @Published var contextMaxSize: Int {
        didSet { UserDefaults.standard.set(contextMaxSize, forKey: Keys.contextMaxSize) }
    }

    private enum Keys {
        static let wakeWordEnabled = "settings.wakeWordEnabled"
        static let wakeWord = "settings.wakeWord"
        static let llmProvider = "settings.llmProvider"
        static let llmModel = "settings.llmModel"
        static let supertonicVoice = "settings.supertonicVoice"
        static let ttsSpeed = "settings.ttsSpeed"
        static let ttsDiffusionSteps = "settings.ttsDiffusionSteps"
        static let contextAutoCompress = "settings.contextAutoCompress"
        static let contextMaxSize = "settings.contextMaxSize"
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
        self.wakeWord = defaults.string(forKey: Keys.wakeWord) ?? "도치야"

        let providerRaw = defaults.string(forKey: Keys.llmProvider) ?? LLMProvider.openai.rawValue
        let provider = LLMProvider(rawValue: providerRaw) ?? .openai
        self.llmProvider = provider
        self.llmModel = defaults.string(forKey: Keys.llmModel) ?? provider.models.first ?? ""

        let voiceRaw = defaults.string(forKey: Keys.supertonicVoice) ?? SupertonicVoice.F1.rawValue
        self.supertonicVoice = SupertonicVoice(rawValue: voiceRaw) ?? .F1
        self.ttsSpeed = defaults.object(forKey: Keys.ttsSpeed) as? Float ?? 1.15
        self.ttsDiffusionSteps = defaults.object(forKey: Keys.ttsDiffusionSteps) as? Int ?? 10

        self.contextAutoCompress = defaults.object(forKey: Keys.contextAutoCompress) as? Bool ?? true
        self.contextMaxSize = defaults.object(forKey: Keys.contextMaxSize) as? Int ?? 15360
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

    func apiKey(for provider: LLMProvider) -> String {
        switch provider {
        case .openai: apiKey
        case .anthropic: anthropicApiKey
        case .zai: zaiApiKey
        }
    }

    // MARK: - Build Instructions

    func buildInstructions() -> String {
        var parts: [String] = []

        let systemPrompt = contextService.loadSystem()
        if !systemPrompt.isEmpty {
            parts.append(systemPrompt)
        }

        let userMemory = contextService.loadMemory()
        if !userMemory.isEmpty {
            parts.append("다음은 사용자에 대해 기억하고 있는 정보입니다:\n\n\(userMemory)")
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
