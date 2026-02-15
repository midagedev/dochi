import Foundation

// MARK: - FeedbackRating

enum FeedbackRating: String, Codable, Sendable {
    case positive
    case negative
}

// MARK: - FeedbackCategory

enum FeedbackCategory: String, Codable, CaseIterable, Sendable {
    case inaccurate
    case unhelpful
    case tooLong
    case tooShort
    case missedContext
    case wrongTone
    case other

    var displayName: String {
        switch self {
        case .inaccurate: return "부정확한 정보"
        case .unhelpful: return "도움이 안 됨"
        case .tooLong: return "너무 길어요"
        case .tooShort: return "너무 짧아요"
        case .missedContext: return "맥락을 놓침"
        case .wrongTone: return "어조가 맞지 않음"
        case .other: return "기타"
        }
    }
}

// MARK: - FeedbackEntry

struct FeedbackEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let messageId: UUID
    let conversationId: UUID
    let rating: FeedbackRating
    var category: FeedbackCategory?
    var comment: String?
    let agentName: String
    let provider: String
    let model: String
    let timestamp: Date

    init(
        id: UUID = UUID(),
        messageId: UUID,
        conversationId: UUID,
        rating: FeedbackRating,
        category: FeedbackCategory? = nil,
        comment: String? = nil,
        agentName: String,
        provider: String,
        model: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.messageId = messageId
        self.conversationId = conversationId
        self.rating = rating
        self.category = category
        self.comment = comment
        self.agentName = agentName
        self.provider = provider
        self.model = model
        self.timestamp = timestamp
    }
}

// MARK: - ModelSatisfaction

struct ModelSatisfaction: Identifiable, Sendable {
    var id: String { model }
    let model: String
    let provider: String
    let totalCount: Int
    let positiveCount: Int

    var satisfactionRate: Double {
        guard totalCount > 0 else { return 0.0 }
        return Double(positiveCount) / Double(totalCount)
    }

    var isWarning: Bool {
        totalCount >= 10 && satisfactionRate < 0.6
    }
}

// MARK: - AgentSatisfaction

struct AgentSatisfaction: Identifiable, Sendable {
    var id: String { agentName }
    let agentName: String
    let totalCount: Int
    let positiveCount: Int

    var satisfactionRate: Double {
        guard totalCount > 0 else { return 0.0 }
        return Double(positiveCount) / Double(totalCount)
    }
}

// MARK: - CategoryCount

struct CategoryCount: Identifiable, Sendable {
    var id: String { category.rawValue }
    let category: FeedbackCategory
    let count: Int
}
