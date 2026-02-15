import Foundation

// MARK: - SyncState

/// 동기화 상태 머신
enum SyncState: Sendable, Equatable {
    case idle
    case syncing
    case conflict(count: Int)
    case error(message: String)
    case offline
    case disabled

    var displayText: String {
        switch self {
        case .idle: "동기화 완료"
        case .syncing: "동기화 중..."
        case .conflict(let count): "충돌 \(count)건"
        case .error(let message): "오류: \(message)"
        case .offline: "오프라인"
        case .disabled: "비활성"
        }
    }

    var iconName: String {
        switch self {
        case .idle: "checkmark.icloud"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .conflict: "exclamationmark.icloud"
        case .error: "xmark.icloud"
        case .offline: "icloud.slash"
        case .disabled: "icloud.slash"
        }
    }

    var indicatorColor: String {
        switch self {
        case .idle: "green"
        case .syncing: "blue"
        case .conflict: "orange"
        case .error: "red"
        case .offline: "gray"
        case .disabled: "gray"
        }
    }
}

// MARK: - SyncDirection

enum SyncDirection: String, Sendable, Codable {
    case incoming
    case outgoing
}

// MARK: - SyncEntityType

enum SyncEntityType: String, Sendable, Codable, CaseIterable {
    case conversation
    case memory
    case kanban
    case profile

    var displayName: String {
        switch self {
        case .conversation: "대화"
        case .memory: "메모리"
        case .kanban: "칸반"
        case .profile: "프로필"
        }
    }

    var iconName: String {
        switch self {
        case .conversation: "bubble.left.and.bubble.right"
        case .memory: "brain"
        case .kanban: "rectangle.3.group"
        case .profile: "person.crop.circle"
        }
    }
}

// MARK: - SyncProgress

struct SyncProgress: Sendable, Equatable {
    var totalItems: Int
    var completedItems: Int
    var currentEntity: String
    var startedAt: Date

    var fraction: Double {
        guard totalItems > 0 else { return 0 }
        return Double(completedItems) / Double(totalItems)
    }

    var isComplete: Bool {
        totalItems > 0 && completedItems >= totalItems
    }

    static let empty = SyncProgress(totalItems: 0, completedItems: 0, currentEntity: "", startedAt: Date())
}

// MARK: - SyncConflict

struct SyncConflict: Identifiable, Sendable, Equatable {
    let id: UUID
    let entityType: SyncEntityType
    let entityId: String
    let entityTitle: String
    let localUpdatedAt: Date
    let remoteUpdatedAt: Date
    let localPreview: String
    let remotePreview: String

    init(
        id: UUID = UUID(),
        entityType: SyncEntityType,
        entityId: String,
        entityTitle: String,
        localUpdatedAt: Date,
        remoteUpdatedAt: Date,
        localPreview: String,
        remotePreview: String
    ) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.entityTitle = entityTitle
        self.localUpdatedAt = localUpdatedAt
        self.remoteUpdatedAt = remoteUpdatedAt
        self.localPreview = localPreview
        self.remotePreview = remotePreview
    }
}

// MARK: - ConflictResolution

enum ConflictResolution: String, Sendable {
    case keepLocal
    case keepRemote
    case merge
}

// MARK: - SyncToastEvent

struct SyncToastEvent: Identifiable, Sendable {
    let id: UUID
    let direction: SyncDirection
    let entityType: SyncEntityType
    let entityTitle: String
    let isConflict: Bool
    let timestamp: Date

    init(
        id: UUID = UUID(),
        direction: SyncDirection,
        entityType: SyncEntityType,
        entityTitle: String,
        isConflict: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.direction = direction
        self.entityType = entityType
        self.entityTitle = entityTitle
        self.isConflict = isConflict
        self.timestamp = timestamp
    }

    var displayMessage: String {
        let directionText = direction == .incoming ? "수신" : "발신"
        let conflictText = isConflict ? " (충돌)" : ""
        return "\(entityType.displayName) \(directionText)\(conflictText)"
    }
}

// MARK: - SyncHistoryEntry

struct SyncHistoryEntry: Identifiable, Sendable {
    let id: UUID
    let direction: SyncDirection
    let entityType: SyncEntityType
    let entityTitle: String
    let timestamp: Date
    let success: Bool
    let errorMessage: String?

    init(
        id: UUID = UUID(),
        direction: SyncDirection,
        entityType: SyncEntityType,
        entityTitle: String,
        timestamp: Date = Date(),
        success: Bool = true,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.direction = direction
        self.entityType = entityType
        self.entityTitle = entityTitle
        self.timestamp = timestamp
        self.success = success
        self.errorMessage = errorMessage
    }
}

// MARK: - SyncMetadata

/// 로컬 파일에 저장되는 동기화 메타데이터
struct SyncMetadata: Codable, Sendable {
    var lastSyncTimestamp: Date?
    var entityTimestamps: [String: Date]

    init(lastSyncTimestamp: Date? = nil, entityTimestamps: [String: Date] = [:]) {
        self.lastSyncTimestamp = lastSyncTimestamp
        self.entityTimestamps = entityTimestamps
    }
}

// MARK: - SyncQueueItem

/// 오프라인 큐에 적재되는 동기화 항목
struct SyncQueueItem: Codable, Identifiable, Sendable {
    let id: UUID
    let entityType: SyncEntityType
    let entityId: String
    let action: SyncAction
    let payload: Data?
    let enqueuedAt: Date

    init(
        id: UUID = UUID(),
        entityType: SyncEntityType,
        entityId: String,
        action: SyncAction,
        payload: Data? = nil,
        enqueuedAt: Date = Date()
    ) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.action = action
        self.payload = payload
        self.enqueuedAt = enqueuedAt
    }
}

// MARK: - SyncAction

enum SyncAction: String, Codable, Sendable {
    case create
    case update
    case delete
}
