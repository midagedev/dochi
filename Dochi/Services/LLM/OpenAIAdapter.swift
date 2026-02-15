import Foundation

struct OpenAIAdapter: LLMProviderAdapter {
    let provider: LLMProvider = .openai

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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "stream_options": ["include_usage": true],
        ]

        var apiMessages: [[String: Any]] = []

        // System prompt as a system message
        if !systemPrompt.isEmpty {
            apiMessages.append([
                "role": "system",
                "content": systemPrompt,
            ])
        }

        for msg in messages {
            apiMessages.append(Self.convertMessage(msg))
        }

        body["messages"] = apiMessages

        if let tools, !tools.isEmpty {
            body["tools"] = tools
        }

        body = addProviderSpecificFields(body)

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Subclass hook — OpenAI base adds nothing, ZAI overrides.
    func addProviderSpecificFields(_ body: [String: Any]) -> [String: Any] {
        body
    }

    func parseSSELine(_ line: String, accumulated: inout StreamAccumulator) -> LLMStreamEvent? {
        // SSE format: "data: {json}" or "data: [DONE]"
        guard line.hasPrefix("data: ") else { return nil }
        let payload = String(line.dropFirst(6))

        if payload == "[DONE]" {
            return .done
        }

        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first else {
            return nil
        }

        // Check for error in response
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return .error(.invalidResponse(message))
        }

        guard let delta = firstChoice["delta"] as? [String: Any] else {
            return nil
        }

        // Text content
        if let content = delta["content"] as? String, !content.isEmpty {
            accumulated.text += content
            return .partial(content)
        }

        // Tool calls
        if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
            for tc in toolCalls {
                guard let index = tc["index"] as? Int else { continue }

                let id = tc["id"] as? String
                let function = tc["function"] as? [String: Any]
                let name = function?["name"] as? String
                let argDelta = function?["arguments"] as? String ?? ""

                // Initialize accumulator entry
                if accumulated.toolCalls[index] == nil {
                    accumulated.toolCalls[index] = StreamAccumulator.ToolCallAccumulator()
                }
                if let id { accumulated.toolCalls[index]?.id = id }
                if let name { accumulated.toolCalls[index]?.name = name }
                accumulated.toolCalls[index]?.arguments += argDelta

                return .toolCallDelta(index: index, id: id, name: name, argumentsDelta: argDelta)
            }
        }

        // Parse usage from final chunk (requires stream_options.include_usage)
        if let usage = json["usage"] as? [String: Any] {
            accumulated.inputTokens = usage["prompt_tokens"] as? Int
            accumulated.outputTokens = usage["completion_tokens"] as? Int
        }

        // finish_reason check
        if let finishReason = firstChoice["finish_reason"] as? String, finishReason == "stop" || finishReason == "tool_calls" {
            return .done
        }

        return nil
    }

    // MARK: - Message Conversion

    static func convertMessage(_ msg: Message) -> [String: Any] {
        var dict: [String: Any] = [
            "role": msg.role.rawValue,
        ]

        if msg.role == .assistant, let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
            // Assistant message with tool calls
            if !msg.content.isEmpty {
                dict["content"] = msg.content
            }
            dict["tool_calls"] = toolCalls.enumerated().map { index, tc in
                [
                    "id": tc.id,
                    "type": "function",
                    "function": [
                        "name": tc.name,
                        "arguments": tc.argumentsJSON,
                    ] as [String: Any],
                ] as [String: Any]
            }
        } else if msg.role == .tool {
            dict["content"] = msg.content
            if let toolCallId = msg.toolCallId {
                dict["tool_call_id"] = toolCallId
            }
        } else if msg.role == .user, let images = msg.imageData, !images.isEmpty {
            // I-3: Convert to multi-content array for Vision
            var content: [[String: Any]] = []
            if !msg.content.isEmpty {
                content.append(["type": "text", "text": msg.content])
            }
            for image in images {
                content.append([
                    "type": "image_url",
                    "image_url": [
                        "url": "data:\(image.mimeType);base64,\(image.base64Data)",
                    ] as [String: Any],
                ])
            }
            dict["content"] = content
        } else {
            dict["content"] = msg.content
        }

        return dict
    }
}
