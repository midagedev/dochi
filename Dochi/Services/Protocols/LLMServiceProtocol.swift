import Foundation

@MainActor
protocol LLMServiceProtocol {
    /// Metrics from the most recent completed exchange.
    var lastMetrics: ExchangeMetrics? { get }

    func send(
        messages: [Message],
        systemPrompt: String,
        model: String,
        provider: LLMProvider,
        apiKey: String,
        tools: [[String: Any]]?,
        onPartial: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> LLMResponse

    func cancel()
}
