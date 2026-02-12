import Foundation

struct AnthropicAdapter: LLMProviderAdapter {
    let provider: LLMProvider = .anthropic

    /// Tracks which content block index is a tool_use block.
    /// Since StreamAccumulator is Sendable and we parse line-by-line,
    /// we store tool block mapping in the accumulator's toolCalls dictionary.

    func buildRequest(
        messages: [Message],
        systemPrompt: String,
        model: String,
        tools: [[String: Any]]?,
        apiKey: String
    ) throws -> URLRequest {
        var request = URLRequest(url: provider.apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "max_tokens": 8192,
        ]

        // System is top-level, NOT in messages
        if !systemPrompt.isEmpty {
            body["system"] = systemPrompt
        }

        var apiMessages: [[String: Any]] = []
        for msg in messages {
            apiMessages.append(convertMessage(msg))
        }
        body["messages"] = apiMessages

        if let tools, !tools.isEmpty {
            body["tools"] = convertTools(tools)
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func parseSSELine(_ line: String, accumulated: inout StreamAccumulator) -> LLMStreamEvent? {
        // Anthropic SSE: "event: <type>" followed by "data: {json}"
        // We only process "data:" lines; the event type is embedded in the JSON.
        guard line.hasPrefix("data: ") else { return nil }
        let payload = String(line.dropFirst(6))

        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }

        switch type {
        case "message_start":
            // Capture input tokens from message start event
            if let message = json["message"] as? [String: Any],
               let usage = message["usage"] as? [String: Any] {
                accumulated.inputTokens = usage["input_tokens"] as? Int
            }
            return nil

        case "content_block_start":
            // A new content block is starting
            guard let index = json["index"] as? Int,
                  let contentBlock = json["content_block"] as? [String: Any],
                  let blockType = contentBlock["type"] as? String else {
                return nil
            }
            if blockType == "tool_use" {
                let id = contentBlock["id"] as? String ?? ""
                let name = contentBlock["name"] as? String ?? ""
                accumulated.toolCalls[index] = StreamAccumulator.ToolCallAccumulator(
                    id: id, name: name, arguments: ""
                )
                return .toolCallDelta(index: index, id: id, name: name, argumentsDelta: "")
            }
            return nil

        case "content_block_delta":
            guard let index = json["index"] as? Int,
                  let delta = json["delta"] as? [String: Any],
                  let deltaType = delta["type"] as? String else {
                return nil
            }

            if deltaType == "text_delta", let text = delta["text"] as? String {
                accumulated.text += text
                return .partial(text)
            }

            if deltaType == "input_json_delta", let partialJSON = delta["partial_json"] as? String {
                accumulated.toolCalls[index]?.arguments += partialJSON
                return .toolCallDelta(index: index, id: nil, name: nil, argumentsDelta: partialJSON)
            }

            return nil

        case "message_delta":
            // Capture output tokens from message delta
            if let usage = json["usage"] as? [String: Any] {
                accumulated.outputTokens = usage["output_tokens"] as? Int
            }
            // Check stop_reason
            if let delta = json["delta"] as? [String: Any],
               let stopReason = delta["stop_reason"] as? String,
               stopReason == "end_turn" || stopReason == "tool_use" {
                return .done
            }
            return nil

        case "message_stop":
            return .done

        case "error":
            let error = json["error"] as? [String: Any]
            let message = error?["message"] as? String ?? "Unknown Anthropic error"
            return .error(.invalidResponse(message))

        default:
            return nil
        }
    }

    // MARK: - Message Conversion

    private func convertMessage(_ msg: Message) -> [String: Any] {
        switch msg.role {
        case .system:
            // Anthropic doesn't use system in messages; this shouldn't happen
            // but handle gracefully by converting to user message
            return ["role": "user", "content": msg.content]

        case .user:
            return ["role": "user", "content": msg.content]

        case .assistant:
            if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                var content: [[String: Any]] = []
                if !msg.content.isEmpty {
                    content.append(["type": "text", "text": msg.content])
                }
                for tc in toolCalls {
                    var input: Any = [String: Any]()
                    if let data = tc.argumentsJSON.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: data) {
                        input = parsed
                    }
                    content.append([
                        "type": "tool_use",
                        "id": tc.id,
                        "name": tc.name,
                        "input": input,
                    ])
                }
                return ["role": "assistant", "content": content]
            }
            return ["role": "assistant", "content": msg.content]

        case .tool:
            // Anthropic tool results go as user messages with tool_result content
            return [
                "role": "user",
                "content": [
                    [
                        "type": "tool_result",
                        "tool_use_id": msg.toolCallId ?? "",
                        "content": msg.content,
                    ] as [String: Any],
                ],
            ]
        }
    }

    /// Convert OpenAI-style tool definitions to Anthropic format.
    /// OpenAI: `[{"type": "function", "function": {"name": ..., "description": ..., "parameters": ...}}]`
    /// Anthropic: `[{"name": ..., "description": ..., "input_schema": ...}]`
    private func convertTools(_ tools: [[String: Any]]) -> [[String: Any]] {
        tools.compactMap { tool -> [String: Any]? in
            if let function = tool["function"] as? [String: Any] {
                var converted: [String: Any] = [:]
                if let name = function["name"] { converted["name"] = name }
                if let description = function["description"] { converted["description"] = description }
                if let parameters = function["parameters"] {
                    converted["input_schema"] = parameters
                } else {
                    converted["input_schema"] = ["type": "object", "properties": [String: Any]()]
                }
                return converted
            }
            // Already in Anthropic format or unknown — pass through
            return tool
        }
    }
}
