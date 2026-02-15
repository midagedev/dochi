import Foundation

/// Apple Shortcuts 연동을 위한 싱글턴 서비스.
/// DochiApp.init()에서 서비스 인스턴스를 주입받아 AppIntent에서 사용한다.
@MainActor
final class DochiShortcutService {
    static let shared = DochiShortcutService()

    // MARK: - Injected Services

    private(set) var contextService: ContextServiceProtocol?
    private(set) var keychainService: KeychainServiceProtocol?
    private(set) var settings: AppSettings?
    private(set) var llmService: LLMServiceProtocol?
    private(set) var heartbeatService: HeartbeatService?

    // MARK: - Execution Log

    private let logStore = ShortcutExecutionLogStore()

    var isConfigured: Bool {
        contextService != nil && keychainService != nil && settings != nil
    }

    // MARK: - Configuration

    func configure(
        contextService: ContextServiceProtocol,
        keychainService: KeychainServiceProtocol,
        settings: AppSettings,
        llmService: LLMServiceProtocol,
        heartbeatService: HeartbeatService
    ) {
        self.contextService = contextService
        self.keychainService = keychainService
        self.settings = settings
        self.llmService = llmService
        self.heartbeatService = heartbeatService
        Log.app.info("DochiShortcutService configured")
    }

    // MARK: - Ask Dochi

    func askDochi(question: String) async throws -> String {
        guard let settings, let keychainService, let llmService else {
            throw ShortcutError.notConfigured
        }

        let provider = LLMProvider(rawValue: settings.llmProvider) ?? .openai
        let model = settings.llmModel

        guard let apiKey = keychainService.load(account: provider.keychainAccount), !apiKey.isEmpty else {
            if provider.requiresAPIKey {
                throw ShortcutError.apiKeyNotSet
            } else {
                // Local providers don't need API key
                return try await performLLMCall(llmService: llmService, question: question, provider: provider, model: model, apiKey: "")
            }
        }

        return try await performLLMCall(llmService: llmService, question: question, provider: provider, model: model, apiKey: apiKey)
    }

    private func performLLMCall(
        llmService: LLMServiceProtocol,
        question: String,
        provider: LLMProvider,
        model: String,
        apiKey: String
    ) async throws -> String {
        let systemPrompt = contextService?.loadBaseSystemPrompt() ?? "당신은 도치라는 AI 비서입니다. 간결하고 도움이 되는 답변을 합니다."
        let messages = [Message(role: .user, content: question)]

        let response = try await llmService.send(
            messages: messages,
            systemPrompt: systemPrompt,
            model: model,
            provider: provider,
            apiKey: apiKey,
            tools: nil,
            onPartial: { _ in }
        )

        switch response {
        case .text(let text):
            return text
        case .partial(let text):
            return text
        case .toolCalls:
            return "도구 호출이 필요한 요청입니다. Shortcuts에서는 도구 실행이 제한됩니다."
        }
    }

    // MARK: - Add Memo

    func addMemo(content: String) throws -> String {
        guard let contextService, let settings else {
            throw ShortcutError.notConfigured
        }

        let userId = settings.defaultUserId
        if userId.isEmpty {
            // No user set — append to workspace memory
            let workspaceId = UUID(uuidString: settings.currentWorkspaceId)
                ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            contextService.appendWorkspaceMemory(workspaceId: workspaceId, content: content)
            return "워크스페이스 메모리에 메모를 추가했습니다."
        } else {
            contextService.appendUserMemory(userId: userId, content: content)
            return "개인 메모리에 메모를 추가했습니다."
        }
    }

    // MARK: - Create Kanban Card

    func createKanbanCard(title: String, description: String?) throws -> String {
        let boards = KanbanManager.shared.listBoards()

        guard let board = boards.first else {
            // Create a default board
            let newBoard = KanbanManager.shared.createBoard(name: "기본 보드")
            guard let card = KanbanManager.shared.addCard(
                boardId: newBoard.id,
                title: title,
                description: description ?? ""
            ) else {
                throw ShortcutError.kanbanError("카드 생성에 실패했습니다.")
            }
            return "'\(newBoard.name)' 보드에 '\(card.title)' 카드를 생성했습니다."
        }

        let targetColumn = board.columns.first ?? "백로그"
        guard let card = KanbanManager.shared.addCard(
            boardId: board.id,
            title: title,
            column: targetColumn,
            description: description ?? ""
        ) else {
            throw ShortcutError.kanbanError("카드 생성에 실패했습니다.")
        }

        return "'\(board.name)' 보드의 '\(targetColumn)' 컬럼에 '\(card.title)' 카드를 생성했습니다."
    }

