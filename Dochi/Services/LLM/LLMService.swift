import Foundation
import os

@MainActor
final class LLMService: LLMServiceProtocol {
    private var currentTask: Task<Void, Never>?

    func send(
        messages: [Message],
        systemPrompt: String,
        model: String,
        provider: LLMProvider,
        tools: [[String: Any]]?,
        onPartial: @MainActor @Sendable (String) -> Void
    ) async throws -> LLMResponse {
        // TODO: Phase 1 — implement provider adapters + SSE streaming
        Log.llm.info("LLMService.send called (stub)")
        return .text("LLM 서비스가 아직 구현되지 않았습니다.")
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        Log.llm.info("LLM request cancelled")
    }
}
