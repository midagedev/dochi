import XCTest
@testable import Dochi

@MainActor
final class KanbanTests: XCTestCase {
    private var tempDir: URL!
    private var manager: KanbanManager!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KanbanTests_\(UUID().uuidString)")
        manager = KanbanManager(storageDir: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - KanbanBoard Model

    func testDefaultColumns() {
        XCTAssertEqual(KanbanBoard.defaultColumns, ["백로그", "준비", "진행 중", "검토", "완료"])
    }

    func testBoardInitDefaults() {
        let board = KanbanBoard(name: "테스트")
        XCTAssertEqual(board.name, "테스트")
        XCTAssertEqual(board.columns, KanbanBoard.defaultColumns)
        XCTAssertTrue(board.cards.isEmpty)
    }

    func testBoardInitCustomColumns() {
        let board = KanbanBoard(name: "Custom", columns: ["A", "B"])
        XCTAssertEqual(board.columns, ["A", "B"])
    }

    // MARK: - KanbanCard Model

    func testCardInitDefaults() {
        let card = KanbanCard(title: "할 일", column: "백로그")
        XCTAssertEqual(card.title, "할 일")
        XCTAssertEqual(card.column, "백로그")
        XCTAssertEqual(card.priority, .medium)
        XCTAssertTrue(card.labels.isEmpty)
        XCTAssertNil(card.assignee)
        XCTAssertTrue(card.transitions.isEmpty)
    }

    func testCardPriorityIcons() {
        XCTAssertEqual(KanbanCard.Priority.low.icon, "⬜")
        XCTAssertEqual(KanbanCard.Priority.medium.icon, "🟦")
        XCTAssertEqual(KanbanCard.Priority.high.icon, "🟧")
        XCTAssertEqual(KanbanCard.Priority.urgent.icon, "🟥")
    }

    func testCardPrioritySortOrder() {
        XCTAssertLessThan(KanbanCard.Priority.urgent.sortOrder, KanbanCard.Priority.high.sortOrder)
        XCTAssertLessThan(KanbanCard.Priority.high.sortOrder, KanbanCard.Priority.medium.sortOrder)
        XCTAssertLessThan(KanbanCard.Priority.medium.sortOrder, KanbanCard.Priority.low.sortOrder)
    }

    // MARK: - StatusTransition Model

    func testStatusTransitionInit() {
        let t = StatusTransition(fromColumn: "백로그", toColumn: "진행 중")
        XCTAssertEqual(t.fromColumn, "백로그")
        XCTAssertEqual(t.toColumn, "진행 중")
    }

    // MARK: - Board CRUD

    func testCreateBoard() {
        let board = manager.createBoard(name: "프로젝트")
        XCTAssertEqual(board.name, "프로젝트")
        XCTAssertEqual(board.columns, KanbanBoard.defaultColumns)
        XCTAssertEqual(manager.listBoards().count, 1)
    }

    func testCreateBoardCustomColumns() {
        let board = manager.createBoard(name: "심플", columns: ["할 일", "완료"])
        XCTAssertEqual(board.columns, ["할 일", "완료"])
    }

    func testListBoardsSortedByCreation() {
        let b1 = manager.createBoard(name: "First")
        let b2 = manager.createBoard(name: "Second")
        let boards = manager.listBoards()
        XCTAssertEqual(boards.count, 2)
        XCTAssertEqual(boards[0].id, b1.id)
        XCTAssertEqual(boards[1].id, b2.id)
    }

    func testBoardById() {
        let board = manager.createBoard(name: "Find Me")
        XCTAssertNotNil(manager.board(id: board.id))
        XCTAssertNil(manager.board(id: UUID()))
    }

    func testBoardByName() {
        _ = manager.createBoard(name: "프로젝트 A")
        XCTAssertNotNil(manager.board(name: "프로젝트"))
        XCTAssertNotNil(manager.board(name: "프로젝트 a")) // case insensitive
        XCTAssertNil(manager.board(name: "없는보드"))
    }

    func testDeleteBoard() {
        let board = manager.createBoard(name: "삭제할 보드")
        XCTAssertEqual(manager.listBoards().count, 1)
        manager.deleteBoard(id: board.id)
        XCTAssertEqual(manager.listBoards().count, 0)
        XCTAssertNil(manager.board(id: board.id))
    }

    // MARK: - Card CRUD

    func testAddCard() {
        let board = manager.createBoard(name: "보드")
        let card = manager.addCard(boardId: board.id, title: "새 카드")
        XCTAssertNotNil(card)
        XCTAssertEqual(card?.title, "새 카드")
        XCTAssertEqual(card?.column, "백로그") // first column
        XCTAssertEqual(card?.priority, .medium)
    }

    func testAddCardToSpecificColumn() {
        let board = manager.createBoard(name: "보드")
        let card = manager.addCard(boardId: board.id, title: "검토 카드", column: "검토")
        XCTAssertEqual(card?.column, "검토")
    }

    func testAddCardToInvalidColumn() {
        let board = manager.createBoard(name: "보드")
        let card = manager.addCard(boardId: board.id, title: "실패", column: "없는컬럼")
        XCTAssertNil(card)
    }

    func testAddCardToNonExistentBoard() {
        let card = manager.addCard(boardId: UUID(), title: "실패")
        XCTAssertNil(card)
    }

    func testAddCardWithAllProperties() {
        let board = manager.createBoard(name: "보드")
        let card = manager.addCard(
            boardId: board.id,
            title: "완전한 카드",
            column: "준비",
            priority: .urgent,
            description: "상세 설명",
            labels: ["버그", "긴급"],
            assignee: "홍길동"
        )
        XCTAssertEqual(card?.priority, .urgent)
        XCTAssertEqual(card?.description, "상세 설명")
        XCTAssertEqual(card?.labels, ["버그", "긴급"])
        XCTAssertEqual(card?.assignee, "홍길동")
    }

    func testMoveCard() {
        let board = manager.createBoard(name: "보드")
        let card = manager.addCard(boardId: board.id, title: "이동 카드")!
        let result = manager.moveCard(boardId: board.id, cardId: card.id, toColumn: "진행 중")
        XCTAssertTrue(result)

        let updated = manager.board(id: board.id)!.cards.first!
        XCTAssertEqual(updated.column, "진행 중")
    }

    func testMoveCardRecordsTransition() {
        let board = manager.createBoard(name: "보드")
        let card = manager.addCard(boardId: board.id, title: "전이 카드")!
        _ = manager.moveCard(boardId: board.id, cardId: card.id, toColumn: "준비")
        _ = manager.moveCard(boardId: board.id, cardId: card.id, toColumn: "진행 중")

        let transitions = manager.cardHistory(boardId: board.id, cardId: card.id)!
        XCTAssertEqual(transitions.count, 2)
        XCTAssertEqual(transitions[0].fromColumn, "백로그")
        XCTAssertEqual(transitions[0].toColumn, "준비")
        XCTAssertEqual(transitions[1].fromColumn, "준비")
        XCTAssertEqual(transitions[1].toColumn, "진행 중")
    }

    func testMoveCardToInvalidColumn() {
        let board = manager.createBoard(name: "보드")
        let card = manager.addCard(boardId: board.id, title: "카드")!
        let result = manager.moveCard(boardId: board.id, cardId: card.id, toColumn: "없는컬럼")
        XCTAssertFalse(result)
    }

    func testMoveCardNonExistentCard() {
        let board = manager.createBoard(name: "보드")
        let result = manager.moveCard(boardId: board.id, cardId: UUID(), toColumn: "완료")
        XCTAssertFalse(result)
    }

    func testUpdateCard() {
        let board = manager.createBoard(name: "보드")
        let card = manager.addCard(boardId: board.id, title: "수정 전")!
        let result = manager.updateCard(
            boardId: board.id,
            cardId: card.id,
            title: "수정 후",
            priority: .high,
            labels: ["개선"]
        )
        XCTAssertTrue(result)

        let updated = manager.board(id: board.id)!.cards.first!
        XCTAssertEqual(updated.title, "수정 후")
        XCTAssertEqual(updated.priority, .high)
        XCTAssertEqual(updated.labels, ["개선"])
    }

    func testUpdateCardPartial() {
        let board = manager.createBoard(name: "보드")
        let card = manager.addCard(boardId: board.id, title: "원본", description: "설명")!
        _ = manager.updateCard(boardId: board.id, cardId: card.id, title: "새 제목")

        let updated = manager.board(id: board.id)!.cards.first!
        XCTAssertEqual(updated.title, "새 제목")
        XCTAssertEqual(updated.description, "설명") // unchanged
    }

    func testDeleteCard() {
        let board = manager.createBoard(name: "보드")
        let card = manager.addCard(boardId: board.id, title: "삭제 카드")!
        XCTAssertEqual(manager.board(id: board.id)!.cards.count, 1)

        let result = manager.deleteCard(boardId: board.id, cardId: card.id)
        XCTAssertTrue(result)
        XCTAssertEqual(manager.board(id: board.id)!.cards.count, 0)
    }

    func testDeleteCardNonExistent() {
        let board = manager.createBoard(name: "보드")
        let result = manager.deleteCard(boardId: board.id, cardId: UUID())
        XCTAssertFalse(result)
    }

    // MARK: - Card History

    func testCardHistoryEmpty() {
        let board = manager.createBoard(name: "보드")
        let card = manager.addCard(boardId: board.id, title: "카드")!
        let history = manager.cardHistory(boardId: board.id, cardId: card.id)
        XCTAssertNotNil(history)
        XCTAssertTrue(history!.isEmpty)
    }

    func testCardHistoryNonExistentBoard() {
        let history = manager.cardHistory(boardId: UUID(), cardId: UUID())
        XCTAssertNil(history)
    }

    func testCardHistoryNonExistentCard() {
        let board = manager.createBoard(name: "보드")
        let history = manager.cardHistory(boardId: board.id, cardId: UUID())
        XCTAssertNil(history)
    }

    // MARK: - Persistence

    func testPersistenceRoundtrip() {
        let board = manager.createBoard(name: "영속성 테스트")
        let card = manager.addCard(boardId: board.id, title: "카드 1", column: "준비", priority: .high)!
        _ = manager.moveCard(boardId: board.id, cardId: card.id, toColumn: "진행 중")

        // Create a new manager from the same directory
        let manager2 = KanbanManager(storageDir: tempDir)
        let loaded = manager2.board(id: board.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded!.name, "영속성 테스트")
        XCTAssertEqual(loaded!.cards.count, 1)
        XCTAssertEqual(loaded!.cards[0].column, "진행 중")
        XCTAssertEqual(loaded!.cards[0].transitions.count, 1)
    }

    func testDeleteBoardRemovesFile() {
        let board = manager.createBoard(name: "삭제 테스트")
        let file = tempDir.appendingPathComponent("\(board.id.uuidString).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        manager.deleteBoard(id: board.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: - Backward Compatibility

    func testDecodeCardWithoutTransitions() throws {
        // Simulate old format without transitions field
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "title": "구 카드",
            "description": "",
            "column": "할 일",
            "priority": "medium",
            "labels": [],
            "createdAt": "2024-01-01T00:00:00Z",
            "updatedAt": "2024-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let card = try decoder.decode(KanbanCard.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(card.title, "구 카드")
        XCTAssertTrue(card.transitions.isEmpty)
    }

    func testDecodeCardWithTransitions() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000002",
            "title": "신 카드",
            "description": "",
            "column": "진행 중",
            "priority": "high",
            "labels": [],
            "createdAt": "2024-01-01T00:00:00Z",
            "updatedAt": "2024-01-01T00:00:00Z",
            "transitions": [
                { "fromColumn": "백로그", "toColumn": "진행 중", "timestamp": "2024-01-02T00:00:00Z" }
            ]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let card = try decoder.decode(KanbanCard.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(card.transitions.count, 1)
        XCTAssertEqual(card.transitions[0].fromColumn, "백로그")
    }

    // MARK: - Board Codable Roundtrip

    func testBoardCodableRoundtrip() throws {
        var board = KanbanBoard(name: "테스트 보드", columns: ["A", "B", "C"])
        let card = KanbanCard(title: "카드", column: "A", priority: .urgent, labels: ["bug"], assignee: "dev")
        board.cards.append(card)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(board)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(KanbanBoard.self, from: data)

        XCTAssertEqual(decoded.name, "테스트 보드")
        XCTAssertEqual(decoded.columns, ["A", "B", "C"])
        XCTAssertEqual(decoded.cards.count, 1)
        XCTAssertEqual(decoded.cards[0].title, "카드")
        XCTAssertEqual(decoded.cards[0].priority, .urgent)
        XCTAssertEqual(decoded.cards[0].assignee, "dev")
    }

    // MARK: - Tool Execution

    func testKanbanCardHistoryToolNoTransitions() async {
        let tool = KanbanCardHistoryTool()
        // Uses KanbanManager.shared — create a board through shared for tool test
        let board = KanbanManager.shared.createBoard(name: "HistoryToolTest_\(UUID().uuidString)")
        let card = KanbanManager.shared.addCard(boardId: board.id, title: "히스토리 테스트 카드")!

        let result = await tool.execute(arguments: [
            "board_name": board.name,
            "card_title": "히스토리 테스트",
        ])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("상태 변경 기록 없음"))

        // Clean up
        KanbanManager.shared.deleteBoard(id: board.id)
    }

    func testKanbanCardHistoryToolMissingBoard() async {
        let tool = KanbanCardHistoryTool()
        let result = await tool.execute(arguments: [
            "board_name": "없는보드_\(UUID().uuidString)",
            "card_title": "test",
        ])
        XCTAssertTrue(result.isError)
    }

    func testKanbanCardHistoryToolMissingParams() async {
        let tool = KanbanCardHistoryTool()
        let result = await tool.execute(arguments: [:])
        XCTAssertTrue(result.isError)
    }
}
