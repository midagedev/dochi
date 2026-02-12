import Foundation

// MARK: - Kanban Data Model

struct KanbanCard: Codable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var description: String
    var column: String
    var priority: Priority
    var labels: [String]
    var assignee: String?
    let createdAt: Date
    var updatedAt: Date

    enum Priority: String, Codable, Sendable, CaseIterable {
        case low
        case medium
        case high
        case urgent
    }

    init(
        id: UUID = UUID(),
        title: String,
        description: String = "",
        column: String,
        priority: Priority = .medium,
        labels: [String] = [],
        assignee: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.column = column
        self.priority = priority
        self.labels = labels
        self.assignee = assignee
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct KanbanBoard: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var columns: [String]
    var cards: [KanbanCard]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        columns: [String] = ["할 일", "진행 중", "완료"],
        cards: [KanbanCard] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.columns = columns
        self.cards = cards
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Kanban Manager

@MainActor
final class KanbanManager {
    static let shared = KanbanManager()

    private var boards: [UUID: KanbanBoard] = [:]
    private let storageDir: URL

    private init() {
        storageDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dochi/kanban", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        loadAll()
    }

    // MARK: - Board Operations

    func createBoard(name: String, columns: [String]? = nil) -> KanbanBoard {
        let board = KanbanBoard(name: name, columns: columns ?? ["할 일", "진행 중", "완료"])
        boards[board.id] = board
        save(board)
        return board
    }

    func listBoards() -> [KanbanBoard] {
        Array(boards.values).sorted { $0.createdAt < $1.createdAt }
    }

    func board(id: UUID) -> KanbanBoard? {
        boards[id]
    }

    func board(name: String) -> KanbanBoard? {
        boards.values.first { $0.name.localizedCaseInsensitiveContains(name) }
    }

    func deleteBoard(id: UUID) {
        boards.removeValue(forKey: id)
        let file = storageDir.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: file)
    }

    // MARK: - Card Operations

    func addCard(boardId: UUID, title: String, column: String? = nil, priority: KanbanCard.Priority = .medium, description: String = "", labels: [String] = [], assignee: String? = nil) -> KanbanCard? {
        guard var board = boards[boardId] else { return nil }
        let targetColumn = column ?? board.columns.first ?? "할 일"

        guard board.columns.contains(targetColumn) else { return nil }

        let card = KanbanCard(
            title: title,
            description: description,
            column: targetColumn,
            priority: priority,
            labels: labels,
            assignee: assignee
        )
        board.cards.append(card)
        board.updatedAt = Date()
        boards[boardId] = board
        save(board)
        return card
    }

    func moveCard(boardId: UUID, cardId: UUID, toColumn: String) -> Bool {
        guard var board = boards[boardId] else { return false }
        guard board.columns.contains(toColumn) else { return false }
        guard let idx = board.cards.firstIndex(where: { $0.id == cardId }) else { return false }

        board.cards[idx].column = toColumn
        board.cards[idx].updatedAt = Date()
        board.updatedAt = Date()
        boards[boardId] = board
        save(board)
        return true
    }

    func updateCard(boardId: UUID, cardId: UUID, title: String? = nil, description: String? = nil, priority: KanbanCard.Priority? = nil, labels: [String]? = nil, assignee: String? = nil) -> Bool {
        guard var board = boards[boardId] else { return false }
        guard let idx = board.cards.firstIndex(where: { $0.id == cardId }) else { return false }

        if let title { board.cards[idx].title = title }
        if let description { board.cards[idx].description = description }
        if let priority { board.cards[idx].priority = priority }
        if let labels { board.cards[idx].labels = labels }
        if let assignee { board.cards[idx].assignee = assignee }
        board.cards[idx].updatedAt = Date()
        board.updatedAt = Date()
        boards[boardId] = board
        save(board)
        return true
    }

    func deleteCard(boardId: UUID, cardId: UUID) -> Bool {
        guard var board = boards[boardId] else { return false }
        guard let idx = board.cards.firstIndex(where: { $0.id == cardId }) else { return false }

        board.cards.remove(at: idx)
        board.updatedAt = Date()
        boards[boardId] = board
        save(board)
        return true
    }

    // MARK: - Persistence

    private func save(_ board: KanbanBoard) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(board) else { return }
        let file = storageDir.appendingPathComponent("\(board.id.uuidString).json")
        try? data.write(to: file)
    }

    private func loadAll() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let files = try? FileManager.default.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let board = try? decoder.decode(KanbanBoard.self, from: data) else { continue }
            boards[board.id] = board
        }
    }
}
