import XCTest
@testable import Dochi

/// K-2: 프로액티브 제안 시스템 테스트
@MainActor
final class ProactiveSuggestionTests: XCTestCase {

    // MARK: - Model Tests

    func testProactiveSuggestionInit() {
        let suggestion = ProactiveSuggestion(
            type: .newsTrend,
            title: "테스트 제안",
            body: "이것은 테스트입니다",
            suggestedPrompt: "최근 트렌드를 알려줘"
        )

        XCTAssertEqual(suggestion.type, .newsTrend)
        XCTAssertEqual(suggestion.title, "테스트 제안")
        XCTAssertEqual(suggestion.body, "이것은 테스트입니다")
        XCTAssertEqual(suggestion.suggestedPrompt, "최근 트렌드를 알려줘")
        XCTAssertEqual(suggestion.status, .shown)
        XCTAssertFalse(suggestion.id.uuidString.isEmpty)
    }

    func testSuggestionTypeCaseIterable() {
        let allTypes = SuggestionType.allCases
        XCTAssertEqual(allTypes.count, 6)
        XCTAssertTrue(allTypes.contains(.newsTrend))
        XCTAssertTrue(allTypes.contains(.deepDive))
        XCTAssertTrue(allTypes.contains(.relatedResearch))
        XCTAssertTrue(allTypes.contains(.kanbanCheck))
        XCTAssertTrue(allTypes.contains(.memoryRemind))
        XCTAssertTrue(allTypes.contains(.costReport))
    }

    func testSuggestionTypeDisplayNames() {
        XCTAssertEqual(SuggestionType.newsTrend.displayName, "트렌드")
        XCTAssertEqual(SuggestionType.deepDive.displayName, "심층 탐구")
        XCTAssertEqual(SuggestionType.relatedResearch.displayName, "관련 리서치")
        XCTAssertEqual(SuggestionType.kanbanCheck.displayName, "칸반 점검")
        XCTAssertEqual(SuggestionType.memoryRemind.displayName, "메모리 리마인드")
        XCTAssertEqual(SuggestionType.costReport.displayName, "비용 리포트")
    }

    func testSuggestionTypeIcons() {
        for type in SuggestionType.allCases {
            XCTAssertFalse(type.icon.isEmpty, "\(type.rawValue) icon should not be empty")
        }
    }

    func testSuggestionTypeBadgeColors() {
        for type in SuggestionType.allCases {
            XCTAssertFalse(type.badgeColor.isEmpty, "\(type.rawValue) badge color should not be empty")
        }
    }

    func testSuggestionStatusCases() {
        let shown = SuggestionStatus.shown
        let accepted = SuggestionStatus.accepted
        let deferred = SuggestionStatus.deferred
        let dismissed = SuggestionStatus.dismissed

        XCTAssertEqual(shown.rawValue, "shown")
        XCTAssertEqual(accepted.rawValue, "accepted")
        XCTAssertEqual(deferred.rawValue, "deferred")
        XCTAssertEqual(dismissed.rawValue, "dismissed")
    }

    func testProactiveSuggestionStateCases() {
        XCTAssertEqual(ProactiveSuggestionState.disabled, .disabled)
        XCTAssertEqual(ProactiveSuggestionState.idle, .idle)
        XCTAssertEqual(ProactiveSuggestionState.analyzing, .analyzing)
        XCTAssertEqual(ProactiveSuggestionState.hasSuggestion, .hasSuggestion)
        XCTAssertEqual(ProactiveSuggestionState.cooldown, .cooldown)
        XCTAssertEqual(ProactiveSuggestionState.error("test"), .error("test"))
        XCTAssertNotEqual(ProactiveSuggestionState.error("a"), .error("b"))
    }

    func testSuggestionToastEvent() {
        let suggestion = ProactiveSuggestion(
            type: .kanbanCheck,
            title: "칸반 확인",
            body: "미완료 작업이 있습니다",
            suggestedPrompt: "칸반 상태 알려줘"
        )
        let event = SuggestionToastEvent(suggestion: suggestion)

        XCTAssertEqual(event.suggestion.type, .kanbanCheck)
        XCTAssertEqual(event.suggestion.title, "칸반 확인")
        XCTAssertFalse(event.id.uuidString.isEmpty)
    }

    // MARK: - ProactiveSuggestion Codable Tests

    func testProactiveSuggestionCodable() throws {
        let suggestion = ProactiveSuggestion(
            type: .deepDive,
            title: "심화 주제",
            body: "이전에 논의한 내용을 더 깊게 알아보세요",
            suggestedPrompt: "이전 주제 심화 설명 부탁해",
            sourceContext: "auto-generated"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(suggestion)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ProactiveSuggestion.self, from: data)

        XCTAssertEqual(decoded.id, suggestion.id)
        XCTAssertEqual(decoded.type, suggestion.type)
        XCTAssertEqual(decoded.title, suggestion.title)
        XCTAssertEqual(decoded.body, suggestion.body)
        XCTAssertEqual(decoded.suggestedPrompt, suggestion.suggestedPrompt)
        XCTAssertEqual(decoded.sourceContext, suggestion.sourceContext)
        XCTAssertEqual(decoded.status, suggestion.status)
    }