    // MARK: - Today Briefing

    func todayBriefing() async throws -> String {
        guard let settings, let keychainService, let llmService else {
            throw ShortcutError.notConfigured
        }

        // Gather heartbeat-style context
        var contextParts: [String] = []

        // Kanban — in progress cards
        let boards = KanbanManager.shared.listBoards()
        var kanbanLines: [String] = []
        for board in boards {
            let inProgress = board.cards.filter { $0.column.contains("진행") }
            for card in inProgress {
                kanbanLines.append("- \(card.title) [\(board.name)]")
            }
        }
        if !kanbanLines.isEmpty {
            contextParts.append("진행 중인 칸반 작업:\n\(kanbanLines.joined(separator: "\n"))")
        }

        // Pending cards (backlog/ready)
        var pendingLines: [String] = []
        for board in boards {
            let pending = board.cards.filter { !$0.column.contains("완료") && !$0.column.contains("진행") }
            for card in pending.prefix(5) {
                pendingLines.append("- \(card.title) [\(card.column)]")
            }
        }
        if !pendingLines.isEmpty {
            contextParts.append("대기 중인 작업:\n\(pendingLines.joined(separator: "\n"))")
        }

        // Memory context
        if let contextService {
            let userId = settings.defaultUserId
            if !userId.isEmpty, let memory = contextService.loadUserMemory(userId: userId) {
                let preview = String(memory.prefix(200))
                contextParts.append("사용자 메모리 (미리보기):\n\(preview)")
            }
        }

        if contextParts.isEmpty {
            return "오늘 특별히 확인할 사항이 없습니다. 칸반 보드에 작업을 추가하거나 메모를 남겨보세요."
        }

        // Use LLM to summarize
        let provider = LLMProvider(rawValue: settings.llmProvider) ?? .openai
        let model = settings.llmModel

        let apiKey: String
        if provider.requiresAPIKey {
            guard let key = keychainService.load(account: provider.keychainAccount), !key.isEmpty else {
                // Fall back to simple text summary if no API key
                return "오늘의 요약:\n\n\(contextParts.joined(separator: "\n\n"))"
            }
            apiKey = key
        } else {
            apiKey = ""
        }

        let summaryPrompt = "아래 정보를 기반으로 오늘 하루 브리핑을 간결하게 정리해줘. 3~5줄 이내로."
        let userMessage = "\(summaryPrompt)\n\n\(contextParts.joined(separator: "\n\n"))"

        let messages = [Message(role: .user, content: userMessage)]
        let systemPrompt = "당신은 도치라는 AI 비서입니다. 간결하고 친근한 브리핑을 제공합니다."

        do {
            let response = try await llmService.send(
                messages: messages,
                systemPrompt: systemPrompt,
                model: model,
                provider: provider,
                apiKey: apiKey,
                tools: nil,
                onPartial: { _ in }
            )

            switch response {
            case .text(let text):
                return text
            case .partial(let text):
                return text
            case .toolCalls:
                return "오늘의 요약:\n\n\(contextParts.joined(separator: "\n\n"))"
            }
        } catch {
            // LLM failure — return raw context
            return "오늘의 요약:\n\n\(contextParts.joined(separator: "\n\n"))"
        }
    }

    // MARK: - Execution Log

    func recordExecution(actionName: String, success: Bool, resultSummary: String, errorMessage: String? = nil) {
        let log = ShortcutExecutionLog(
            actionName: actionName,
            success: success,
            resultSummary: String(resultSummary.prefix(200)),
            errorMessage: errorMessage
        )
        logStore.appendLog(log)
        Log.app.info("Shortcut executed: \(actionName), success: \(success)")
    }

    func loadExecutionLogs() -> [ShortcutExecutionLog] {
        logStore.loadLogs()
    }

    // MARK: - Private Init

    private init() {}
}

// MARK: - ShortcutError

enum ShortcutError: LocalizedError {
    case notConfigured
    case apiKeyNotSet
    case networkError(String)
    case kanbanError(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "도치 앱이 아직 초기화되지 않았습니다. 앱을 먼저 실행해주세요."
        case .apiKeyNotSet:
            return "API 키가 설정되지 않았습니다. 도치 설정에서 API 키를 입력해주세요."
        case .networkError(let message):
            return "네트워크 오류: \(message)"
        case .kanbanError(let message):
            return "칸반 오류: \(message)"
        case .timeout:
            return "요청 시간이 초과되었습니다."
        }
    }
}
