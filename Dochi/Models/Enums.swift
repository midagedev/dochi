import Foundation

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
        case .openai: ["gpt-4.1", "gpt-4.1-mini", "gpt-4.1-nano", "o3", "o4-mini", "gpt-4o", "gpt-4o-mini"]
        case .anthropic: ["claude-opus-4-6", "claude-sonnet-4-5-20250929", "claude-haiku-4-5-20251001"]
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
