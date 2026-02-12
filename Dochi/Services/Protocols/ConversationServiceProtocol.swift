import Foundation

@MainActor
protocol ConversationServiceProtocol {
    func list() -> [Conversation]
    func load(id: UUID) -> Conversation?
    func save(conversation: Conversation)
    func delete(id: UUID)
}
