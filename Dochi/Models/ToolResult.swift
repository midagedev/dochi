import Foundation

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
