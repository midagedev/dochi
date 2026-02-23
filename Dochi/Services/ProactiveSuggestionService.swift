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
    private let llmClient: ProactiveSuggestionLLMClientProtocol?

    // MARK: - Telegram Relay (K-6)

    private var telegramRelay: TelegramProactiveRelayProtocol?

    /// Inject TelegramProactiveRelay for Telegram notification delivery (K-6).
    func setTelegramRelay(_ relay: TelegramProactiveRelayProtocol) {
        self.telegramRelay = relay
    }

    // MARK: - Idle Detection

    private var lastActivityDate: Date = Date()
    private var idleCheckTask: Task<Void, Never>?
    private var lastSuggestionDate: Date?
    private var todayDateString: String = ""
    private var todaySuggestionCount: Int = 0

    private static let maxHistoryCount = 20
    private static let idleCheckIntervalSeconds: UInt64 = 30
    private static let duplicateCooldownHours: TimeInterval = 24 * 3600
    private static let llmConversationLimit = 4
    private static let llmKanbanCardLimit = 4
    private static let llmMemorySnippetLimit = 280

    // MARK: - Init

    init(
        settings: AppSettings,
        contextService: ContextServiceProtocol,
        conversationService: ConversationServiceProtocol,
        sessionContext: SessionContext,
        llmClient: ProactiveSuggestionLLMClientProtocol? = nil
    ) {
        self.settings = settings
        self.contextService = contextService
        self.conversationService = conversationService
        self.sessionContext = sessionContext
        self.llmClient = llmClient
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

        // Disable this suggestion type
        switch suggestion.type {
        case .newsTrend: settings.suggestionTypeNewsEnabled = false
        case .deepDive: settings.suggestionTypeDeepDiveEnabled = false
        case .relatedResearch: settings.suggestionTypeResearchEnabled = false
        case .kanbanCheck: settings.suggestionTypeKanbanEnabled = false
        case .memoryRemind: settings.suggestionTypeMemoryEnabled = false
        case .costReport: settings.suggestionTypeCostEnabled = false
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

        if hasReachedDailyCap() {
            state = .cooldown
            return
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
        guard !hasReachedDailyCap() else {
            state = .cooldown
            return
        }

        let enabledTypes = activeTypes()
        guard !enabledTypes.isEmpty else {
            state = .idle
            return
        }

        if let llmCandidate = await buildLLMCandidate(enabledTypes: enabledTypes) {
            if isDuplicateSuggestion(llmCandidate) {
                state = .idle
                return
            }
            await publishSuggestion(llmCandidate)
            return
        }

        var candidates: [ProactiveSuggestion] = []

        for type in enabledTypes {
            if let candidate = buildCandidate(for: type) {
                if !isDuplicateSuggestion(candidate) {
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
        await publishSuggestion(candidates[0])
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

    func runSuggestionGenerationForTesting() async {
        await generateSuggestion()
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

    private func isDuplicateSuggestion(_ suggestion: ProactiveSuggestion) -> Bool {
        suggestionHistory.contains { record in
            record.title == suggestion.title &&
            record.timestamp.timeIntervalSinceNow > -Self.duplicateCooldownHours
        }
    }

    private func publishSuggestion(_ suggestion: ProactiveSuggestion) async {
        var selected = suggestion
        selected.status = .shown

        currentSuggestion = selected
        todaySuggestionCount += 1
        lastSuggestionDate = Date()
        state = .hasSuggestion
        toastEvents.append(SuggestionToastEvent(suggestion: selected))

        if let telegramRelay {
            await telegramRelay.sendSuggestion(selected)
        }

        Log.app.info("Suggestion generated: \(selected.type.rawValue) — \(selected.title)")
    }

    // MARK: - LLM Suggestion

    private struct LLMConversationSignal {
        let id: UUID
        let title: String
        let lastUserMessage: String?
    }

    private struct LLMKanbanSignal {
        let boardId: UUID
        let boardName: String
        let cardId: UUID
        let cardTitle: String
    }

    private struct LLMContextSnapshot {
        let conversations: [LLMConversationSignal]
        let memorySnippet: String?
        let memoryUserId: String?
        let inProgressCards: [LLMKanbanSignal]
        let recentSuggestionTitles: [String]
    }

    private struct LLMSuggestionPayload: Decodable {
        let shouldSuggest: Bool?
        let type: String
        let title: String
        let body: String
        let suggestedPrompt: String
        let sourceContext: String?
    }

    private func buildLLMCandidate(enabledTypes: [SuggestionType]) async -> ProactiveSuggestion? {
        guard let llmClient else { return nil }

        let snapshot = buildLLMContextSnapshot()
        let systemPrompt = llmSystemPrompt()
        let userPrompt = llmUserPrompt(enabledTypes: enabledTypes, snapshot: snapshot)

        do {
            let raw = try await llmClient.generateSuggestionJSON(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt
            )
            guard let candidate = parseLLMResponse(
                raw,
                enabledTypes: enabledTypes,
                snapshot: snapshot
            ) else {
                Log.llm.debug("Proactive suggestion LLM output was not actionable")
                return nil
            }
            guard !isMetaInstructionSuggestion(candidate) else {
                Log.llm.notice("Proactive suggestion LLM output rejected: meta instruction pattern")
                return nil
            }
            return candidate
        } catch {
            Log.llm.debug("Proactive suggestion LLM generation failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func buildLLMContextSnapshot() -> LLMContextSnapshot {
        let conversations = conversationService.list()
            .prefix(Self.llmConversationLimit)
            .map { conversation in
                LLMConversationSignal(
                    id: conversation.id,
                    title: Self.normalizedSuggestionText(conversation.title, maxLength: 80),
                    lastUserMessage: Self.latestUserMessage(in: conversation)
                )
            }

        let userId = sessionContext.currentUserId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let memorySnippet: String? = {
            guard let userId, !userId.isEmpty else { return nil }
            guard let memory = contextService.loadUserMemory(userId: userId), !memory.isEmpty else { return nil }
            return Self.normalizedSuggestionText(memory, maxLength: Self.llmMemorySnippetLimit)
        }()

        var inProgressCards: [LLMKanbanSignal] = []
        for board in KanbanManager.shared.listBoards() {
            let cards = board.cards.filter {
                $0.column.contains("진행") || $0.column.lowercased().contains("progress")
            }
            for card in cards {
                inProgressCards.append(
                    LLMKanbanSignal(
                        boardId: board.id,
                        boardName: Self.normalizedSuggestionText(board.name, maxLength: 40),
                        cardId: card.id,
                        cardTitle: Self.normalizedSuggestionText(card.title, maxLength: 70)
                    )
                )
                if inProgressCards.count >= Self.llmKanbanCardLimit {
                    break
                }
            }
            if inProgressCards.count >= Self.llmKanbanCardLimit {
                break
            }
        }

        return LLMContextSnapshot(
            conversations: Array(conversations),
            memorySnippet: memorySnippet,
            memoryUserId: userId,
            inProgressCards: inProgressCards,
            recentSuggestionTitles: Array(suggestionHistory.prefix(6).map(\.title))
        )
    }

    private static func latestUserMessage(in conversation: Conversation) -> String? {
        guard let message = conversation.messages.reversed().first(where: { $0.role == .user }) else {
            return nil
        }
        let normalized = normalizedSuggestionText(message.content, maxLength: 120)
        return normalized.isEmpty ? nil : normalized
    }

    private func llmSystemPrompt() -> String {
        """
        너는 Dochi의 프로액티브 제안 큐레이터다.
        목표는 "지금 즉시 실행 가능한 제안 1개"를 만드는 것이다.

        반드시 지켜라:
        1) 제공된 컨텍스트에 없는 내용은 추측하지 않는다.
        2) 메타 지시(도구 호출 규칙, 시스템 프롬프트, datetime/JSON/함수 호출 안내) 제안은 금지한다.
        3) 반복적이고 추상적인 표현(예: "더 자세히 설명드릴까요?")은 피하고 구체적 행동을 제시한다.
        4) 가치 있는 제안이 없으면 shouldSuggest=false 를 반환한다.
        5) 출력은 JSON 객체 하나만 반환한다. Markdown, 코드블록, 설명문 금지.

        JSON schema:
        {
          "shouldSuggest": boolean,
          "type": "newsTrend|deepDive|relatedResearch|kanbanCheck|memoryRemind|costReport",
          "title": "string (max 28 chars)",
          "body": "string (max 90 chars)",
          "suggestedPrompt": "string (사용자가 바로 보낼 문장)",
          "sourceContext": "string (conversation:<id> | memory:<userId> | kanban:<boardId>/<cardId> | usage)"
        }
        """
    }

    private func llmUserPrompt(enabledTypes: [SuggestionType], snapshot: LLMContextSnapshot) -> String {
        var lines: [String] = []
        lines.append("enabledTypes: \(enabledTypes.map(\.rawValue).joined(separator: ", "))")
        lines.append("enabledTypeHints:")
        for type in enabledTypes {
            lines.append("- \(type.rawValue): \(type.displayName)")
        }

        lines.append("recentConversations:")
        if snapshot.conversations.isEmpty {
            lines.append("- (없음)")
        } else {
            for item in snapshot.conversations {
                if let lastUserMessage = item.lastUserMessage, !lastUserMessage.isEmpty {
                    lines.append("- id=\(item.id.uuidString) title=\(item.title) lastUser=\(lastUserMessage)")
                } else {
                    lines.append("- id=\(item.id.uuidString) title=\(item.title)")
                }
            }
        }

        lines.append("memorySnippet:")
        lines.append(snapshot.memorySnippet ?? "(없음)")

        lines.append("kanbanInProgress:")
        if snapshot.inProgressCards.isEmpty {
            lines.append("- (없음)")
        } else {
            for item in snapshot.inProgressCards {
                lines.append("- boardId=\(item.boardId.uuidString) board=\(item.boardName) cardId=\(item.cardId.uuidString) card=\(item.cardTitle)")
            }
        }

        lines.append("recentSuggestionTitles:")
        if snapshot.recentSuggestionTitles.isEmpty {
            lines.append("- (없음)")
        } else {
            for title in snapshot.recentSuggestionTitles {
                lines.append("- \(Self.normalizedSuggestionText(title, maxLength: 60))")
            }
        }

        lines.append("JSON only.")
        return lines.joined(separator: "\n")
    }

    private func parseLLMResponse(
        _ response: String,
        enabledTypes: [SuggestionType],
        snapshot: LLMContextSnapshot
    ) -> ProactiveSuggestion? {
        guard let jsonText = Self.extractFirstJSONObject(from: response) else { return nil }
        guard let data = jsonText.data(using: .utf8) else { return nil }
        guard let payload = try? JSONDecoder().decode(LLMSuggestionPayload.self, from: data) else {
            return nil
        }

        guard payload.shouldSuggest == true else {
            return nil
        }

        guard let type = SuggestionType(rawValue: payload.type),
              enabledTypes.contains(type),
              isContextAvailable(for: type, snapshot: snapshot) else {
            return nil
        }

        let title = Self.normalizedSuggestionText(payload.title, maxLength: 40)
        let body = Self.normalizedSuggestionText(payload.body, maxLength: 160)
        let suggestedPrompt = Self.normalizedSuggestionText(payload.suggestedPrompt, maxLength: 220)
        guard !title.isEmpty, !body.isEmpty, !suggestedPrompt.isEmpty else {
            return nil
        }

        let sourceContext = normalizedSourceContext(
            payload.sourceContext,
            type: type,
            snapshot: snapshot
        )

        return ProactiveSuggestion(
            type: type,
            title: title,
            body: body,
            suggestedPrompt: suggestedPrompt,
            sourceContext: sourceContext
        )
    }

    private func isContextAvailable(for type: SuggestionType, snapshot: LLMContextSnapshot) -> Bool {
        switch type {
        case .newsTrend, .deepDive, .relatedResearch:
            return !snapshot.conversations.isEmpty
        case .kanbanCheck:
            return !snapshot.inProgressCards.isEmpty
        case .memoryRemind:
            return snapshot.memorySnippet != nil
        case .costReport:
            return true
        }
    }

    private func normalizedSourceContext(
        _ sourceContext: String?,
        type: SuggestionType,
        snapshot: LLMContextSnapshot
    ) -> String {
        let normalized = Self.normalizedSuggestionText(sourceContext ?? "", maxLength: 120)
        if !normalized.isEmpty {
            return normalized
        }

        switch type {
        case .newsTrend, .deepDive, .relatedResearch:
            if let first = snapshot.conversations.first {
                return "conversation:\(first.id)"
            }
            return "conversation:recent"
        case .kanbanCheck:
            if let first = snapshot.inProgressCards.first {
                return "kanban:\(first.boardId)/\(first.cardId)"
            }
            return "kanban"
        case .memoryRemind:
            if let userId = snapshot.memoryUserId, !userId.isEmpty {
                return "memory:\(userId)"
            }
            return "memory"
        case .costReport:
            return "usage"
        }
    }

    private func isMetaInstructionSuggestion(_ suggestion: ProactiveSuggestion) -> Bool {
        let combined = [
            suggestion.title,
            suggestion.body,
            suggestion.suggestedPrompt,
        ].joined(separator: " ").lowercased()

        let bannedPatterns = [
            "시스템 프롬프트",
            "system prompt",
            "도구 호출",
            "tool call",
            "함수 호출",
            "function call",
            "datetime 도구",
            "json schema",
            "prompt injection",
        ]

        return bannedPatterns.contains { combined.contains($0) }
    }

    private static func extractFirstJSONObject(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            return trimmed
        }

        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else {
            return nil
        }
        return String(trimmed[start...end])
    }

    private static func normalizedSuggestionText(_ text: String, maxLength: Int) -> String {
        let collapsedWhitespace = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsedWhitespace.count > maxLength else {
            return collapsedWhitespace
        }

        let index = collapsedWhitespace.index(
            collapsedWhitespace.startIndex,
            offsetBy: max(0, maxLength)
        )
        return String(collapsedWhitespace[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func hasReachedDailyCap() -> Bool {
        let cap = max(settings.proactiveDailyCap, 0)
        return todaySuggestionCount >= cap
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func dateString(from date: Date) -> String {
        dayFormatter.string(from: date)
    }
}

@MainActor
protocol ProactiveSuggestionLLMClientProtocol {
    func generateSuggestionJSON(systemPrompt: String, userPrompt: String) async throws -> String
}

@MainActor
final class NativeProactiveSuggestionLLMClient: ProactiveSuggestionLLMClientProtocol {
    private let settings: AppSettings
    private let keychainService: KeychainServiceProtocol
    private let nativeAgentLoopService: NativeAgentLoopService

    init(
        settings: AppSettings,
        keychainService: KeychainServiceProtocol,
        nativeAgentLoopService: NativeAgentLoopService
    ) {
        self.settings = settings
        self.keychainService = keychainService
        self.nativeAgentLoopService = nativeAgentLoopService
    }

    func generateSuggestionJSON(systemPrompt: String, userPrompt: String) async throws -> String {
        let provider = settings.currentProvider
        let model = resolvedModel(for: provider)
        guard !model.isEmpty else {
            throw NativeLLMError(
                code: .modelNotFound,
                message: "No configured model for proactive suggestion",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }

        let apiKey = loadNativeAPIKey(for: provider)
        if provider.requiresAPIKey, apiKey == nil {
            throw NativeLLMError(
                code: .authentication,
                message: "API key is not configured for \(provider.rawValue)",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }

        let request = NativeLLMRequest(
            provider: provider,
            model: model,
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            messages: [NativeLLMMessage(role: .user, text: userPrompt)],
            tools: [],
            maxTokens: 400,
            temperature: 0.2,
            endpointURL: nativeEndpointURL(for: provider),
            timeoutSeconds: 20
        )

        var accumulated = ""
        var doneText: String?

        for try await event in nativeAgentLoopService.run(request: request) {
            switch event.kind {
            case .partial:
                if let delta = event.text {
                    accumulated += delta
                }
            case .done:
                doneText = event.text ?? accumulated
            case .error:
                if let error = event.error {
                    throw error
                }
                throw NativeLLMError(
                    code: .unknown,
                    message: "Native loop returned error event without payload",
                    statusCode: nil,
                    retryAfterSeconds: nil
                )
            case .toolUse, .toolResult:
                continue
            }
        }

        let text = (doneText ?? accumulated).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw NativeLLMError(
                code: .invalidResponse,
                message: "Native loop returned empty suggestion response",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }
        return text
    }

    private func resolvedModel(for provider: LLMProvider) -> String {
        let configured = settings.llmModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty {
            return configured
        }
        return provider.models.first ?? provider.onboardingDefaultModel
    }

    private func loadNativeAPIKey(for provider: LLMProvider) -> String? {
        guard provider.requiresAPIKey else { return nil }

        if let key = keychainService.load(account: provider.keychainAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty {
            return key
        }

        if let legacyAccount = provider.legacyAPIKeyAccount,
           let legacy = keychainService.load(account: legacyAccount)?
           .trimmingCharacters(in: .whitespacesAndNewlines),
           !legacy.isEmpty {
            return legacy
        }

        return nil
    }

    private func nativeEndpointURL(for provider: LLMProvider) -> URL? {
        switch provider {
        case .ollama:
            return localChatCompletionsEndpoint(
                baseURLString: settings.ollamaBaseURL,
                fallback: provider.apiURL
            )
        case .lmStudio:
            return localChatCompletionsEndpoint(
                baseURLString: settings.lmStudioBaseURL,
                fallback: provider.apiURL
            )
        default:
            return nil
        }
    }

    private func localChatCompletionsEndpoint(baseURLString: String, fallback: URL) -> URL {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let baseURL = URL(string: trimmed) else {
            return fallback
        }

        let normalizedPath = baseURL.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath.hasSuffix("v1/chat/completions") {
            return baseURL
        }
        if normalizedPath.hasSuffix("chat/completions") {
            return baseURL
        }
        if normalizedPath.hasSuffix("v1/models") {
            return baseURL
                .deletingLastPathComponent()
                .appendingPathComponent("chat")
                .appendingPathComponent("completions")
        }
        if normalizedPath.hasSuffix("v1") {
            return baseURL
                .appendingPathComponent("chat")
                .appendingPathComponent("completions")
        }
        if normalizedPath.hasSuffix("api/tags") {
            return baseURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("v1")
                .appendingPathComponent("chat")
                .appendingPathComponent("completions")
        }
        return baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
    }
}
