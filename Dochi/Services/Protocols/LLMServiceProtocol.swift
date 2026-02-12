import Foundation

@MainActor
protocol LLMServiceProtocol {
    func send(
        messages: [Message],
        systemPrompt: String,
        model: String,
        provider: LLMProvider,
        tools: [[String: Any]]?,
        onPartial: @MainActor @Sendable (String) -> Void
    ) async throws -> LLMResponse

    func cancel()
}
