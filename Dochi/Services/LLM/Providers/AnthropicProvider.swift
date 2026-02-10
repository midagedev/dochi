import Foundation

enum AnthropicProviderHelper {
    static func buildBody(messages: [Message], systemPrompt: String, model: String, tools: [[String: Any]]?, toolResults: [ToolResult]?, maxTokens: Int) -> [String: Any] {
        var apiMessages: [[String: Any]] = []
        var pendingToolResults: [[String: Any]] = []
        for msg in messages where msg.role != .system {
            if msg.role == .tool {
                pendingToolResults.append(["type": "tool_result", "tool_use_id": msg.toolCallId ?? "", "content": msg.content])
                continue
            }
            if !pendingToolResults.isEmpty { apiMessages.append(["role": "user", "content": pendingToolResults]); pendingToolResults = [] }
            let role = msg.role == .user ? "user" : "assistant"
            if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                var content: [[String: Any]] = []
                if !msg.content.isEmpty { content.append(["type": "text", "text": msg.content]) }
                for tc in toolCalls { content.append(["type": "tool_use", "id": tc.id, "name": tc.name, "input": tc.arguments]) }
                apiMessages.append(["role": role, "content": content])
            } else {
                apiMessages.append(["role": role, "content": msg.content])
            }
        }
        if !pendingToolResults.isEmpty { apiMessages.append(["role": "user", "content": pendingToolResults]) }
        if let results = toolResults, !results.isEmpty {
            var content: [[String: Any]] = []
            for result in results { content.append(["type": "tool_result", "tool_use_id": result.toolCallId, "content": result.content, "is_error": result.isError]) }
            apiMessages.append(["role": "user", "content": content])
        }
        var body: [String: Any] = ["model": model, "messages": apiMessages, "stream": true, "max_tokens": maxTokens]
        if !systemPrompt.isEmpty { body["system"] = systemPrompt }
        if let tools, !tools.isEmpty {
            let anthropicTools = tools.compactMap { tool -> [String: Any]? in
                guard let function = tool["function"] as? [String: Any], let name = function["name"] as? String else { return nil }
                var anthropicTool: [String: Any] = ["name": name]
                if let desc = function["description"] as? String { anthropicTool["description"] = desc }
                if let params = function["parameters"] as? [String: Any] { anthropicTool["input_schema"] = params }
                else { anthropicTool["input_schema"] = ["type": "object", "properties": [:]] }
                return anthropicTool
            }
            body["tools"] = anthropicTools
        }
        return body
    }

    enum DeltaResult { case text(String); case toolUseStart(id: String, name: String); case toolUseInput(String) }

    static func parseDelta(_ json: [String: Any]) -> DeltaResult? {
        guard let type = json["type"] as? String else { return nil }
        switch type {
        case "content_block_delta":
            if let delta = json["delta"] as? [String: Any] {
                if let text = delta["text"] as? String { return .text(text) }
                if let input = delta["partial_json"] as? String { return .toolUseInput(input) }
            }
        case "content_block_start":
            if let contentBlock = json["content_block"] as? [String: Any], contentBlock["type"] as? String == "tool_use", let id = contentBlock["id"] as? String, let name = contentBlock["name"] as? String {
                return .toolUseStart(id: id, name: name)
            }
        default: break
        }
        return nil
    }
}

