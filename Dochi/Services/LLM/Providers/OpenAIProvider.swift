import Foundation

enum OpenAIProviderHelper {
    static func buildBody(messages: [Message], systemPrompt: String, model: String, tools: [[String: Any]]?, toolResults: [ToolResult]?, providerIsZAI: Bool) -> [String: Any] {
        var apiMessages: [[String: Any]] = []
        if !systemPrompt.isEmpty { apiMessages.append(["role": "system", "content": systemPrompt]) }
        for msg in messages {
            switch msg.role {
            case .tool:
                apiMessages.append(["role": "tool", "tool_call_id": msg.toolCallId ?? "", "content": msg.content])
            case .user, .assistant, .system:
                let role: String
                switch msg.role { case .user: role = "user"; case .assistant: role = "assistant"; case .system: role = "system"; default: continue }
                if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                    var msgDict: [String: Any] = ["role": role]
                    if !msg.content.isEmpty { msgDict["content"] = msg.content }
                    msgDict["tool_calls"] = toolCalls.map { tc in [
                        "id": tc.id,
                        "type": "function",
                        "function": [
                            "name": tc.name,
                            "arguments": (try? String(data: JSONSerialization.data(withJSONObject: tc.arguments), encoding: .utf8)) ?? "{}"
                        ]
                    ] }
                    apiMessages.append(msgDict)
                } else {
                    apiMessages.append(["role": role, "content": msg.content])
                }
            }
        }
        if let results = toolResults {
            for result in results {
                apiMessages.append(["role": "tool", "tool_call_id": result.toolCallId, "content": result.content])
            }
        }
        var body: [String: Any] = ["model": model, "messages": apiMessages, "stream": true]
        if providerIsZAI { body["enable_thinking"] = false }
        if let tools, !tools.isEmpty { body["tools"] = tools }
        return body
    }

    static func parseDelta(_ json: [String: Any]) -> (text: String?, toolCall: (id: String?, name: String?, arguments: String?)?)? {
        guard let choices = json["choices"] as? [[String: Any]], let first = choices.first, let delta = first["delta"] as? [String: Any] else { return nil }
        let text = delta["content"] as? String
        var id: String?; var name: String?; var arguments: String?
        if let toolCalls = delta["tool_calls"] as? [[String: Any]], let tc = toolCalls.first {
            id = tc["id"] as? String
            if let function = tc["function"] as? [String: Any] {
                name = function["name"] as? String
                arguments = function["arguments"] as? String
            }
        }
        if text == nil && id == nil && name == nil && arguments == nil { return nil }
        return (text, (id, name, arguments))
    }
}

