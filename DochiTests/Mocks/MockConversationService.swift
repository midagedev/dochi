import Foundation
@testable import Dochi

@MainActor
final class MockConversationService: ConversationServiceProtocol {
    var conversations: [UUID: Conversation] = [:]

    func list() -> [Conversation] {
        Array(conversations.values).sorted { $0.updatedAt > $1.updatedAt }
    }

    func load(id: UUID) -> Conversation? {
        conversations[id]
    }

    func save(_ conversation: Conversation) {
        conversations[conversation.id] = conversation
    }

    func delete(id: UUID) {
        conversations.removeValue(forKey: id)
    }
}
