import Foundation

enum AgentBackendKind: String, CaseIterable, Identifiable, Sendable {
    case native
    case hermesRemote

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .native: "기기 내 Swift 에이전트"
        case .hermesRemote: "Hermes 원격 브리지"
        }
    }
}

enum NativeModelProviderKind: String, CaseIterable, Identifiable, Sendable {
    case anthropic
    case openAI
    case gemini
    case openAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        case .gemini: "Google Gemini"
        case .openAICompatible: "OpenAI 호환"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: "claude-sonnet-5"
        case .openAI: "gpt-5.6"
        case .gemini: "gemini-3.5-flash"
        case .openAICompatible: ""
        }
    }

    var keychainAccount: String { "agent-provider-\(rawValue)-api-key" }
}
