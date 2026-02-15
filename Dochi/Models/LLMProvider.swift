import Foundation

enum LLMProvider: String, Codable, CaseIterable, Sendable {
    case openai
    case anthropic
    case zai
    case ollama
    case lmStudio

    var displayName: String {
        switch self {
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        case .zai: "Z.AI"
        case .ollama: "Ollama"
        case .lmStudio: "LM Studio"
        }
    }

    var models: [String] {
        switch self {
        case .openai: ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "o3-mini"]
        case .anthropic: ["claude-sonnet-4-5-20250514", "claude-3-5-haiku-20241022"]
        case .zai: ["glm-5", "glm-4.7"]
        case .ollama: [] // Dynamic — fetched from running Ollama instance
        case .lmStudio: [] // Dynamic — fetched from running LM Studio instance
        }
    }

    var apiURL: URL {
        switch self {
        case .openai: URL(string: "https://api.openai.com/v1/chat/completions")!
        case .anthropic: URL(string: "https://api.anthropic.com/v1/messages")!
        case .zai: URL(string: "https://api.z.ai/api/paas/v4/chat/completions")!
        case .ollama: URL(string: "http://localhost:11434/v1/chat/completions")!
        case .lmStudio: URL(string: "http://localhost:1234/v1/chat/completions")!
        }
    }

    var keychainAccount: String {
        rawValue
    }

    /// Whether this provider requires an API key.
    var requiresAPIKey: Bool {
        switch self {
        case .ollama, .lmStudio: false
        default: true
        }
    }

    /// Whether this provider runs locally (no internet required).
    var isLocal: Bool {
        switch self {
        case .ollama, .lmStudio: true
        default: false
        }
    }

    /// Find the provider that offers a given model name, or nil if unknown.
    static func provider(forModel model: String) -> LLMProvider? {
        allCases.first { $0.models.contains(model) }
    }

    /// Cloud providers (require internet).
    static var cloudProviders: [LLMProvider] {
        allCases.filter { !$0.isLocal }
    }

    /// Local providers (run on localhost).
    static var localProviders: [LLMProvider] {
        allCases.filter { $0.isLocal }
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
        case .ollama, .lmStudio:
            return 128_000 // Conservative default; actual varies by model
        }
    }
}

// MARK: - Local Model Info

/// Metadata about a locally available model (from Ollama or LM Studio).
struct LocalModelInfo: Codable, Identifiable, Sendable {
    let name: String
    let size: Int64            // Model file size in bytes
    let parameterSize: String? // e.g. "7B", "13B"
    let quantization: String?  // e.g. "Q4_K_M"
    let family: String?        // e.g. "llama", "mistral"
    let supportsTools: Bool    // Whether this model supports function calling

    var id: String { name }

    /// Human-readable file size string.
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    /// Compact metadata display string (e.g. "7B Q4_K_M 4.1 GB").
    var compactDescription: String {
        var parts: [String] = []
        if let parameterSize { parts.append(parameterSize) }
        if let quantization { parts.append(quantization) }
        if size > 0 { parts.append(formattedSize) }
        return parts.joined(separator: " ")
    }
}

// MARK: - Local Server Status

/// Connection status for a local LLM server (Ollama or LM Studio).
enum LocalServerStatus: String, Sendable {
    case unknown
    case connected
    case disconnected
    case checking
}
