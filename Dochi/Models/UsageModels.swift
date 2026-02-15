import Foundation

// MARK: - UsageEntry

/// A single LLM usage record within a day.
struct UsageEntry: Codable, Sendable {
    let provider: String
    let model: String
    let agentName: String
    let inputTokens: Int
    let outputTokens: Int
    let exchangeCount: Int
    let estimatedCostUSD: Double
    let timestamp: Date
}

// MARK: - DailyUsageRecord

/// Aggregated usage records for a single day.
struct DailyUsageRecord: Codable, Sendable, Identifiable {
    let date: String  // yyyy-MM-dd
    var entries: [UsageEntry]

    var id: String { date }

    var totalInputTokens: Int {
        entries.reduce(0) { $0 + $1.inputTokens }
    }

    var totalOutputTokens: Int {
        entries.reduce(0) { $0 + $1.outputTokens }
    }

    var totalExchanges: Int {
        entries.reduce(0) { $0 + $1.exchangeCount }
    }

    var totalCostUSD: Double {
        entries.reduce(0.0) { $0 + $1.estimatedCostUSD }
    }
}

// MARK: - MonthlyUsageFile

/// File format for monthly usage storage: `{yyyy-MM}.json`.
struct MonthlyUsageFile: Codable, Sendable {
    var days: [DailyUsageRecord]
}

// MARK: - MonthlyUsageSummary

/// Aggregated summary for a month.
struct MonthlyUsageSummary: Sendable {
    let month: String  // yyyy-MM
    let totalExchanges: Int
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let totalCostUSD: Double
    let days: [DailyUsageRecord]

    /// Cost breakdown by model.
    var costByModel: [String: Double] {
        var result: [String: Double] = [:]
        for day in days {
            for entry in day.entries {
                result[entry.model, default: 0] += entry.estimatedCostUSD
            }
        }
        return result
    }

    /// Cost breakdown by agent.
    var costByAgent: [String: Double] {
        var result: [String: Double] = [:]
        for day in days {
            for entry in day.entries {
                result[entry.agentName, default: 0] += entry.estimatedCostUSD
            }
        }
        return result
    }
}

// MARK: - ModelPricingTable

/// Hardcoded per-model pricing (USD per 1M tokens).
enum ModelPricingTable {
    struct Pricing: Sendable {
        let inputPerMillion: Double
        let outputPerMillion: Double
    }

    static let prices: [String: Pricing] = [
        // OpenAI
        "gpt-4o": Pricing(inputPerMillion: 2.50, outputPerMillion: 10.00),
        "gpt-4o-mini": Pricing(inputPerMillion: 0.15, outputPerMillion: 0.60),
        "gpt-4-turbo": Pricing(inputPerMillion: 10.00, outputPerMillion: 30.00),
        "gpt-4": Pricing(inputPerMillion: 30.00, outputPerMillion: 60.00),
        "gpt-3.5-turbo": Pricing(inputPerMillion: 0.50, outputPerMillion: 1.50),
        "o1": Pricing(inputPerMillion: 15.00, outputPerMillion: 60.00),
        "o1-mini": Pricing(inputPerMillion: 3.00, outputPerMillion: 12.00),
        "o3-mini": Pricing(inputPerMillion: 1.10, outputPerMillion: 4.40),
        // Anthropic
        "claude-3-5-sonnet-20241022": Pricing(inputPerMillion: 3.00, outputPerMillion: 15.00),
        "claude-3-5-haiku-20241022": Pricing(inputPerMillion: 0.80, outputPerMillion: 4.00),
        "claude-3-opus-20240229": Pricing(inputPerMillion: 15.00, outputPerMillion: 75.00),
        "claude-sonnet-4-20250514": Pricing(inputPerMillion: 3.00, outputPerMillion: 15.00),
        "claude-opus-4-20250514": Pricing(inputPerMillion: 15.00, outputPerMillion: 75.00),
        // Z.AI
        "zai-mini-1": Pricing(inputPerMillion: 0.20, outputPerMillion: 0.80),
    ]

    /// Estimate cost for given token counts and model.
    /// Returns 0.0 for unknown/local models.
    static func estimateCost(model: String, inputTokens: Int, outputTokens: Int) -> Double {
        // Local models (Ollama, LM Studio) are free
        guard let pricing = prices[model] else {
            // Try prefix matching for versioned model names
            if let match = prices.first(where: { model.hasPrefix($0.key) || $0.key.hasPrefix(model) }) {
                let p = match.value
                return (Double(inputTokens) * p.inputPerMillion + Double(outputTokens) * p.outputPerMillion) / 1_000_000.0
            }
            return 0.0
        }
        return (Double(inputTokens) * pricing.inputPerMillion + Double(outputTokens) * pricing.outputPerMillion) / 1_000_000.0
    }
}
