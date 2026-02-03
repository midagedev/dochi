import Foundation
import Combine

@MainActor
final class LLMService: ObservableObject {
    @Published var partialResponse: String = ""
    @Published var error: String?
    @Published var isStreaming: Bool = false

    var onResponseComplete: ((String) -> Void)?
    var onSentenceReady: ((String) -> Void)?
    var onToolCallsReceived: (([ToolCall]) -> Void)?

    private var streamTask: Task<Void, Never>?
    private var sentenceBuffer: String = ""
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
        sentenceBuffer = ""
        pendingToolCalls = []
        error = nil
        isStreaming = true

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
            let body = buildOpenAIBody(
                messages: messages,
                systemPrompt: systemPrompt,
                model: model,
                provider: provider,
                tools: tools,
                toolResults: toolResults
            )
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let body = buildAnthropicBody(
                messages: messages,
                systemPrompt: systemPrompt,
                model: model,
                tools: tools,
                toolResults: toolResults
            )
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return request
    }

    private static func buildOpenAIBody(
        messages: [Message],
        systemPrompt: String,
        model: String,
        provider: LLMProvider,
        tools: [[String: Any]]?,
        toolResults: [ToolResult]?
    ) -> [String: Any] {
        var apiMessages: [[String: Any]] = []

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

            // tool_calls가 있는 assistant 메시지
            if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                var msgDict: [String: Any] = ["role": role]
                if !msg.content.isEmpty {
                    msgDict["content"] = msg.content
                }
                msgDict["tool_calls"] = toolCalls.map { tc in
                    [
                        "id": tc.id,
                        "type": "function",
                        "function": [
                            "name": tc.name,
                            "arguments": (try? String(data: JSONSerialization.data(withJSONObject: tc.arguments), encoding: .utf8)) ?? "{}"
                        ]
                    ] as [String: Any]
                }
                apiMessages.append(msgDict)
            } else {
                apiMessages.append(["role": role, "content": msg.content])
            }
        }

        // Tool 결과 추가
        if let results = toolResults {
            for result in results {
                apiMessages.append([
                    "role": "tool",
                    "tool_call_id": result.toolCallId,
                    "content": result.content
                ])
            }
        }

        var body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "stream": true,
        ]

        if provider == .zai {
            body["enable_thinking"] = false
        }

        if let tools = tools, !tools.isEmpty {
            body["tools"] = tools
        }

        return body
    }

    private static func buildAnthropicBody(
        messages: [Message],
        systemPrompt: String,
        model: String,
        tools: [[String: Any]]?,
        toolResults: [ToolResult]?
    ) -> [String: Any] {
        var apiMessages: [[String: Any]] = []

        for msg in messages where msg.role != .system {
            let role = msg.role == .user ? "user" : "assistant"

            // Anthropic은 content가 배열일 수 있음 (tool_use, tool_result)
            if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                var content: [[String: Any]] = []
                if !msg.content.isEmpty {
                    content.append(["type": "text", "text": msg.content])
                }
                for tc in toolCalls {
                    content.append([
                        "type": "tool_use",
                        "id": tc.id,
                        "name": tc.name,
                        "input": tc.arguments
                    ])
                }
                apiMessages.append(["role": role, "content": content])
            } else {
                apiMessages.append(["role": role, "content": msg.content])
            }
        }

        // Tool 결과 추가 (user 메시지로)
        if let results = toolResults, !results.isEmpty {
            var content: [[String: Any]] = []
            for result in results {
                content.append([
                    "type": "tool_result",
                    "tool_use_id": result.toolCallId,
                    "content": result.content,
                    "is_error": result.isError
                ])
            }
            apiMessages.append(["role": "user", "content": content])
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

        if let tools = tools, !tools.isEmpty {
            // Anthropic 형식으로 변환
            let anthropicTools = tools.compactMap { tool -> [String: Any]? in
                guard let function = tool["function"] as? [String: Any],
                      let name = function["name"] as? String else { return nil }
                var anthropicTool: [String: Any] = ["name": name]
                if let desc = function["description"] as? String {
                    anthropicTool["description"] = desc
                }
                if let params = function["parameters"] as? [String: Any] {
                    anthropicTool["input_schema"] = params
                } else {
                    anthropicTool["input_schema"] = ["type": "object", "properties": [:]]
                }
                return anthropicTool
            }
            body["tools"] = anthropicTools
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

        var currentToolCall: (id: String, name: String, arguments: String)?

        for try await line in bytes.lines {
            try Task.checkCancellation()

            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))

            if payload == "[DONE]" { break }

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            switch provider {
            case .openai, .zai:
                if let (text, toolCallDelta) = Self.parseOpenAIDelta(json) {
                    if let text = text {
                        partialResponse += text
                        feedSentenceBuffer(text)
                    }
                    if let delta = toolCallDelta {
                        // Tool call 조립
                        if let id = delta.id {
                            // 새 tool call 시작
                            if let current = currentToolCall {
                                pendingToolCalls.append(ToolCall(
                                    id: current.id,
                                    name: current.name,
                                    argumentsJSON: current.arguments
                                ))
                            }
                            currentToolCall = (id, delta.name ?? "", delta.arguments ?? "")
                        } else if currentToolCall != nil {
                            // 기존 tool call에 arguments 추가
                            currentToolCall?.arguments += delta.arguments ?? ""
                        }
                    }
                }

            case .anthropic:
                if let result = Self.parseAnthropicDelta(json) {
                    switch result {
                    case .text(let text):
                        partialResponse += text
                        feedSentenceBuffer(text)
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
        flushSentenceBuffer()

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

    // MARK: - Sentence Detection

    private func feedSentenceBuffer(_ text: String) {
        sentenceBuffer += text

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

    private struct ToolCallDelta {
        var id: String?
        var name: String?
        var arguments: String?
    }

    private static func parseOpenAIDelta(_ json: [String: Any]) -> (text: String?, toolCall: ToolCallDelta?)? {
        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any]
        else { return nil }

        let text = delta["content"] as? String

        var toolCallDelta: ToolCallDelta?
        if let toolCalls = delta["tool_calls"] as? [[String: Any]],
           let tc = toolCalls.first {
            toolCallDelta = ToolCallDelta()
            toolCallDelta?.id = tc["id"] as? String
            if let function = tc["function"] as? [String: Any] {
                toolCallDelta?.name = function["name"] as? String
                toolCallDelta?.arguments = function["arguments"] as? String
            }
        }

        if text == nil && toolCallDelta == nil { return nil }
        return (text, toolCallDelta)
    }

    private enum AnthropicDeltaResult {
        case text(String)
        case toolUseStart(id: String, name: String)
        case toolUseInput(String)
    }

    private static func parseAnthropicDelta(_ json: [String: Any]) -> AnthropicDeltaResult? {
        guard let type = json["type"] as? String else { return nil }

        switch type {
        case "content_block_delta":
            if let delta = json["delta"] as? [String: Any] {
                if let text = delta["text"] as? String {
                    return .text(text)
                }
                if let input = delta["partial_json"] as? String {
                    return .toolUseInput(input)
                }
            }

        case "content_block_start":
            if let contentBlock = json["content_block"] as? [String: Any],
               contentBlock["type"] as? String == "tool_use",
               let id = contentBlock["id"] as? String,
               let name = contentBlock["name"] as? String {
                return .toolUseStart(id: id, name: name)
            }

        default:
            break
        }

        return nil
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
