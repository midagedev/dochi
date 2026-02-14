import Foundation

// MARK: - Kanban Data Model

struct StatusTransition: Codable, Sendable {
    let fromColumn: String
    let toColumn: String
    let timestamp: Date

    init(fromColumn: String, toColumn: String, timestamp: Date = Date()) {
        self.fromColumn = fromColumn
        self.toColumn = toColumn
        self.timestamp = timestamp
    }
}

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
    var transitions: [StatusTransition]

    enum Priority: String, Codable, Sendable, CaseIterable {
        case low
        case medium
        case high
        case urgent
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, column, priority, labels, assignee, createdAt, updatedAt, transitions
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
        updatedAt: Date = Date(),
        transitions: [StatusTransition] = []
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
        self.transitions = transitions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        column = try container.decode(String.self, forKey: .column)
        priority = try container.decode(Priority.self, forKey: .priority)
        labels = try container.decode([String].self, forKey: .labels)
        assignee = try container.decodeIfPresent(String.self, forKey: .assignee)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        transitions = try container.decodeIfPresent([StatusTransition].self, forKey: .transitions) ?? []
    }
}

struct KanbanBoard: Codable, Identifiable, Sendable {
    static let defaultColumns = ["백로그", "준비", "진행 중", "검토", "완료"]

    let id: UUID
    var name: String
    var columns: [String]
    var cards: [KanbanCard]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        columns: [String] = KanbanBoard.defaultColumns,
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

    private(set) var boards: [UUID: KanbanBoard] = [:]
    private let storageDir: URL

    private init() {
        storageDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dochi/kanban", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        loadAll()
    }

    /// Testable initializer with custom storage directory.
    init(storageDir: URL) {
        self.storageDir = storageDir
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        loadAll()
    }

    // MARK: - Board Operations

    func createBoard(name: String, columns: [String]? = nil) -> KanbanBoard {
        let board = KanbanBoard(name: name, columns: columns ?? KanbanBoard.defaultColumns)
        boards[board.id] = board
        save(board)
        Log.storage.info("Created kanban board: \(name) with \(board.columns.count) columns")
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
        let name = boards[id]?.name ?? "unknown"
        boards.removeValue(forKey: id)
        let file = storageDir.appendingPathComponent("\(id.uuidString).json")
        do {
            try FileManager.default.removeItem(at: file)
            Log.storage.info("Deleted kanban board: \(name)")
        } catch {
            Log.storage.error("Failed to delete kanban board file: \(error.localizedDescription)")
        }
    }

    // MARK: - Card Operations

    func addCard(boardId: UUID, title: String, column: String? = nil, priority: KanbanCard.Priority = .medium, description: String = "", labels: [String] = [], assignee: String? = nil) -> KanbanCard? {
        guard var board = boards[boardId] else { return nil }
        let targetColumn = column ?? board.columns.first ?? "백로그"

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

        let fromColumn = board.cards[idx].column
        let transition = StatusTransition(fromColumn: fromColumn, toColumn: toColumn)
        board.cards[idx].transitions.append(transition)
        board.cards[idx].column = toColumn
        board.cards[idx].updatedAt = Date()
        board.updatedAt = Date()
        boards[boardId] = board
        save(board)
        Log.storage.debug("Moved card '\(board.cards[idx].title)': \(fromColumn) → \(toColumn)")
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

        let title = board.cards[idx].title
        board.cards.remove(at: idx)
        board.updatedAt = Date()
        boards[boardId] = board
        save(board)
        Log.storage.debug("Deleted card: \(title)")
        return true
    }

    /// Returns the transition history of a card.
    func cardHistory(boardId: UUID, cardId: UUID) -> [StatusTransition]? {
        guard let board = boards[boardId],
              let card = board.cards.first(where: { $0.id == cardId }) else { return nil }
        return card.transitions
    }

    // MARK: - Persistence

    private func save(_ board: KanbanBoard) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(board)
            let file = storageDir.appendingPathComponent("\(board.id.uuidString).json")
            try data.write(to: file)
        } catch {
            Log.storage.error("Failed to save kanban board: \(error.localizedDescription)")
        }
    }

    private func loadAll() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let files = try? FileManager.default.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: file)
                let board = try decoder.decode(KanbanBoard.self, from: data)
                boards[board.id] = board
            } catch {
                Log.storage.warning("Failed to load kanban board from \(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}
