import Foundation

enum LLMProvider: String, Codable, CaseIterable, Sendable {
    case openai
    case anthropic
    case zai

    var displayName: String {
        switch self {
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        case .zai: "Z.AI"
        }
    }

    var models: [String] {
        switch self {
        case .openai: ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "o3-mini"]
        case .anthropic: ["claude-sonnet-4-5-20250514", "claude-3-5-haiku-20241022"]
        case .zai: ["glm-5", "glm-4.7"]
        }
    }

    var apiURL: URL {
        switch self {
        case .openai: URL(string: "https://api.openai.com/v1/chat/completions")!
        case .anthropic: URL(string: "https://api.anthropic.com/v1/messages")!
        case .zai: URL(string: "https://api.z.ai/api/paas/v4/chat/completions")!
        }
    }

    var keychainAccount: String {
        rawValue
    }

    /// Find the provider that offers a given model name, or nil if unknown.
    static func provider(forModel model: String) -> LLMProvider? {
        allCases.first { $0.models.contains(model) }
    }

    /// Context window size (max input tokens) per model.
    func contextWindowTokens(for model: String) -> Int {
        switch self {
        case .openai:
            switch model {
            case "gpt-4o", "gpt-4o-mini", "gpt-4-turbo":
                return 128_000
            case "o3-mini":
                return 200_000
            default:
                return 128_000
            }
        case .anthropic:
            return 200_000
        case .zai:
            return 200_000
        }
    }
}
