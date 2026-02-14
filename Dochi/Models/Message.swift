import Foundation

enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

/// Metadata from the LLM exchange that produced this message.
struct MessageMetadata: Codable, Sendable, Equatable {
    let provider: String
    let model: String
    let inputTokens: Int?
    let outputTokens: Int?
    let totalLatency: TimeInterval?
    let wasFallback: Bool

    var totalTokensDisplay: String {
        let input = inputTokens ?? 0
        let output = outputTokens ?? 0
        return input + output > 0 ? "\(input + output)" : "N/A"
    }

    var latencyDisplay: String {
        guard let latency = totalLatency else { return "N/A" }
        return String(format: "%.1f초", latency)
    }

    /// Short display: model name · response time
    var shortDisplay: String {
        let parts = [model, latencyDisplay].filter { $0 != "N/A" }
        return parts.joined(separator: " · ")
    }
}

struct Message: Codable, Identifiable, Sendable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    var toolCalls: [CodableToolCall]?
    var toolCallId: String?
    var imageURLs: [URL]?
    var metadata: MessageMetadata?

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date(), toolCalls: [CodableToolCall]? = nil, toolCallId: String? = nil, imageURLs: [URL]? = nil, metadata: MessageMetadata? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.imageURLs = imageURLs
        self.metadata = metadata
    }
}
