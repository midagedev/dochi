import Foundation
import os

@MainActor
final class WebSearchTool: BuiltInToolProtocol {
    let name = "web_search"
    let category: ToolCategory = .safe
    let description = "Tavily API를 사용하여 웹 검색을 수행합니다."
    let isBaseline = true

    private let keychainService: KeychainServiceProtocol

    init(keychainService: KeychainServiceProtocol) {
        self.keychainService = keychainService
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "query": ["type": "string", "description": "검색 쿼리"]
            ],
            "required": ["query"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: query는 필수입니다.", isError: true)
        }

        guard let apiKey = keychainService.load(account: "tavily_api_key"), !apiKey.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: Tavily API 키가 설정되지 않았습니다. 설정에서 API 키를 등록해주세요.", isError: true)
        }

        let url = URL(string: "https://api.tavily.com/search")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "api_key": apiKey,
            "query": query,
            "max_results": 5,
            "include_answer": true
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return ToolResult(toolCallId: "", content: "오류: 요청 생성 실패.", isError: true)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return ToolResult(toolCallId: "", content: "오류: 서버 응답을 받을 수 없습니다.", isError: true)
            }

            guard httpResponse.statusCode == 200 else {
                Log.tool.error("Tavily API error: status \(httpResponse.statusCode)")
                return ToolResult(toolCallId: "", content: "오류: 검색 API 오류 (HTTP \(httpResponse.statusCode)). API 키를 확인해주세요.", isError: true)
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ToolResult(toolCallId: "", content: "오류: 응답 파싱 실패.", isError: true)
            }

            var output = "검색 결과: \"\(query)\"\n\n"

            if let answer = json["answer"] as? String, !answer.isEmpty {
                output += "요약: \(answer)\n\n"
            }

            if let results = json["results"] as? [[String: Any]] {
                for (i, result) in results.enumerated() {
                    let title = result["title"] as? String ?? ""
                    let resultUrl = result["url"] as? String ?? ""
                    let content = result["content"] as? String ?? ""
                    output += "\(i + 1). \(title)\n   \(resultUrl)\n   \(content)\n\n"
                }
            }

            Log.tool.info("Web search completed: \(query)")
            return ToolResult(toolCallId: "", content: output.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            Log.tool.error("Web search failed: \(error.localizedDescription)")
            return ToolResult(toolCallId: "", content: "오류: 검색 실패 — \(error.localizedDescription)", isError: true)
        }
    }
}
