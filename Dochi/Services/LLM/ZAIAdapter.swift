import Foundation

struct ZAIAdapter: LLMProviderAdapter {
    let provider: LLMProvider = .zai

    private let base = OpenAIAdapter()

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
            "enable_thinking": false,
        ]

        var apiMessages: [[String: Any]] = []

        if !systemPrompt.isEmpty {
            apiMessages.append([
                "role": "system",
                "content": systemPrompt,
            ])
        }

        for msg in messages {
            apiMessages.append(OpenAIAdapter.convertMessage(msg))
        }

        body["messages"] = apiMessages

        if let tools, !tools.isEmpty {
            body["tools"] = tools
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func parseSSELine(_ line: String, accumulated: inout StreamAccumulator) -> LLMStreamEvent? {
        // Z.AI uses OpenAI-compatible SSE format
        base.parseSSELine(line, accumulated: &accumulated)
    }
}
