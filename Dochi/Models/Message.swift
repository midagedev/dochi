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
    var toolExecutionRecords: [ToolExecutionRecord]?

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date(), toolCalls: [CodableToolCall]? = nil, toolCallId: String? = nil, imageURLs: [URL]? = nil, metadata: MessageMetadata? = nil, toolExecutionRecords: [ToolExecutionRecord]? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.imageURLs = imageURLs
        self.metadata = metadata
        self.toolExecutionRecords = toolExecutionRecords
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(MessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        toolCalls = try container.decodeIfPresent([CodableToolCall].self, forKey: .toolCalls)
        toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
        imageURLs = try container.decodeIfPresent([URL].self, forKey: .imageURLs)
        metadata = try container.decodeIfPresent(MessageMetadata.self, forKey: .metadata)
        toolExecutionRecords = try container.decodeIfPresent([ToolExecutionRecord].self, forKey: .toolExecutionRecords)
    }
}
