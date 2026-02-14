import Foundation

/// 대화 필터 조건
struct ConversationFilter: Sendable {
    var showFavoritesOnly: Bool = false
    var selectedTags: Set<String> = []
    var source: ConversationSource?
    var dateFrom: Date?
    var dateTo: Date?

    var isActive: Bool {
        showFavoritesOnly
            || !selectedTags.isEmpty
            || source != nil
            || dateFrom != nil
            || dateTo != nil
    }

    var activeCount: Int {
        var count = 0
        if showFavoritesOnly { count += 1 }
        count += selectedTags.count
        if source != nil { count += 1 }
        if dateFrom != nil || dateTo != nil { count += 1 }
        return count
    }

    func matches(_ conversation: Conversation) -> Bool {
        if showFavoritesOnly && !conversation.isFavorite { return false }
        if !selectedTags.isEmpty {
            let conversationTagSet = Set(conversation.tags)
            if selectedTags.isDisjoint(with: conversationTagSet) { return false }
        }
        if let source, conversation.source != source { return false }
        if let dateFrom, conversation.updatedAt < dateFrom { return false }
        if let dateTo, conversation.updatedAt > dateTo { return false }
        return true
    }

    mutating func reset() {
        showFavoritesOnly = false
        selectedTags.removeAll()
        source = nil
        dateFrom = nil
        dateTo = nil
    }
}
