import Foundation

struct Message: Identifiable, Codable, Sendable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    var toolCalls: [ToolCall]?
    var imageURLs: [URL]?

    enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
    }

    init(role: Role, content: String, toolCalls: [ToolCall]? = nil, imageURLs: [URL]? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.toolCalls = toolCalls
        self.imageURLs = imageURLs
    }

    // Custom Codable for toolCalls
    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, toolCalls, imageURLs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)

        // ToolCalls는 optional하게 디코딩
        if let toolCallsData = try container.decodeIfPresent([CodableToolCall].self, forKey: .toolCalls) {
            toolCalls = toolCallsData.map { $0.toToolCall() }
        } else {
            toolCalls = nil
        }

        imageURLs = try container.decodeIfPresent([URL].self, forKey: .imageURLs)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)

        if let toolCalls = toolCalls {
            let codableToolCalls = toolCalls.map { CodableToolCall(from: $0) }
            try container.encode(codableToolCalls, forKey: .toolCalls)
        }

        try container.encodeIfPresent(imageURLs, forKey: .imageURLs)
    }
}

// Codable wrapper for ToolCall
private struct CodableToolCall: Codable {
    let id: String
    let name: String
    let argumentsJSON: String

    init(from toolCall: ToolCall) {
        self.id = toolCall.id
        self.name = toolCall.name
        self.argumentsJSON = (try? String(data: JSONSerialization.data(withJSONObject: toolCall.arguments), encoding: .utf8)) ?? "{}"
    }

    func toToolCall() -> ToolCall {
        ToolCall(id: id, name: name, argumentsJSON: argumentsJSON)
    }
}
