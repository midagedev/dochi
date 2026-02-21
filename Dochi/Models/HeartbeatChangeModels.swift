import Foundation

enum HeartbeatChangeSource: String, Codable, Sendable {
    case git
    case codingSession
}

enum HeartbeatChangeSeverity: String, Codable, Sendable {
    case info
    case warning
    case critical
}

enum HeartbeatChangeEventType: String, Codable, Sendable {
    case gitRepositoryAdded = "git_repository_added"
    case gitRepositoryRemoved = "git_repository_removed"
    case gitBranchChanged = "git_branch_changed"
    case gitDirtyStateChanged = "git_dirty_state_changed"
    case gitDirtySpike = "git_dirty_spike"
    case gitAheadBehindChanged = "git_ahead_behind_changed"

    case codingSessionStarted = "coding_session_started"
    case codingSessionEnded = "coding_session_ended"
    case codingSessionActivityChanged = "coding_session_activity_changed"
    case codingSessionRepositoryChanged = "coding_session_repository_changed"
}

struct HeartbeatChangeEvent: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let source: HeartbeatChangeSource
    let eventType: HeartbeatChangeEventType
    let severity: HeartbeatChangeSeverity
    let targetId: String
    let title: String
    let detail: String
    let metadata: [String: String]
    let timestamp: Date

    init(
        id: UUID = UUID(),
        source: HeartbeatChangeSource,
        eventType: HeartbeatChangeEventType,
        severity: HeartbeatChangeSeverity,
        targetId: String,
        title: String,
        detail: String,
        metadata: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.eventType = eventType
        self.severity = severity
        self.targetId = targetId
        self.title = title
        self.detail = detail
        self.metadata = metadata
        self.timestamp = timestamp
    }

    var dedupeKey: String {
        "\(source.rawValue)|\(eventType.rawValue)|\(targetId)"
    }
}
