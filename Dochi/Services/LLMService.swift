import Foundation
import Combine
import os

@MainActor
final class LLMService: ObservableObject {
    @Published var partialResponse: String = ""
    @Published var error: String?
    @Published var isStreaming: Bool = false

    var onResponseComplete: ((String) -> Void)?
    var onSentenceReady: ((String) -> Void)?
    var onToolCallsReceived: (([ToolCall]) -> Void)?

    private var streamTask: Task<Void, Never>?
    private let sentenceChunker = SentenceChunker()
    private var pendingToolCalls: [ToolCall] = []

    // MARK: - Public

    func sendMessage(
        messages: [Message],
        systemPrompt: String,
        provider: LLMProvider,
        model: String,
        apiKey: String,
        tools: [[String: Any]]? = nil,
        toolResults: [ToolResult]? = nil
    ) {
        guard !apiKey.isEmpty else {
            error = "\(provider.displayName) API 키를 설정해주세요."
            return
        }
        cancel()
        partialResponse = ""
        sentenceChunker.reset()
        pendingToolCalls = []
        error = nil
        isStreaming = true

        Log.llm.info("요청 시작: provider=\(provider.displayName, privacy: .public), model=\(model, privacy: .public), messages=\(messages.count)")

        streamTask = Task { [weak self] in
            do {
                let request = try Self.buildRequest(
                    messages: messages,
                    systemPrompt: systemPrompt,
                    provider: provider,
                    model: model,
                    apiKey: apiKey,
                    tools: tools,
                    toolResults: toolResults
                )
                try await self?.streamResponse(request: request, provider: provider)
            } catch is CancellationError {
                Log.llm.debug("요청 취소됨")
            } catch {
                Log.llm.error("요청 실패: \(error, privacy: .public)")
                self?.error = error.localizedDescription
            }
            self?.isStreaming = false
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        sentenceChunker.reset()
        pendingToolCalls = []
    }

    // MARK: - Request Building

    private static func buildRequest(
        messages: [Message],
        systemPrompt: String,
        provider: LLMProvider,
        model: String,
        apiKey: String,
        tools: [[String: Any]]?,
        toolResults: [ToolResult]?
    ) throws -> URLRequest {
        var request = URLRequest(url: provider.apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        switch provider {
        case .openai, .zai:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let body = OpenAIProviderHelper.buildBody(messages: messages, systemPrompt: systemPrompt, model: model, tools: tools, toolResults: toolResults, providerIsZAI: provider == .zai)
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(Constants.LLM.anthropicAPIVersion, forHTTPHeaderField: "anthropic-version")
            let body = AnthropicProviderHelper.buildBody(messages: messages, systemPrompt: systemPrompt, model: model, tools: tools, toolResults: toolResults, maxTokens: Constants.LLM.anthropicMaxTokens)
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return request
    }


    // MARK: - SSE Streaming

    private func streamResponse(request: URLRequest, provider: LLMProvider) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            var body = ""
            for try await line in bytes.lines {
                body += line
            }
            Log.llm.error("HTTP 에러: status=\(httpResponse.statusCode), body=\(body.prefix(500), privacy: .public)")
            throw LLMError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        var currentToolCall: (id: String, name: String, arguments: String)?

        for try await line in bytes.lines {
            try Task.checkCancellation()

            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))

            if payload == "[DONE]" { break }

            // SSE 스트림의 개별 줄 파싱 실패는 무시하고 다음 줄 처리
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            switch provider {
            case .openai, .zai:
                if let parsed = OpenAIProviderHelper.parseDelta(json) {
                    if let text = parsed.text {
                        partialResponse += text
                        for sentence in sentenceChunker.process(text) { self.onSentenceReady?(sentence) }
                    }
                    if let tc = parsed.toolCall {
                        // Tool call 조립
                        if let id = tc.id {
                            // 새 tool call 시작
                            if let current = currentToolCall {
                                pendingToolCalls.append(ToolCall(
                                    id: current.id,
                                    name: current.name,
                                    argumentsJSON: current.arguments
                                ))
                            }
                            currentToolCall = (id, tc.name ?? "", tc.arguments ?? "")
                        } else if currentToolCall != nil {
                            // 기존 tool call에 arguments 추가
                            currentToolCall?.arguments += tc.arguments ?? ""
                        }
                    }
                }

            case .anthropic:
                if let result = AnthropicProviderHelper.parseDelta(json) {
                    switch result {
                    case .text(let text):
                        partialResponse += text
                        for sentence in sentenceChunker.process(text) { self.onSentenceReady?(sentence) }
                    case .toolUseStart(let id, let name):
                        if let current = currentToolCall {
                            pendingToolCalls.append(ToolCall(
                                id: current.id,
                                name: current.name,
                                argumentsJSON: current.arguments
                            ))
                        }
                        currentToolCall = (id, name, "")
                    case .toolUseInput(let input):
                        currentToolCall?.arguments += input
                    }
                }
            }
        }

        // 마지막 tool call 처리
        if let current = currentToolCall {
            pendingToolCalls.append(ToolCall(
                id: current.id,
                name: current.name,
                argumentsJSON: current.arguments
            ))
        }

        // 남은 버퍼 flush
        if let last = sentenceChunker.flush() { onSentenceReady?(last) }

        // Tool calls가 있으면 콜백
        if !pendingToolCalls.isEmpty {
            onToolCallsReceived?(pendingToolCalls)
        } else {
            let finalResponse = partialResponse
            if !finalResponse.isEmpty {
                onResponseComplete?(finalResponse)
            }
        }
    }

    // Sentence chunking and provider-specific parsing are delegated to
    // SentenceChunker and Providers/* helpers respectively.
}

// MARK: - Error

enum LLMError: LocalizedError {
    case httpError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            "HTTP \(code): \(body.prefix(200))"
        }
    }
}
