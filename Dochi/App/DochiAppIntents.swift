import AppIntents
import Foundation

// MARK: - AskDochiIntent

/// "도치에게 물어보기" Shortcut Action
struct AskDochiIntent: AppIntent {
    static let title: LocalizedStringResource = "도치에게 물어보기"
    static let description: IntentDescription = "도치에게 질문하고 AI 응답을 받습니다."

    @Parameter(title: "질문", description: "도치에게 물어볼 내용")
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let service = DochiShortcutService.shared

        guard service.isConfigured else {
            service.recordExecution(
                actionName: "도치에게 물어보기",
                success: false,
                resultSummary: "서비스 미초기화",
                errorMessage: ShortcutError.notConfigured.localizedDescription
            )
            throw ShortcutError.notConfigured
        }

        do {
            let response = try await service.askDochi(question: question)
            service.recordExecution(
                actionName: "도치에게 물어보기",
                success: true,
                resultSummary: response
            )
            return .result(value: response)
        } catch {
            service.recordExecution(
                actionName: "도치에게 물어보기",
                success: false,
                resultSummary: "실패",
                errorMessage: error.localizedDescription
            )
            throw error
        }
    }
}

// MARK: - AddMemoIntent

/// "도치 메모 추가" Shortcut Action
struct AddMemoIntent: AppIntent {
    static let title: LocalizedStringResource = "도치 메모 추가"
    static let description: IntentDescription = "도치의 메모리에 메모를 추가합니다."

    @Parameter(title: "메모 내용", description: "저장할 메모 내용")
    var content: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let service = DochiShortcutService.shared

        guard service.isConfigured else {
            service.recordExecution(
                actionName: "도치 메모 추가",
                success: false,
                resultSummary: "서비스 미초기화",
                errorMessage: ShortcutError.notConfigured.localizedDescription
            )
            throw ShortcutError.notConfigured
        }

        do {
            let result = try service.addMemo(content: content)
            service.recordExecution(
                actionName: "도치 메모 추가",
                success: true,
                resultSummary: result
            )
            return .result(value: result)
        } catch {
            service.recordExecution(
                actionName: "도치 메모 추가",
                success: false,
                resultSummary: "실패",
                errorMessage: error.localizedDescription
            )
            throw error
        }
    }
}

// MARK: - CreateKanbanCardIntent

/// "도치 칸반 카드 생성" Shortcut Action
struct CreateKanbanCardIntent: AppIntent {
    static let title: LocalizedStringResource = "도치 칸반 카드 생성"
    static let description: IntentDescription = "도치 칸반 보드에 새 카드를 생성합니다."

    @Parameter(title: "제목", description: "카드 제목")
    var title: String

    @Parameter(title: "설명", description: "카드 설명 (선택)")
    var cardDescription: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let service = DochiShortcutService.shared

        guard service.isConfigured else {
            service.recordExecution(
                actionName: "도치 칸반 카드 생성",
                success: false,
                resultSummary: "서비스 미초기화",
                errorMessage: ShortcutError.notConfigured.localizedDescription
            )
            throw ShortcutError.notConfigured
        }

        do {
            let result = try service.createKanbanCard(title: title, description: cardDescription)
            service.recordExecution(
                actionName: "도치 칸반 카드 생성",
                success: true,
                resultSummary: result
            )
            return .result(value: result)
        } catch {
            service.recordExecution(
                actionName: "도치 칸반 카드 생성",
                success: false,
                resultSummary: "실패",
                errorMessage: error.localizedDescription
            )
            throw error
        }
    }
}

// MARK: - TodayBriefingIntent

/// "도치 오늘 브리핑" Shortcut Action
struct TodayBriefingIntent: AppIntent {
    static let title: LocalizedStringResource = "도치 오늘 브리핑"
    static let description: IntentDescription = "오늘의 일정, 칸반 현황 등을 요약합니다."

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let service = DochiShortcutService.shared

        guard service.isConfigured else {
            service.recordExecution(
                actionName: "도치 오늘 브리핑",
                success: false,
                resultSummary: "서비스 미초기화",
                errorMessage: ShortcutError.notConfigured.localizedDescription
            )
            throw ShortcutError.notConfigured
        }

        do {
            let result = try await service.todayBriefing()
            service.recordExecution(
                actionName: "도치 오늘 브리핑",
                success: true,
                resultSummary: result
            )
            return .result(value: result)
        } catch {
            service.recordExecution(
                actionName: "도치 오늘 브리핑",
                success: false,
                resultSummary: "실패",
                errorMessage: error.localizedDescription
            )
            throw error
        }
    }
}
