import Foundation
import os

// MARK: - Create Board

@MainActor
final class KanbanCreateBoardTool: BuiltInToolProtocol {
    let name = "kanban.create_board"
    let category: ToolCategory = .safe
    let description = "새 칸반 보드를 생성합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "보드 이름"],
                "columns": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "컬럼 목록 (기본: [할 일, 진행 중, 완료])",
                ] as [String: Any],
            ] as [String: Any],
            "required": ["name"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let name = arguments["name"] as? String, !name.isEmpty else {
            return ToolResult(toolCallId: "", content: "name 파라미터가 필요합니다.", isError: true)
        }
        let columns = arguments["columns"] as? [String]
        let board = KanbanManager.shared.createBoard(name: name, columns: columns)
        Log.tool.info("Created kanban board: \(name)")
        return ToolResult(toolCallId: "", content: "칸반 보드 생성: \(name) (ID: \(board.id.uuidString.prefix(8)))\n컬럼: \(board.columns.joined(separator: " → "))")
    }
}

// MARK: - List Boards

@MainActor
final class KanbanListBoardsTool: BuiltInToolProtocol {
    let name = "kanban.list_boards"
    let category: ToolCategory = .safe
    let description = "칸반 보드 목록을 조회합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [:] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let boards = KanbanManager.shared.listBoards()
        guard !boards.isEmpty else {
            return ToolResult(toolCallId: "", content: "칸반 보드가 없습니다. kanban.create_board로 생성하세요.")
        }

        let lines = boards.map { board in
            let cardCount = board.cards.count
            let columnsSummary = board.columns.map { col in
                let count = board.cards.filter { $0.column == col }.count
                return "\(col)(\(count))"
            }.joined(separator: " | ")
            return "- \(board.name) [\(board.id.uuidString.prefix(8))] — \(cardCount)개 카드 [\(columnsSummary)]"
        }

        return ToolResult(toolCallId: "", content: "칸반 보드 (\(boards.count)개):\n\(lines.joined(separator: "\n"))")
    }
}

// MARK: - List Cards

@MainActor
final class KanbanListCardsTool: BuiltInToolProtocol {
    let name = "kanban.list"
    let category: ToolCategory = .safe
    let description = "칸반 보드의 카드 목록을 컬럼별로 조회합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "board_name": ["type": "string", "description": "보드 이름 (부분 일치)"],
                "column": ["type": "string", "description": "특정 컬럼만 필터"],
            ] as [String: Any],
            "required": ["board_name"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let boardName = arguments["board_name"] as? String else {
            return ToolResult(toolCallId: "", content: "board_name 파라미터가 필요합니다.", isError: true)
        }
        guard let board = KanbanManager.shared.board(name: boardName) else {
            return ToolResult(toolCallId: "", content: "'\(boardName)' 보드를 찾을 수 없습니다.", isError: true)
        }

        let filterColumn = arguments["column"] as? String
        var output = "📋 \(board.name)\n"

        for col in board.columns {
            if let filter = filterColumn, !col.localizedCaseInsensitiveContains(filter) { continue }

            let cards = board.cards.filter { $0.column == col }
                .sorted { $0.priority.sortOrder < $1.priority.sortOrder }
            output += "\n── \(col) (\(cards.count)) ──\n"

            if cards.isEmpty {
                output += "  (비어있음)\n"
            } else {
                for card in cards {
                    let priorityIcon = card.priority.icon
                    let labels = card.labels.isEmpty ? "" : " [\(card.labels.joined(separator: ", "))]"
                    let assignee = card.assignee.map { " @\($0)" } ?? ""
                    output += "  \(priorityIcon) \(card.title)\(labels)\(assignee) [\(card.id.uuidString.prefix(8))]\n"
                }
            }
        }

        return ToolResult(toolCallId: "", content: output)
    }
}

// MARK: - Add Card