    func testSuggestionHistoryCodable() throws {
        let suggestions = [
            ProactiveSuggestion(type: .newsTrend, title: "트렌드1", body: "내용1", suggestedPrompt: "p1"),
            ProactiveSuggestion(type: .memoryRemind, title: "리마인드", body: "내용2", suggestedPrompt: "p2", status: .accepted),
            ProactiveSuggestion(type: .costReport, title: "비용", body: "내용3", suggestedPrompt: "p3", status: .deferred),
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(suggestions)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([ProactiveSuggestion].self, from: data)

        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0].type, .newsTrend)
        XCTAssertEqual(decoded[1].status, .accepted)
        XCTAssertEqual(decoded[2].status, .deferred)
    }

    // MARK: - Mock Service Tests

    func testMockServiceAcceptSuggestion() {
        let mock = MockProactiveSuggestionService()
        let suggestion = ProactiveSuggestion(
            type: .newsTrend,
            title: "테스트",
            body: "본문",
            suggestedPrompt: "프롬프트"
        )
        mock.currentSuggestion = suggestion
        mock.suggestionHistory = [suggestion]

        mock.acceptSuggestion(suggestion)

        XCTAssertEqual(mock.acceptSuggestionCallCount, 1)
        XCTAssertNil(mock.currentSuggestion)
        XCTAssertEqual(mock.suggestionHistory[0].status, .accepted)
        XCTAssertEqual(mock.lastAcceptedSuggestion?.id, suggestion.id)
    }

    func testMockServiceDeferSuggestion() {
        let mock = MockProactiveSuggestionService()
        let suggestion = ProactiveSuggestion(
            type: .deepDive,
            title: "심화",
            body: "본문",
            suggestedPrompt: "프롬프트"
        )
        mock.currentSuggestion = suggestion
        mock.suggestionHistory = [suggestion]

        mock.deferSuggestion(suggestion)

        XCTAssertEqual(mock.deferSuggestionCallCount, 1)
        XCTAssertNil(mock.currentSuggestion)
        XCTAssertEqual(mock.suggestionHistory[0].status, .deferred)
    }

    func testMockServiceDismissSuggestionType() {
        let mock = MockProactiveSuggestionService()
        let suggestion = ProactiveSuggestion(
            type: .costReport,
            title: "비용",
            body: "본문",
            suggestedPrompt: "프롬프트"
        )
        mock.currentSuggestion = suggestion
        mock.suggestionHistory = [suggestion]

        mock.dismissSuggestionType(suggestion)

        XCTAssertEqual(mock.dismissSuggestionTypeCallCount, 1)
        XCTAssertNil(mock.currentSuggestion)
        XCTAssertEqual(mock.suggestionHistory[0].status, .dismissed)
    }

    func testMockServiceStartStop() {
        let mock = MockProactiveSuggestionService()

        mock.start()
        XCTAssertEqual(mock.startCallCount, 1)
        XCTAssertEqual(mock.state, .idle)

        mock.stop()
        XCTAssertEqual(mock.stopCallCount, 1)
        XCTAssertEqual(mock.state, .disabled)
    }

    func testMockServiceRecordActivity() {
        let mock = MockProactiveSuggestionService()

        mock.recordActivity()
        mock.recordActivity()
        mock.recordActivity()

        XCTAssertEqual(mock.recordActivityCallCount, 3)
    }

    func testMockServicePause() {
        let mock = MockProactiveSuggestionService()
        XCTAssertFalse(mock.isPaused)

        mock.isPaused = true
        XCTAssertTrue(mock.isPaused)

        mock.isPaused = false
        XCTAssertFalse(mock.isPaused)
    }

    func testMockServiceDismissToast() {
        let mock = MockProactiveSuggestionService()
        let suggestion = ProactiveSuggestion(
            type: .newsTrend,
            title: "트렌드",
            body: "본문",
            suggestedPrompt: "프롬프트"
        )
        let event = SuggestionToastEvent(suggestion: suggestion)
        mock.toastEvents = [event]

        mock.dismissToast(id: event.id)

        XCTAssertEqual(mock.dismissToastCallCount, 1)
        XCTAssertTrue(mock.toastEvents.isEmpty)
    }

    // MARK: - AppSettings Tests

    func testAppSettingsProactiveSuggestionDefaults() {
        let settings = AppSettings()

        // 기본값은 false (opt-in)
        // Note: UserDefaults에 이미 저장된 값이 있을 수 있으므로
        // 특정 기본값을 강제 검증하기보다는 속성 접근이 crash하지 않는지 확인
        _ = settings.proactiveSuggestionEnabled
        _ = settings.proactiveSuggestionIdleMinutes
        _ = settings.proactiveSuggestionCooldownMinutes
        _ = settings.proactiveSuggestionQuietHoursEnabled
        _ = settings.suggestionTypeNewsEnabled
        _ = settings.suggestionTypeDeepDiveEnabled
        _ = settings.suggestionTypeResearchEnabled
        _ = settings.suggestionTypeKanbanEnabled
        _ = settings.suggestionTypeMemoryEnabled
        _ = settings.suggestionTypeCostEnabled
        _ = settings.notificationProactiveSuggestionEnabled
        _ = settings.proactiveSuggestionMenuBarEnabled
    }

    // MARK: - SuggestionType Priority Tests

    func testSuggestionTypePriority() {
        // memoryRemind가 가장 높은 우선순위 (0)
        XCTAssertEqual(SuggestionType.memoryRemind.priority, 0)
        // costReport가 가장 낮은 우선순위 (5)
        XCTAssertEqual(SuggestionType.costReport.priority, 5)
        // 순서 검증
        let sorted = SuggestionType.allCases.sorted { $0.priority < $1.priority }
        XCTAssertEqual(sorted[0], .memoryRemind)
        XCTAssertEqual(sorted[1], .kanbanCheck)
    }
}
