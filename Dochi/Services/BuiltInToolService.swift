import Foundation

/// 내장 도구 서비스 - Tavily 웹검색 등
@MainActor
final class BuiltInToolService: ObservableObject {
    @Published private(set) var error: String?

    private var tavilyApiKey: String = ""

    var availableTools: [MCPToolInfo] {
        var tools: [MCPToolInfo] = []

        if !tavilyApiKey.isEmpty {
            tools.append(MCPToolInfo(
                id: "builtin:web_search",
                name: "web_search",
                description: "Search the web for current information. Use this when you need up-to-date information about events, facts, or topics.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "The search query"
                        ]
                    ],
                    "required": ["query"]
                ]
            ))
        }

        return tools
    }

    func configure(tavilyApiKey: String) {
        self.tavilyApiKey = tavilyApiKey
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        switch name {
        case "web_search":
            return try await webSearch(arguments: arguments)
        default:
            throw BuiltInToolError.unknownTool(name)
        }
    }

    // MARK: - Web Search (Tavily)

    private func webSearch(arguments: [String: Any]) async throws -> MCPToolResult {
        guard !tavilyApiKey.isEmpty else {
            throw BuiltInToolError.missingApiKey("Tavily")
        }

        guard let query = arguments["query"] as? String, !query.isEmpty else {
            throw BuiltInToolError.invalidArguments("query is required")
        }

        let url = URL(string: "https://api.tavily.com/search")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "api_key": tavilyApiKey,
            "query": query,
            "search_depth": "basic",
            "include_answer": true,
            "include_raw_content": false,
            "max_results": 5
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw BuiltInToolError.apiError("Tavily API error (\(httpResponse.statusCode)): \(errorBody)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BuiltInToolError.invalidResponse("Failed to parse Tavily response")
        }

        // 응답 포맷팅
        var resultText = ""

        // AI 요약 (있으면)
        if let answer = json["answer"] as? String, !answer.isEmpty {
            resultText += "## Summary\n\(answer)\n\n"
        }

        // 검색 결과
        if let results = json["results"] as? [[String: Any]] {
            resultText += "## Search Results\n\n"
            for (index, result) in results.prefix(5).enumerated() {
                let title = result["title"] as? String ?? "No title"
                let url = result["url"] as? String ?? ""
                let content = result["content"] as? String ?? ""

                resultText += "\(index + 1). **\(title)**\n"
                if !url.isEmpty {
                    resultText += "   URL: \(url)\n"
                }
                if !content.isEmpty {
                    // 내용 truncate
                    let truncated = content.prefix(300)
                    resultText += "   \(truncated)\(content.count > 300 ? "..." : "")\n"
                }
                resultText += "\n"
            }
        }

        if resultText.isEmpty {
            resultText = "No results found for: \(query)"
        }

        return MCPToolResult(content: resultText, isError: false)
    }
}

// MARK: - Errors

enum BuiltInToolError: LocalizedError {
    case unknownTool(String)
    case missingApiKey(String)
    case invalidArguments(String)
    case apiError(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "Unknown built-in tool: \(name)"
        case .missingApiKey(let service):
            return "\(service) API key is not configured"
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        case .apiError(let message):
            return message
        case .invalidResponse(let message):
            return message
        }
    }
}