@MainActor
final class KanbanAddCardTool: BuiltInToolProtocol {
    let name = "kanban.add_card"
    let category: ToolCategory = .safe
    let description = "칸반 보드에 카드를 추가합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "board_name": ["type": "string", "description": "보드 이름"],
                "title": ["type": "string", "description": "카드 제목"],
                "column": ["type": "string", "description": "추가할 컬럼 (기본: 첫 번째 컬럼)"],
                "priority": [
                    "type": "string",
                    "enum": ["low", "medium", "high", "urgent"],
                    "description": "우선순위 (기본: medium)",
                ],
                "description": ["type": "string", "description": "카드 설명"],
                "labels": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "라벨 목록",
                ] as [String: Any],
                "assignee": ["type": "string", "description": "담당자"],
            ] as [String: Any],
            "required": ["board_name", "title"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let boardName = arguments["board_name"] as? String else {
            return ToolResult(toolCallId: "", content: "board_name 파라미터가 필요합니다.", isError: true)
        }
        guard let title = arguments["title"] as? String, !title.isEmpty else {
            return ToolResult(toolCallId: "", content: "title 파라미터가 필요합니다.", isError: true)
        }
        guard let board = KanbanManager.shared.board(name: boardName) else {
            return ToolResult(toolCallId: "", content: "'\(boardName)' 보드를 찾을 수 없습니다.", isError: true)
        }

        let column = arguments["column"] as? String
        let priorityStr = arguments["priority"] as? String ?? "medium"
        let priority = KanbanCard.Priority(rawValue: priorityStr) ?? .medium
        let description = arguments["description"] as? String ?? ""
        let labels = arguments["labels"] as? [String] ?? []
        let assignee = arguments["assignee"] as? String

        guard let card = KanbanManager.shared.addCard(
            boardId: board.id,
            title: title,
            column: column,
            priority: priority,
            description: description,
            labels: labels,
            assignee: assignee
        ) else {
            return ToolResult(toolCallId: "", content: "카드 추가 실패. 컬럼 이름을 확인해주세요.", isError: true)
        }

        Log.tool.info("Added kanban card: \(title) to \(board.name)")
        return ToolResult(toolCallId: "", content: "카드 추가: \(card.priority.icon) \(title) → \(card.column) [\(card.id.uuidString.prefix(8))]")
    }
}

// MARK: - Move Card

@MainActor
final class KanbanMoveCardTool: BuiltInToolProtocol {
    let name = "kanban.move_card"
    let category: ToolCategory = .safe
    let description = "칸반 카드를 다른 컬럼으로 이동합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "board_name": ["type": "string", "description": "보드 이름"],
                "card_title": ["type": "string", "description": "카드 제목 (부분 일치)"],
                "card_id": ["type": "string", "description": "카드 ID (8자 prefix)"],
                "to_column": ["type": "string", "description": "이동할 컬럼"],
            ] as [String: Any],
            "required": ["board_name", "to_column"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let boardName = arguments["board_name"] as? String else {
            return ToolResult(toolCallId: "", content: "board_name 파라미터가 필요합니다.", isError: true)
        }
        guard let toColumn = arguments["to_column"] as? String else {
            return ToolResult(toolCallId: "", content: "to_column 파라미터가 필요합니다.", isError: true)
        }
        guard let board = KanbanManager.shared.board(name: boardName) else {
            return ToolResult(toolCallId: "", content: "'\(boardName)' 보드를 찾을 수 없습니다.", isError: true)
        }

        let card: KanbanCard?
        if let cardIdPrefix = arguments["card_id"] as? String {
            card = board.cards.first { $0.id.uuidString.lowercased().hasPrefix(cardIdPrefix.lowercased()) }
        } else if let cardTitle = arguments["card_title"] as? String {
            card = board.cards.first { $0.title.localizedCaseInsensitiveContains(cardTitle) }
        } else {
            return ToolResult(toolCallId: "", content: "card_title 또는 card_id가 필요합니다.", isError: true)
        }

        guard let card else {
            return ToolResult(toolCallId: "", content: "카드를 찾을 수 없습니다.", isError: true)
        }

        let fromColumn = card.column
        guard KanbanManager.shared.moveCard(boardId: board.id, cardId: card.id, toColumn: toColumn) else {
            return ToolResult(toolCallId: "", content: "카드 이동 실패. 컬럼 이름을 확인해주세요.", isError: true)
        }

        Log.tool.info("Moved kanban card: \(card.title) → \(toColumn)")
        return ToolResult(toolCallId: "", content: "카드 이동: \(card.title) (\(fromColumn) → \(toColumn))")
    }
}

// MARK: - Update Card

