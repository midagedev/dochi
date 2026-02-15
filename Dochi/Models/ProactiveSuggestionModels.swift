import Foundation

// MARK: - K-2: Proactive Suggestion Models

enum SuggestionType: String, Codable, Sendable, CaseIterable {
    case newsTrend
    case deepDive
    case relatedResearch
    case kanbanCheck
    case memoryRemind
    case costReport

    var icon: String {
        switch self {
        case .newsTrend: return "newspaper"
        case .deepDive: return "text.book.closed"
        case .relatedResearch: return "doc.text.magnifyingglass"
        case .kanbanCheck: return "checklist"
        case .memoryRemind: return "brain"
        case .costReport: return "chart.bar"
        }
    }

    var actionLabel: String {
        switch self {
        case .newsTrend: return "알아보기"
        case .deepDive: return "설명 듣기"
        case .relatedResearch: return "자료 보기"
        case .kanbanCheck: return "칸반 보기"
        case .memoryRemind: return "확인하기"
        case .costReport: return "상세 보기"
        }
    }

    var displayName: String {
        switch self {
        case .newsTrend: return "트렌드"
        case .deepDive: return "심층 탐구"
        case .relatedResearch: return "관련 리서치"
        case .kanbanCheck: return "칸반 점검"
        case .memoryRemind: return "메모리 리마인드"
        case .costReport: return "비용 리포트"
        }
    }

    var badgeColor: String {
        switch self {
        case .newsTrend: return "blue"
        case .deepDive: return "purple"
        case .relatedResearch: return "teal"
        case .kanbanCheck: return "orange"
        case .memoryRemind: return "green"
        case .costReport: return "red"
        }
    }

    /// Priority for selection (lower = higher priority)
    var priority: Int {
        switch self {
        case .memoryRemind: return 0
        case .kanbanCheck: return 1
        case .newsTrend: return 2
        case .deepDive: return 3
        case .relatedResearch: return 4
        case .costReport: return 5
        }
    }

    /// AppSettings key suffix for per-type toggle
    var settingsKey: String {
        switch self {
        case .newsTrend: return "suggestionTypeNewsEnabled"
        case .deepDive: return "suggestionTypeDeepDiveEnabled"
        case .relatedResearch: return "suggestionTypeResearchEnabled"
        case .kanbanCheck: return "suggestionTypeKanbanEnabled"
        case .memoryRemind: return "suggestionTypeMemoryEnabled"
        case .costReport: return "suggestionTypeCostEnabled"
        }
    }
}

struct ProactiveSuggestion: Identifiable, Codable, Sendable {
    let id: UUID
    let type: SuggestionType
    let title: String
    let body: String
    let suggestedPrompt: String
    let sourceContext: String
    let timestamp: Date
    var status: SuggestionStatus

    init(
        id: UUID = UUID(),
        type: SuggestionType,
        title: String,
        body: String,
        suggestedPrompt: String,
        sourceContext: String = "",
        timestamp: Date = Date(),
        status: SuggestionStatus = .shown
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.suggestedPrompt = suggestedPrompt
        self.sourceContext = sourceContext
        self.timestamp = timestamp
        self.status = status
    }
}

enum SuggestionStatus: String, Codable, Sendable {
    case shown
    case accepted
    case deferred
    case dismissed
}

enum ProactiveSuggestionState: Sendable, Equatable {
    case disabled
    case idle
    case analyzing
    case hasSuggestion
    case cooldown
    case error(String)
}

struct SuggestionToastEvent: Identifiable, Sendable {
    let id: UUID
    let suggestion: ProactiveSuggestion
    let timestamp: Date

    init(suggestion: ProactiveSuggestion) {
        self.id = UUID()
        self.suggestion = suggestion
        self.timestamp = Date()
    }
}
