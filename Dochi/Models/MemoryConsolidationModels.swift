import Foundation

// MARK: - ConsolidationState

/// 메모리 정리 진행 상태
enum ConsolidationState: Equatable, Sendable {
    case idle
    case analyzing
    case completed(added: Int, updated: Int)
    case conflict(count: Int)
    case failed(message: String)

    var isActive: Bool {
        switch self {
        case .analyzing: return true
        default: return false
        }
    }
}

// MARK: - MemoryScope

/// 메모리 범위: 개인, 워크스페이스, 에이전트
enum MemoryScope: String, Codable, Sendable {
    case personal
    case workspace
    case agent
}

// MARK: - MemoryChange

/// 메모리 변경 항목
struct MemoryChange: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let scope: MemoryScope
    let type: ChangeType
    let content: String
    let previousContent: String?
    let timestamp: Date

    enum ChangeType: String, Codable, Sendable, Equatable {
        case added
        case updated
        case removed
        case archived
    }

    init(id: UUID = UUID(), scope: MemoryScope, type: ChangeType, content: String, previousContent: String? = nil, timestamp: Date = Date()) {
        self.id = id
        self.scope = scope
        self.type = type
        self.content = content
        self.previousContent = previousContent
        self.timestamp = timestamp
    }
}

// MARK: - MemoryConflict

/// 메모리 모순 항목
struct MemoryConflict: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let scope: MemoryScope
    let existingFact: String
    let newFact: String
    let explanation: String

    init(id: UUID = UUID(), scope: MemoryScope, existingFact: String, newFact: String, explanation: String) {
        self.id = id
        self.scope = scope
        self.existingFact = existingFact
        self.newFact = newFact
        self.explanation = explanation
    }
}

// MARK: - MemoryConflictResolution

/// 모순 해결 선택지
enum MemoryConflictResolution: String, Codable, Sendable {
    case keepExisting
    case useNew
    case keepBoth
}

// MARK: - ConsolidationResult

/// 정리 결과
struct ConsolidationResult: Codable, Identifiable, Sendable {
    let id: UUID
    let conversationId: UUID
    let timestamp: Date
    let changes: [MemoryChange]
    let conflicts: [MemoryConflict]
    let factsExtracted: Int
    let duplicatesSkipped: Int

    init(id: UUID = UUID(), conversationId: UUID, timestamp: Date = Date(), changes: [MemoryChange], conflicts: [MemoryConflict], factsExtracted: Int, duplicatesSkipped: Int) {
        self.id = id
        self.conversationId = conversationId
        self.timestamp = timestamp
        self.changes = changes
        self.conflicts = conflicts
        self.factsExtracted = factsExtracted
        self.duplicatesSkipped = duplicatesSkipped
    }

    var addedCount: Int { changes.filter { $0.type == .added }.count }
    var updatedCount: Int { changes.filter { $0.type == .updated }.count }
}

// MARK: - ExtractedFact

/// LLM에서 추출된 사실/결정
struct ExtractedFact: Codable, Sendable, Equatable {
    let content: String
    let scope: MemoryScope

    init(content: String, scope: MemoryScope = .personal) {
        self.content = content
        self.scope = scope
    }
}

// MARK: - ChangelogEntry

/// 변경 이력 항목 (memory_changelog.json에 저장)
struct ChangelogEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let conversationId: UUID
    let timestamp: Date
    let changes: [MemoryChange]
    let conflicts: [MemoryConflict]
    let factsExtracted: Int
    let duplicatesSkipped: Int

    init(from result: ConsolidationResult) {
        self.id = result.id
        self.conversationId = result.conversationId
        self.timestamp = result.timestamp
        self.changes = result.changes
        self.conflicts = result.conflicts
        self.factsExtracted = result.factsExtracted
        self.duplicatesSkipped = result.duplicatesSkipped
    }
}