@MainActor
final class KanbanUpdateCardTool: BuiltInToolProtocol {
    let name = "kanban.update_card"
    let category: ToolCategory = .safe
    let description = "칸반 카드의 속성을 수정합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "board_name": ["type": "string", "description": "보드 이름"],
                "card_title": ["type": "string", "description": "카드 제목 (부분 일치)"],
                "card_id": ["type": "string", "description": "카드 ID (8자 prefix)"],
                "new_title": ["type": "string", "description": "새 제목"],
                "description": ["type": "string", "description": "새 설명"],
                "priority": [
                    "type": "string",
                    "enum": ["low", "medium", "high", "urgent"],
                    "description": "새 우선순위",
                ],
                "labels": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "새 라벨 목록",
                ] as [String: Any],
                "assignee": ["type": "string", "description": "새 담당자"],
            ] as [String: Any],
            "required": ["board_name"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let boardName = arguments["board_name"] as? String else {
            return ToolResult(toolCallId: "", content: "board_name 파라미터가 필요합니다.", isError: true)
        }
        guard let board = KanbanManager.shared.board(name: boardName) else {
            return ToolResult(toolCallId: "", content: "'\(boardName)' 보드를 찾을 수 없습니다.", isError: true)
        }

        let card: KanbanCard?
        if let cardIdPrefix = arguments["card_id"] as? String {
            card = board.cards.first { $0.id.uuidString.lowercased().hasPrefix(cardIdPrefix.lowercased()) }
        } else if let cardTitle = arguments["card_title"] as? String {
            card = board.cards.first { $0.title.localizedCaseInsensitiveContains(cardTitle) }
        } else {
            return ToolResult(toolCallId: "", content: "card_title 또는 card_id가 필요합니다.", isError: true)
        }

        guard let card else {
            return ToolResult(toolCallId: "", content: "카드를 찾을 수 없습니다.", isError: true)
        }

        let newTitle = arguments["new_title"] as? String
        let newDescription = arguments["description"] as? String
        let newPriority = (arguments["priority"] as? String).flatMap(KanbanCard.Priority.init)
        let newLabels = arguments["labels"] as? [String]
        let newAssignee = arguments["assignee"] as? String

        guard KanbanManager.shared.updateCard(
            boardId: board.id,
            cardId: card.id,
            title: newTitle,
            description: newDescription,
            priority: newPriority,
            labels: newLabels,
            assignee: newAssignee
        ) else {
            return ToolResult(toolCallId: "", content: "카드 수정 실패.", isError: true)
        }

        Log.tool.info("Updated kanban card: \(card.title)")
        return ToolResult(toolCallId: "", content: "카드 수정 완료: \(newTitle ?? card.title)")
    }
}

// MARK: - Delete Card

@MainActor
final class KanbanDeleteCardTool: BuiltInToolProtocol {
    let name = "kanban.delete_card"
    let category: ToolCategory = .safe
    let description = "칸반 카드를 삭제합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "board_name": ["type": "string", "description": "보드 이름"],
                "card_title": ["type": "string", "description": "카드 제목 (부분 일치)"],
                "card_id": ["type": "string", "description": "카드 ID (8자 prefix)"],
            ] as [String: Any],
            "required": ["board_name"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let boardName = arguments["board_name"] as? String else {
            return ToolResult(toolCallId: "", content: "board_name 파라미터가 필요합니다.", isError: true)
        }
        guard let board = KanbanManager.shared.board(name: boardName) else {
            return ToolResult(toolCallId: "", content: "'\(boardName)' 보드를 찾을 수 없습니다.", isError: true)
        }

        let card: KanbanCard?
        if let cardIdPrefix = arguments["card_id"] as? String {
            card = board.cards.first { $0.id.uuidString.lowercased().hasPrefix(cardIdPrefix.lowercased()) }
        } else if let cardTitle = arguments["card_title"] as? String {
            card = board.cards.first { $0.title.localizedCaseInsensitiveContains(cardTitle) }
        } else {
            return ToolResult(toolCallId: "", content: "card_title 또는 card_id가 필요합니다.", isError: true)
        }

        guard let card else {
            return ToolResult(toolCallId: "", content: "카드를 찾을 수 없습니다.", isError: true)
        }

        guard KanbanManager.shared.deleteCard(boardId: board.id, cardId: card.id) else {
            return ToolResult(toolCallId: "", content: "카드 삭제 실패.", isError: true)
        }

        Log.tool.info("Deleted kanban card: \(card.title)")
        return ToolResult(toolCallId: "", content: "카드 삭제: \(card.title)")
    }
}

// MARK: - Priority Helpers

extension KanbanCard.Priority {
    var icon: String {
        switch self {
        case .low: "⬜"
        case .medium: "🟦"
        case .high: "🟧"
        case .urgent: "🟥"
        }
    }

    var sortOrder: Int {
        switch self {
        case .urgent: 0
        case .high: 1
        case .medium: 2
        case .low: 3
        }
    }
}
