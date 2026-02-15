import Foundation

/// Per-exchange LLM usage and timing metrics for local diagnostics.
struct ExchangeMetrics: Codable, Sendable {
    let provider: String
    let model: String
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let firstByteLatency: TimeInterval?
    let totalLatency: TimeInterval
    let timestamp: Date
    let wasFallback: Bool
    /// Agent name that generated this exchange. Backward compatible (defaults to "도치").
    let agentName: String

    init(
        provider: String,
        model: String,
        inputTokens: Int?,
        outputTokens: Int?,
        totalTokens: Int?,
        firstByteLatency: TimeInterval?,
        totalLatency: TimeInterval,
        timestamp: Date,
        wasFallback: Bool,
        agentName: String = "도치"
    ) {
        self.provider = provider
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.firstByteLatency = firstByteLatency
        self.totalLatency = totalLatency
        self.timestamp = timestamp
        self.wasFallback = wasFallback
        self.agentName = agentName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(String.self, forKey: .provider)
        model = try container.decode(String.self, forKey: .model)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens)
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens)
        totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens)
        firstByteLatency = try container.decodeIfPresent(TimeInterval.self, forKey: .firstByteLatency)
        totalLatency = try container.decode(TimeInterval.self, forKey: .totalLatency)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        wasFallback = try container.decode(Bool.self, forKey: .wasFallback)
        agentName = try container.decodeIfPresent(String.self, forKey: .agentName) ?? "도치"
    }

    var totalTokensDisplay: String {
        if let total = totalTokens {
            return "\(total)"
        }
        let input = inputTokens ?? 0
        let output = outputTokens ?? 0
        return input + output > 0 ? "\(input + output)" : "N/A"
    }
}
