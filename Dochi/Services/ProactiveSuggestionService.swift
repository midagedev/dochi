import Foundation
import os

/// K-2: 프로액티브 제안 서비스 — 유휴 감지 + 컨텍스트 분석 + 제안 생성
@MainActor
@Observable
final class ProactiveSuggestionService: ProactiveSuggestionServiceProtocol {
    // MARK: - State

    private(set) var currentSuggestion: ProactiveSuggestion?
    private(set) var suggestionHistory: [ProactiveSuggestion] = []
    private(set) var state: ProactiveSuggestionState = .idle
    var isPaused: Bool = false
    private(set) var toastEvents: [SuggestionToastEvent] = []

    // MARK: - Dependencies

    private let settings: AppSettings
    private let contextService: ContextServiceProtocol
    private let conversationService: ConversationServiceProtocol
    private let sessionContext: SessionContext

    // MARK: - Idle Detection

    private var lastActivityDate: Date = Date()
    private var idleCheckTask: Task<Void, Never>?
    private var lastSuggestionDate: Date?
    private var todayDateString: String = ""
    private var todaySuggestionCount: Int = 0

    private static let maxHistoryCount = 20
    private static let idleCheckIntervalSeconds: UInt64 = 30
    private static let duplicateCooldownHours: TimeInterval = 24 * 3600

    // MARK: - Init

    init(
        settings: AppSettings,
        llmService: LLMServiceProtocol? = nil,
        contextService: ContextServiceProtocol,
        conversationService: ConversationServiceProtocol = ConversationService(),
        keychainService: KeychainServiceProtocol? = nil,
        sessionContext: SessionContext
    ) {
        self.settings = settings
        self.contextService = contextService
        self.conversationService = conversationService
        self.sessionContext = sessionContext
        todayDateString = Self.dateString(from: Date())
        Log.app.info("ProactiveSuggestionService initialized")
    }

    // MARK: - Lifecycle

