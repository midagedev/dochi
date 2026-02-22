import Foundation

enum WorkItemSource: String, Codable, Sendable {
    case heartbeat
    case resource
    case orchestrator
    case user
}

enum WorkItemSeverity: String, Codable, Sendable, CaseIterable {
    case info
    case warning
    case critical

    var priority: Int {
        switch self {
        case .critical:
            return 3
        case .warning:
            return 2
        case .info:
            return 1
        }
    }
}

enum WorkItemStatus: String, Codable, Sendable {
    case queued
    case notified
    case accepted
    case deferred
    case dismissed
    case expired

    func canTransition(to next: WorkItemStatus) -> Bool {
        if self == next {
            return true
        }

        switch self {
        case .queued:
            return next == .notified || next == .accepted || next == .deferred || next == .dismissed || next == .expired
        case .notified:
            return next == .accepted || next == .deferred || next == .dismissed || next == .expired
        case .accepted:
            return next == .dismissed || next == .expired
        case .deferred:
            return next == .queued || next == .notified || next == .accepted || next == .dismissed || next == .expired
        case .dismissed, .expired:
            return false
        }
    }
}

struct WorkItemDraft: Equatable, Sendable {
    let source: WorkItemSource
    let title: String
    let detail: String
    let repositoryRoot: String?
    let severity: WorkItemSeverity
    let suggestedAction: String
    let dedupeKey: String
    let dueAt: Date?
    let ttl: TimeInterval?

    init(
        source: WorkItemSource,
        title: String,
        detail: String,
        repositoryRoot: String? = nil,
        severity: WorkItemSeverity = .info,
        suggestedAction: String,
        dedupeKey: String,
        dueAt: Date? = nil,
        ttl: TimeInterval? = nil
    ) {
        self.source = source
        self.title = title
        self.detail = detail
        self.repositoryRoot = repositoryRoot
        self.severity = severity
        self.suggestedAction = suggestedAction
        self.dedupeKey = dedupeKey
        self.dueAt = dueAt
        self.ttl = ttl
    }
}

struct WorkItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let source: WorkItemSource
    let title: String
    let detail: String
    let repositoryRoot: String?
    let severity: WorkItemSeverity
    let suggestedAction: String
    let dedupeKey: String
    var status: WorkItemStatus
    let createdAt: Date
    let dueAt: Date?
    let expiresAt: Date?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        source: WorkItemSource,
        title: String,
        detail: String,
        repositoryRoot: String?,
        severity: WorkItemSeverity,
        suggestedAction: String,
        dedupeKey: String,
        status: WorkItemStatus = .queued,
        createdAt: Date = Date(),
        dueAt: Date? = nil,
        expiresAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.detail = detail
        self.repositoryRoot = repositoryRoot
        self.severity = severity
        self.suggestedAction = suggestedAction
        self.dedupeKey = dedupeKey
        self.status = status
        self.createdAt = createdAt
        self.dueAt = dueAt
        self.expiresAt = expiresAt
        self.updatedAt = updatedAt
    }
}
