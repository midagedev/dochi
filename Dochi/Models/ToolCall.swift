import Foundation

/// LLM이 요청한 도구 호출
struct ToolCall: Identifiable, @unchecked Sendable {
    let id: String
    let name: String
    let arguments: [String: Any]

    // Sendable을 위한 안전한 arguments 저장
    private let argumentsData: Data

    init(id: String, name: String, arguments: [String: Any]) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.argumentsData = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data()
    }

    init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        if let data = argumentsJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            self.arguments = parsed
            self.argumentsData = data
        } else {
            self.arguments = [:]
            self.argumentsData = Data()
        }
    }
}

/// 도구 실행 결과
struct ToolResult: Sendable {
    let toolCallId: String
    let content: String
    let isError: Bool

    init(toolCallId: String, content: String, isError: Bool = false) {
        self.toolCallId = toolCallId
        self.content = content
        self.isError = isError
    }
}

/// LLM 응답 타입
enum LLMResponse: Sendable {
    case text(String)
    case toolCalls([ToolCall])
    case partial(String)  // 스트리밍 중간 응답
}
