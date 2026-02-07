import Foundation
import os

/// 웹검색 도구 (Tavily API)
@MainActor
final class WebSearchTool: BuiltInTool {
    nonisolated var tools: [MCPToolInfo] {
        [
            MCPToolInfo(
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
            )
        ]
    }

    var apiKey: String = ""

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        guard name == "web_search" else {
            throw BuiltInToolError.unknownTool(name)
        }
        return try await webSearch(arguments: arguments)
    }

    private func webSearch(arguments: [String: Any]) async throws -> MCPToolResult {
        guard !apiKey.isEmpty else {
            throw BuiltInToolError.missingApiKey("Tavily")
        }

        guard let query = arguments["query"] as? String, !query.isEmpty else {
            throw BuiltInToolError.invalidArguments("query is required")
        }

        Log.tool.info("웹검색 요청: query=\(query, privacy: .public)")

        let url = URL(string: "https://api.tavily.com/search")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "api_key": apiKey,
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
            Log.tool.error("Tavily API 에러: status=\(httpResponse.statusCode), body=\(errorBody, privacy: .public)")
            throw BuiltInToolError.apiError("Tavily API error (\(httpResponse.statusCode)): \(errorBody)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BuiltInToolError.invalidResponse("Failed to parse Tavily response")
        }

        var resultText = ""

        if let answer = json["answer"] as? String, !answer.isEmpty {
            resultText += "## Summary\n\(answer)\n\n"
        }

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
