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
            switch msg.role {
            case .tool:
                // Tool result 메시지
                apiMessages.append([
                    "role": "tool",
                    "tool_call_id": msg.toolCallId ?? "",
                    "content": msg.content
                ])
            case .user, .assistant, .system:
                let role: String
                switch msg.role {
                case .user: role = "user"
                case .assistant: role = "assistant"
                case .system: role = "system"
                default: continue
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
                                // JSON 직렬화 실패 시 빈 객체로 폴백 — arguments는 이미 유효한 딕셔너리
                                "arguments": (try? String(data: JSONSerialization.data(withJSONObject: tc.arguments), encoding: .utf8)) ?? "{}"
                            ]
                        ] as [String: Any]
                    }
                    apiMessages.append(msgDict)
                } else {
                    apiMessages.append(["role": role, "content": msg.content])
                }
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

        // Anthropic: tool result 메시지들을 연속된 user content 배열로 묶어야 함
        var pendingToolResults: [[String: Any]] = []

        for msg in messages where msg.role != .system {
            if msg.role == .tool {
                // tool result를 모아두기 (다음 비-tool 메시지 전에 flush)
                pendingToolResults.append([
                    "type": "tool_result",
                    "tool_use_id": msg.toolCallId ?? "",
                    "content": msg.content
                ])
                continue
            }

            // 모인 tool result가 있으면 user 메시지로 flush
            if !pendingToolResults.isEmpty {
                apiMessages.append(["role": "user", "content": pendingToolResults])
                pendingToolResults = []
            }

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

        // 마지막에 남은 tool result flush
        if !pendingToolResults.isEmpty {
            apiMessages.append(["role": "user", "content": pendingToolResults])
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
            "max_tokens": Constants.LLM.anthropicMaxTokens,
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
                    let text = parsed.text
                    var toolCallDelta: ToolCallDelta?
                    if let tc = parsed.toolCall {
                        var d = ToolCallDelta()
                        d.id = tc.id
                        d.name = tc.name
                        d.arguments = tc.arguments
                        toolCallDelta = d
                    }
                    if let text = text {
                        partialResponse += text
                        for sentence in sentenceChunker.process(text) { self.onSentenceReady?(sentence) }
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

    // MARK: - Sentence Detection

    private static let punctuationTerminators: Set<Character> = [".", "?", "!", "。"]

    // sentence chunking is delegated to SentenceChunker

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
