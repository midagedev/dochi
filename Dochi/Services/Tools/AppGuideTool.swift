import Foundation
import os

/// 앱 사용 가이드 빌트인 도구.
/// 사용자가 앱 사용법을 물어볼 때 LLM이 호출하여 구조화된 가이드 데이터를 반환한다.
@MainActor
final class AppGuideTool: BuiltInToolProtocol {
    let name = "app.guide"
    let category: ToolCategory = .safe
    let description = "앱 사용법, 기능, 단축키, 설정 등의 가이드 정보를 조회합니다."
    let isBaseline = true

    private weak var toolRegistry: ToolRegistry?

    init(toolRegistry: ToolRegistry? = nil) {
        self.toolRegistry = toolRegistry
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "topic": [
                    "type": "string",
                    "enum": ["overview"] + AppGuideContentBuilder.allTopics,
                    "description": "가이드 주제. 생략 시 전체 개요(overview) 반환.",
                ] as [String: Any],
                "query": [
                    "type": "string",
                    "description": "자연어 검색 쿼리. topic 내 또는 전체에서 키워드 매칭.",
                ],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let topic = arguments["topic"] as? String
        let query = arguments["query"] as? String

        // topic 유효성 검증
        if let topic, !topic.isEmpty, topic != "overview" {
            let validTopics = AppGuideContentBuilder.allTopics
            if !validTopics.contains(topic) {
                let allValid = (["overview"] + validTopics).joined(separator: ", ")
                return ToolResult(
                    toolCallId: "",
                    content: "알 수 없는 주제: \(topic). 사용 가능한 주제: \(allValid)",
                    isError: true
                )
            }
        }

        let response = AppGuideContentBuilder.build(
            topic: topic,
            query: query,
            toolRegistry: toolRegistry
        )

        if response.items.isEmpty {
            let msg: String
            if let query {
                msg = "\"\(query)\"에 대한 가이드 항목을 찾을 수 없습니다. 다른 키워드로 검색하거나, topic 파라미터 없이 전체 검색을 시도해보세요."
            } else {
                msg = "해당 주제의 가이드 항목이 없습니다."
            }
            return ToolResult(toolCallId: "", content: msg)
        }

        Log.tool.info("app.guide: topic=\(topic ?? "nil"), query=\(query ?? "nil"), items=\(response.items.count)")
        return ToolResult(toolCallId: "", content: response.formatted())
    }
}
