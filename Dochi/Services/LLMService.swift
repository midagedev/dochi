import Foundation
import Combine

@MainActor
final class LLMService: ObservableObject {
    @Published var partialResponse: String = ""
    @Published var error: String?
    @Published var isStreaming: Bool = false

    var onResponseComplete: ((String) -> Void)?
    var onSentenceReady: ((String) -> Void)?

    private var streamTask: Task<Void, Never>?
    private var sentenceBuffer: String = ""

    // MARK: - Public

    func sendMessage(
        messages: [Message],
        systemPrompt: String,
        provider: LLMProvider,
        model: String,
        apiKey: String
    ) {
        guard !apiKey.isEmpty else {
            error = "\(provider.displayName) API 키를 설정해주세요."
            return
        }
        cancel()
        partialResponse = ""
        sentenceBuffer = ""
        error = nil
        isStreaming = true

        streamTask = Task { [weak self] in
            do {
                let request = try Self.buildRequest(
                    messages: messages,
                    systemPrompt: systemPrompt,
                    provider: provider,
                    model: model,
                    apiKey: apiKey
                )
                try await self?.streamResponse(request: request, provider: provider)
            } catch is CancellationError {
                // cancelled
            } catch {
                self?.error = error.localizedDescription
            }
            self?.isStreaming = false
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        sentenceBuffer = ""
    }

    // MARK: - Request Building

    private static func buildRequest(
        messages: [Message],
        systemPrompt: String,
        provider: LLMProvider,
        model: String,
        apiKey: String
    ) throws -> URLRequest {
        var request = URLRequest(url: provider.apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        switch provider {
        case .openai, .zai:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let body = buildOpenAIBody(messages: messages, systemPrompt: systemPrompt, model: model, provider: provider)
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let body = buildAnthropicBody(messages: messages, systemPrompt: systemPrompt, model: model)
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return request
    }

    private static func buildOpenAIBody(
        messages: [Message],
        systemPrompt: String,
        model: String,
        provider: LLMProvider
    ) -> [String: Any] {
        var apiMessages: [[String: String]] = []
        if !systemPrompt.isEmpty {
            apiMessages.append(["role": "system", "content": systemPrompt])
        }
        for msg in messages {
            let role: String
            switch msg.role {
            case .user: role = "user"
            case .assistant: role = "assistant"
            case .system: role = "system"
            }
            apiMessages.append(["role": role, "content": msg.content])
        }
        var body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "stream": true,
        ]
        if provider == .zai {
            body["enable_thinking"] = false
        }
        return body
    }

    private static func buildAnthropicBody(
        messages: [Message],
        systemPrompt: String,
        model: String
    ) -> [String: Any] {
        var apiMessages: [[String: String]] = []
        for msg in messages where msg.role != .system {
            let role = msg.role == .user ? "user" : "assistant"
            apiMessages.append(["role": role, "content": msg.content])
        }
        var body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "stream": true,
            "max_tokens": 4096,
        ]
        if !systemPrompt.isEmpty {
            body["system"] = systemPrompt
        }
        return body
    }

    // MARK: - SSE Streaming

    private func streamResponse(request: URLRequest, provider: LLMProvider) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            var body = ""
            for try await line in bytes.lines {
                body += line
            }
            throw LLMError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()

            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))

            if payload == "[DONE]" { break }

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let delta: String?
            switch provider {
            case .openai, .zai:
                delta = Self.parseOpenAIDelta(json)
            case .anthropic:
                delta = Self.parseAnthropicDelta(json)
            }

            if let text = delta {
                partialResponse += text
                feedSentenceBuffer(text)
            }
        }

        // 남은 버퍼 flush
        flushSentenceBuffer()

        let finalResponse = partialResponse
        if !finalResponse.isEmpty {
            onResponseComplete?(finalResponse)
        }
    }

    // MARK: - Sentence Detection

    private func feedSentenceBuffer(_ text: String) {
        sentenceBuffer += text

        // 줄바꿈이 들어오면 즉시 flush
        while let nlRange = sentenceBuffer.range(of: "\n") {
            let line = String(sentenceBuffer[sentenceBuffer.startIndex..<nlRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            sentenceBuffer = String(sentenceBuffer[nlRange.upperBound...])
            if !line.isEmpty {
                onSentenceReady?(line)
            }
        }
    }

    private func flushSentenceBuffer() {
        let remaining = sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        sentenceBuffer = ""
        if !remaining.isEmpty {
            onSentenceReady?(remaining)
        }
    }

    // MARK: - Delta Parsing

    private static func parseOpenAIDelta(_ json: [String: Any]) -> String? {
        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any],
              let content = delta["content"] as? String
        else { return nil }
        return content
    }

    private static func parseAnthropicDelta(_ json: [String: Any]) -> String? {
        guard let type = json["type"] as? String,
              type == "content_block_delta",
              let delta = json["delta"] as? [String: Any],
              let text = delta["text"] as? String
        else { return nil }
        return text
    }
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