    func start() {
        guard settings.proactiveSuggestionEnabled else {
            state = .disabled
            return
        }
        stop()
        state = .idle
        idleCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.idleCheckIntervalSeconds * 1_000_000_000)
                guard let self, !Task.isCancelled else { break }
                await self.checkIdle()
            }
        }
        Log.app.info("ProactiveSuggestionService started")
    }

    func stop() {
        idleCheckTask?.cancel()
        idleCheckTask = nil
        state = .idle
    }

    // MARK: - Activity Recording

    func recordActivity() {
        lastActivityDate = Date()
    }

    // MARK: - Suggestion Actions

    func acceptSuggestion(_ suggestion: ProactiveSuggestion) {
        var updated = suggestion
        updated.status = .accepted
        addToHistory(updated)
        currentSuggestion = nil
        state = .cooldown
        Log.app.info("Suggestion accepted: \(suggestion.title)")
    }

    func deferSuggestion(_ suggestion: ProactiveSuggestion) {
        var updated = suggestion
        updated.status = .deferred
        addToHistory(updated)
        currentSuggestion = nil
        state = .cooldown
        Log.app.info("Suggestion deferred: \(suggestion.title)")
    }

    func dismissSuggestionType(_ suggestion: ProactiveSuggestion) {
        var updated = suggestion
        updated.status = .dismissed
        addToHistory(updated)
        currentSuggestion = nil
        state = .cooldown

        // Disable this suggestion type via per-type settings key
        let key = suggestion.type.settingsKey
        switch key {
        case "suggestionTypeNewsEnabled": settings.suggestionTypeNewsEnabled = false
        case "suggestionTypeDeepDiveEnabled": settings.suggestionTypeDeepDiveEnabled = false
        case "suggestionTypeResearchEnabled": settings.suggestionTypeResearchEnabled = false
        case "suggestionTypeKanbanEnabled": settings.suggestionTypeKanbanEnabled = false
        case "suggestionTypeMemoryEnabled": settings.suggestionTypeMemoryEnabled = false
        case "suggestionTypeCostEnabled": settings.suggestionTypeCostEnabled = false
        default: break
        }
        Log.app.info("Suggestion type dismissed: \(suggestion.type.rawValue)")
    }

    func dismissToast(id: UUID) {
        toastEvents.removeAll { $0.id == id }
    }

    // MARK: - Idle Check

    private func checkIdle() async {
        guard settings.proactiveSuggestionEnabled else {
            state = .disabled
            return
        }
        guard !isPaused else { return }
        guard currentSuggestion == nil else { return }

        // Reset daily count if new day
        let today = Self.dateString(from: Date())
        if today != todayDateString {
            todayDateString = today
            todaySuggestionCount = 0
        }

        let elapsed = Date().timeIntervalSince(lastActivityDate)
        let idleThreshold = TimeInterval(settings.proactiveSuggestionIdleMinutes * 60)
        guard elapsed >= idleThreshold else { return }

        // Cooldown after last suggestion
        if let lastDate = lastSuggestionDate {
            let cooldown = TimeInterval(settings.proactiveSuggestionCooldownMinutes * 60)
            guard Date().timeIntervalSince(lastDate) >= cooldown else {
                state = .cooldown
                return
            }
        }

        // Quiet hours check (reuse heartbeat quiet hours)
        if settings.proactiveSuggestionQuietHoursEnabled, isQuietHours() {
            return
        }

        state = .analyzing
        await generateSuggestion()
    }

    // MARK: - Suggestion Generation

    private func generateSuggestion() async {
        let enabledTypes = activeTypes()
        guard !enabledTypes.isEmpty else {
            state = .idle
            return
        }

        var candidates: [ProactiveSuggestion] = []

        for type in enabledTypes {
            if let candidate = buildCandidate(for: type) {
                // Duplicate filter: skip if same title was suggested in last 24h
                let isDuplicate = suggestionHistory.contains { record in
                    record.title == candidate.title &&
                    record.timestamp.timeIntervalSinceNow > -Self.duplicateCooldownHours
                }
                if !isDuplicate {
                    candidates.append(candidate)
                }
            }
        }

        guard !candidates.isEmpty else {
            state = .idle
            return
        }

        // Select by priority
        candidates.sort { $0.type.priority < $1.type.priority }
        var selected = candidates[0]
        selected.status = .shown

        currentSuggestion = selected
        todaySuggestionCount += 1
        lastSuggestionDate = Date()
        state = .hasSuggestion

        // Add toast event
        toastEvents.append(SuggestionToastEvent(suggestion: selected))

        Log.app.info("Suggestion generated: \(selected.type.rawValue) — \(selected.title)")
    }

    private func buildCandidate(for type: SuggestionType) -> ProactiveSuggestion? {
        switch type {
        case .kanbanCheck:
            return buildKanbanCandidate()
        case .memoryRemind:
            return buildMemoryCandidate()
        case .costReport:
            return buildCostReportCandidate()
        case .newsTrend:
            return buildNewsTrendCandidate()
        case .deepDive:
            return buildDeepDiveCandidate()
        case .relatedResearch:
            return buildRelatedResearchCandidate()
        }
    }

    private func buildKanbanCandidate() -> ProactiveSuggestion? {
        let boards = KanbanManager.shared.listBoards()
        for board in boards {
            let inProgress = board.cards.filter { $0.column.contains("진행") || $0.column.lowercased().contains("progress") }
            if let card = inProgress.first {
                return ProactiveSuggestion(
                    type: .kanbanCheck,
                    title: "칸반 진행 상황 체크",
                    body: "'\(card.title)' 카드가 진행 중입니다. 도움이 필요하신가요?",
                    suggestedPrompt: "칸반 보드에서 진행 중인 '\(card.title)' 카드 상태를 확인하고 도움이 필요한지 알려줘",
                    sourceContext: "kanban:\(board.id)/\(card.id)"
                )
            }
        }
        return nil
    }

    private func buildMemoryCandidate() -> ProactiveSuggestion? {
        guard let userId = sessionContext.currentUserId, !userId.isEmpty else { return nil }
        guard let memory = contextService.loadUserMemory(userId: userId), !memory.isEmpty else { return nil }

        let timePatterns = ["이번 주", "내일", "다음 주", "오늘까지", "이번 달", "까지"]
        for pattern in timePatterns {
            if memory.contains(pattern) {
                if let range = memory.range(of: pattern) {
                    let start = memory.index(range.lowerBound, offsetBy: -30, limitedBy: memory.startIndex) ?? memory.startIndex
                    let end = memory.index(range.upperBound, offsetBy: 30, limitedBy: memory.endIndex) ?? memory.endIndex
                    let snippet = String(memory[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)

                    return ProactiveSuggestion(
                        type: .memoryRemind,
                        title: "메모리에 기한 관련 메모가 있습니다",
                        body: "'\(pattern)' 관련 메모를 확인해보세요: \(snippet)",
                        suggestedPrompt: "내 메모리에서 '\(pattern)'과 관련된 내용을 확인하고 리마인드해줘",
                        sourceContext: "memory:\(userId)"
                    )
                }
            }
        }
        return nil
    }

    private func buildCostReportCandidate() -> ProactiveSuggestion? {
        return ProactiveSuggestion(
            type: .costReport,
            title: "이번 주 AI 사용량 확인",
            body: "이번 주 AI 사용 현황을 확인해보세요.",
            suggestedPrompt: "이번 주 AI 사용량 요약을 보여줘",
            sourceContext: "usage"
        )
    }

    private func buildNewsTrendCandidate() -> ProactiveSuggestion? {
        let conversations = conversationService.list()
        guard !conversations.isEmpty else { return nil }

        let recent = conversations.prefix(3)
        let topics = recent.compactMap { conv -> String? in
            let title = conv.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }
        guard let topic = topics.first else { return nil }

        return ProactiveSuggestion(
            type: .newsTrend,
            title: "관심있으실 만한 소식",
            body: "최근 '\(topic)' 관련 대화를 하셨습니다. 관련 최신 소식을 알아볼까요?",
            suggestedPrompt: "최근 \(topic) 관련 뉴스와 트렌드를 조사해줘",
            sourceContext: "conversation:recent"
        )
    }

    private func buildDeepDiveCandidate() -> ProactiveSuggestion? {
        let conversations = conversationService.list()
        guard conversations.count >= 2 else { return nil }

        let topic = conversations[0].title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty else { return nil }

        return ProactiveSuggestion(
            type: .deepDive,
            title: "이전 대화 주제 심화",
            body: "'\(topic)'에 대해 더 자세히 설명드릴까요?",
            suggestedPrompt: "\(topic)에 대해 더 자세히 설명해줘",
            sourceContext: "conversation:\(conversations[0].id)"
        )
    }

    private func buildRelatedResearchCandidate() -> ProactiveSuggestion? {
        let conversations = conversationService.list()
        guard !conversations.isEmpty else { return nil }

        let topic = conversations[0].title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty else { return nil }

        return ProactiveSuggestion(
            type: .relatedResearch,
            title: "관련 자료 조사",
            body: "'\(topic)' 관련 최신 자료를 조사해볼까요?",
            suggestedPrompt: "\(topic) 관련 최신 블로그나 문서를 조사해줘",
            sourceContext: "conversation:\(conversations[0].id)"
        )
    }

    // MARK: - Helpers

    private func activeTypes() -> [SuggestionType] {
        return SuggestionType.allCases.filter { type in
            isTypeEnabled(type)
        }
    }

    private func isTypeEnabled(_ type: SuggestionType) -> Bool {
        switch type {
        case .newsTrend: return settings.suggestionTypeNewsEnabled
        case .deepDive: return settings.suggestionTypeDeepDiveEnabled
        case .relatedResearch: return settings.suggestionTypeResearchEnabled
        case .kanbanCheck: return settings.suggestionTypeKanbanEnabled
        case .memoryRemind: return settings.suggestionTypeMemoryEnabled
        case .costReport: return settings.suggestionTypeCostEnabled
        }
    }

    private func isQuietHours() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        let quietStart = settings.heartbeatQuietHoursStart
        let quietEnd = settings.heartbeatQuietHoursEnd
        if quietStart > quietEnd {
            return hour >= quietStart || hour < quietEnd
        } else if quietStart < quietEnd {
            return hour >= quietStart && hour < quietEnd
        }
        return false
    }

    private func addToHistory(_ suggestion: ProactiveSuggestion) {
        suggestionHistory.insert(suggestion, at: 0)
        if suggestionHistory.count > Self.maxHistoryCount {
            suggestionHistory = Array(suggestionHistory.prefix(Self.maxHistoryCount))
        }
    }

    private static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
