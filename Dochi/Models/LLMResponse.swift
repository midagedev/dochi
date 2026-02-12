import Foundation

enum LLMResponse: Sendable {
    case text(String)
    case toolCalls([CodableToolCall])
    case partial(String)
}
