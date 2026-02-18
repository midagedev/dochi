import Foundation

enum TaskOpportunitySource: String, Codable, Sendable {
    case calendar
    case kanban
    case reminder
    case memory
}

enum TaskOpportunityActionKind: String, Codable, Sendable {
    case createReminder
    case createKanbanCard

    var buttonTitle: String {
        switch self {
        case .createReminder: return "미리알림 등록"
        case .createKanbanCard: return "칸반 등록"
        }
    }
}

struct TaskOpportunity: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let source: TaskOpportunitySource
    let title: String
    let detail: String
    let actionKind: TaskOpportunityActionKind
    let suggestedTitle: String
    let suggestedNotes: String?
    let dueDateISO8601: String?
    let boardName: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        source: TaskOpportunitySource,
        title: String,
        detail: String,
        actionKind: TaskOpportunityActionKind,
        suggestedTitle: String,
        suggestedNotes: String? = nil,
        dueDateISO8601: String? = nil,
        boardName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.detail = detail
        self.actionKind = actionKind
        self.suggestedTitle = suggestedTitle
        self.suggestedNotes = suggestedNotes
        self.dueDateISO8601 = dueDateISO8601
        self.boardName = boardName
        self.createdAt = createdAt
    }
}

struct TaskOpportunityActionFeedback: Equatable, Sendable {
    let opportunityId: UUID
    let isSuccess: Bool
    let message: String
}
