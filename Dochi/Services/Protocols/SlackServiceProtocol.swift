import Foundation

// MARK: - Slack Models

struct SlackUser: Codable, Sendable {
    let id: String
    let name: String
    let isBot: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isBot = "is_bot"
    }
}

struct SlackMessage: Codable, Sendable {
    let channelId: String
    let userId: String?
    let text: String
    let threadTs: String?   // thread timestamp (nil for top-level)
    let ts: String          // message timestamp (used as ID)
    let isMention: Bool     // whether bot was @mentioned

    enum CodingKeys: String, CodingKey {
        case channelId = "channel_id"
        case userId = "user_id"
        case text
        case threadTs = "thread_ts"
        case ts
        case isMention = "is_mention"
    }
}

struct SlackChannel: Codable, Sendable {
    let id: String
    let name: String
    let isDM: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case isDM = "is_dm"
    }
}

// MARK: - Slack Chat Mapping

struct SlackChatMapping: Codable, Sendable, Identifiable {
    var id: String { channelId }
    let channelId: String
    var workspaceId: UUID?
    var label: String
    var enabled: Bool

    init(channelId: String, workspaceId: UUID? = nil, label: String, enabled: Bool = true) {
        self.channelId = channelId
        self.workspaceId = workspaceId
        self.label = label
        self.enabled = enabled
    }

    enum CodingKeys: String, CodingKey {
        case channelId = "channel_id"
        case workspaceId = "workspace_id"
        case label, enabled
    }
}

// MARK: - Protocol

@MainActor
protocol SlackServiceProtocol {
    var isConnected: Bool { get }

    /// Connect to Slack using Socket Mode or Events API.
    func connect(botToken: String, appToken: String) async throws
    func disconnect()

    /// Send a message to a channel or DM. Returns the message timestamp.
    func sendMessage(channelId: String, text: String, threadTs: String?) async throws -> String

    /// Update an existing message.
    func updateMessage(channelId: String, ts: String, text: String) async throws

    /// Send a typing indicator.
    func sendTyping(channelId: String) async throws

    /// Get bot identity.
    func authTest(botToken: String) async throws -> SlackUser

    /// Incoming message handler.
    var onMessage: (@MainActor @Sendable (SlackMessage) -> Void)? { get set }
}
