import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @Published var instructions: String {
        didSet { UserDefaults.standard.set(instructions, forKey: Keys.instructions) }
    }
    @Published var voice: String {
        didSet { UserDefaults.standard.set(voice, forKey: Keys.voice) }
    }
    @Published var wakeWordEnabled: Bool {
        didSet { UserDefaults.standard.set(wakeWordEnabled, forKey: Keys.wakeWordEnabled) }
    }
    @Published var wakeWord: String {
        didSet { UserDefaults.standard.set(wakeWord, forKey: Keys.wakeWord) }
    }

    // Dual mode settings
    @Published var appMode: AppMode {
        didSet { UserDefaults.standard.set(appMode.rawValue, forKey: Keys.appMode) }
    }
    @Published var llmProvider: LLMProvider {
        didSet {
            UserDefaults.standard.set(llmProvider.rawValue, forKey: Keys.llmProvider)
            // 제공자 변경 시 해당 제공자의 첫 번째 모델로 초기화
            if !llmProvider.models.contains(llmModel) {
                llmModel = llmProvider.models.first ?? ""
            }
        }
    }
    @Published var llmModel: String {
        didSet { UserDefaults.standard.set(llmModel, forKey: Keys.llmModel) }
    }
    @Published var supertonicVoice: SupertonicVoice {
        didSet { UserDefaults.standard.set(supertonicVoice.rawValue, forKey: Keys.supertonicVoice) }
    }
    @Published var ttsSpeed: Float {
        didSet { UserDefaults.standard.set(ttsSpeed, forKey: Keys.ttsSpeed) }
    }
    @Published var ttsDiffusionSteps: Int {
        didSet { UserDefaults.standard.set(ttsDiffusionSteps, forKey: Keys.ttsDiffusionSteps) }
    }

    // Context compression
    @Published var contextAutoCompress: Bool {
        didSet { UserDefaults.standard.set(contextAutoCompress, forKey: Keys.contextAutoCompress) }
    }
    @Published var contextMaxSize: Int {
        didSet { UserDefaults.standard.set(contextMaxSize, forKey: Keys.contextMaxSize) }
    }

    static let availableVoices = ["alloy", "ash", "ballad", "coral", "echo", "nova", "sage", "shimmer", "verse"]

    private enum Keys {
        static let instructions = "settings.instructions"
        static let voice = "settings.voice"
        static let wakeWordEnabled = "settings.wakeWordEnabled"
        static let wakeWord = "settings.wakeWord"
        static let appMode = "settings.appMode"
        static let llmProvider = "settings.llmProvider"
        static let llmModel = "settings.llmModel"
        static let supertonicVoice = "settings.supertonicVoice"
        static let ttsSpeed = "settings.ttsSpeed"
        static let ttsDiffusionSteps = "settings.ttsDiffusionSteps"
        static let contextAutoCompress = "settings.contextAutoCompress"
        static let contextMaxSize = "settings.contextMaxSize"
    }

    init() {
        let defaults = UserDefaults.standard
        self.instructions = defaults.string(forKey: Keys.instructions) ?? ""
        self.voice = defaults.string(forKey: Keys.voice) ?? "nova"
        self.wakeWordEnabled = defaults.bool(forKey: Keys.wakeWordEnabled)
        self.wakeWord = defaults.string(forKey: Keys.wakeWord) ?? "도치야"

        // Dual mode defaults
        let modeRaw = defaults.string(forKey: Keys.appMode) ?? AppMode.realtime.rawValue
        self.appMode = AppMode(rawValue: modeRaw) ?? .realtime

        let providerRaw = defaults.string(forKey: Keys.llmProvider) ?? LLMProvider.openai.rawValue
        let provider = LLMProvider(rawValue: providerRaw) ?? .openai
        self.llmProvider = provider
        self.llmModel = defaults.string(forKey: Keys.llmModel) ?? provider.models.first ?? ""

        let voiceRaw = defaults.string(forKey: Keys.supertonicVoice) ?? SupertonicVoice.F1.rawValue
        self.supertonicVoice = SupertonicVoice(rawValue: voiceRaw) ?? .F1
        self.ttsSpeed = defaults.object(forKey: Keys.ttsSpeed) as? Float ?? 1.15
        self.ttsDiffusionSteps = defaults.object(forKey: Keys.ttsDiffusionSteps) as? Int ?? 10

        // Context compression (default: enabled, max 15KB)
        self.contextAutoCompress = defaults.object(forKey: Keys.contextAutoCompress) as? Bool ?? true
        self.contextMaxSize = defaults.object(forKey: Keys.contextMaxSize) as? Int ?? 15360
    }

    // MARK: - API Keys

    var apiKey: String {
        get { KeychainService.load(account: "openai") ?? "" }
        set {
            KeychainService.save(account: "openai", value: newValue)
            objectWillChange.send()
        }
    }

    var anthropicApiKey: String {
        get { KeychainService.load(account: "anthropic") ?? "" }
        set {
            KeychainService.save(account: "anthropic", value: newValue)
            objectWillChange.send()
        }
    }

    var zaiApiKey: String {
        get { KeychainService.load(account: "zai") ?? "" }
        set {
            KeychainService.save(account: "zai", value: newValue)
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

        // 기본 인스트럭션
        if !instructions.isEmpty {
            parts.append(instructions)
        }

        // 장기 컨텍스트 (context.md)
        let longTermContext = ContextService.load()
        if !longTermContext.isEmpty {
            parts.append("다음은 사용자에 대해 기억하고 있는 정보입니다:\n\n\(longTermContext)")
        }

        return parts.isEmpty ? "You are a helpful assistant. Respond in Korean." : parts.joined(separator: "\n\n")
    }
}
