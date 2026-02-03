import Foundation

// MARK: - App Mode

enum AppMode: String, CaseIterable, Codable {
    case text = "text"
    case realtime = "realtime"

    var displayName: String {
        switch self {
        case .text: "텍스트"
        case .realtime: "리얼타임"
        }
    }
}

// MARK: - LLM Provider

enum LLMProvider: String, CaseIterable, Codable {
    case openai = "openai"
    case anthropic = "anthropic"
    case zai = "zai"

    var displayName: String {
        switch self {
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        case .zai: "Z.AI"
        }
    }

    var models: [String] {
        switch self {
        case .openai: ["gpt-4o", "gpt-4o-mini"]
        case .anthropic: ["claude-sonnet-4-20250514", "claude-haiku-4-20250414"]
        case .zai: ["glm-4.7"]
        }
    }

    var apiURL: URL {
        switch self {
        case .openai: URL(string: "https://api.openai.com/v1/chat/completions")!
        case .anthropic: URL(string: "https://api.anthropic.com/v1/messages")!
        case .zai: URL(string: "https://api.z.ai/api/coding/paas/v4/chat/completions")!
        }
    }

    var keychainAccount: String {
        switch self {
        case .openai: "openai"
        case .anthropic: "anthropic"
        case .zai: "zai"
        }
    }
}

// MARK: - Supertonic Voice

enum SupertonicVoice: String, CaseIterable, Codable {
    case F1, F2, F3, F4, F5
    case M1, M2, M3, M4, M5

    var displayName: String { rawValue }
}
