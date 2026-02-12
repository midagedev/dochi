import Foundation

// MARK: - Stream Event

enum LLMStreamEvent: Sendable {
    case partial(String)
    case toolCallDelta(index: Int, id: String?, name: String?, argumentsDelta: String)
    case done
    case error(LLMError)
}

// MARK: - Stream Accumulator

struct StreamAccumulator: Sendable {
    var text: String = ""
    var toolCalls: [Int: ToolCallAccumulator] = [:]

    /// Token usage reported by the provider (populated from final SSE chunks).
    var inputTokens: Int?
    var outputTokens: Int?

    struct ToolCallAccumulator: Sendable {
        var id: String = ""
        var name: String = ""
        var arguments: String = ""
    }

    var completedToolCalls: [CodableToolCall] {
        toolCalls.sorted(by: { $0.key < $1.key }).map {
            CodableToolCall(id: $0.value.id, name: $0.value.name, argumentsJSON: $0.value.arguments)
        }
    }
}

// MARK: - Provider Adapter Protocol

protocol LLMProviderAdapter: Sendable {
    var provider: LLMProvider { get }

    func buildRequest(
        messages: [Message],
        systemPrompt: String,
        model: String,
        tools: [[String: Any]]?,
        apiKey: String
    ) throws -> URLRequest

    func parseSSELine(_ line: String, accumulated: inout StreamAccumulator) -> LLMStreamEvent?
}
