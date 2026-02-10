import Foundation

struct ContextUsageInfo {
    let usedTokens: Int
    let limitTokens: Int
    let percent: Double // 0.0 ... 1.0
}

enum ModelContextEstimator {
    // Conservative defaults; can be tuned without UI changes
    private static let defaultContextTokens = 128_000

    // Approximate average characters per token by provider
    // Note: Korean/CJK generally yields fewer chars per token than English.
    private static func avgCharsPerToken(for provider: LLMProvider) -> Double {
        switch provider {
        case .openai: return 3.5
        case .anthropic: return 3.5
        case .zai: return 3.5
        }
    }

    // Known context windows for common models; fallback to defaultContextTokens.
    private static func knownLimit(for provider: LLMProvider, model: String) -> Int {
        let m = model.lowercased()
        switch provider {
        case .openai:
            // Broad 128k default for recent 4.x/4o family.
            if m.contains("gpt-4.1") { return 128_000 }
            if m.contains("gpt-4o") { return 128_000 }
            if m.contains("o4") { return 128_000 }
            if m.contains("o3") { return 128_000 }
            return defaultContextTokens
        case .anthropic:
            // Claude 4.x (opus/sonnet/haiku 4.5) official: 200K; 1M beta via special header not used here.
            if m.contains("opus") || m.contains("sonnet") || m.contains("haiku") { return 200_000 }
            return 200_000
        case .zai:
            // GLM-4.7 confirmed 200K context window
            if m.contains("glm-4.7") { return 200_000 }
            // Fallback for other versions (can be adjusted as info becomes available)
            return defaultContextTokens
        }
    }

    static func limitTokens(provider: LLMProvider, model: String) -> Int {
        knownLimit(for: provider, model: model)
    }

    static func estimateUsedTokens(systemPrompt: String, messages: [Message], provider: LLMProvider) -> Int {
        // Text-only approximation: count system prompt + message text.
        // We exclude tool call JSON and images for simplicity.
        let textChars = systemPrompt.count + messages.reduce(0) { acc, msg in
            acc + msg.content.count
        }
        let avg = max(1.0, avgCharsPerToken(for: provider))
        return Int(ceil(Double(textChars) / avg))
    }

    static func usageInfo(systemPrompt: String, messages: [Message], provider: LLMProvider, model: String) -> ContextUsageInfo {
        let limit = limitTokens(provider: provider, model: model)
        let used = estimateUsedTokens(systemPrompt: systemPrompt, messages: messages, provider: provider)
        let pct = limit > 0 ? min(1.0, Double(used) / Double(limit)) : 0.0
        return ContextUsageInfo(usedTokens: used, limitTokens: limit, percent: pct)
    }
}
