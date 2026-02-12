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

    var totalTokensDisplay: String {
        if let total = totalTokens {
            return "\(total)"
        }
        let input = inputTokens ?? 0
        let output = outputTokens ?? 0
        return input + output > 0 ? "\(input + output)" : "N/A"
    }
}
