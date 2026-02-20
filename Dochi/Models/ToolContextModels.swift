import Foundation

enum ToolUsageDecision: String, Codable, Sendable {
    case allowed
    case approved
    case denied
    case policyBlocked
    case hookBlocked
    case timeout

    init(auditDecision: ToolAuditDecision) {
        switch auditDecision {
        case .allowed:
            self = .allowed
        case .approved:
            self = .approved
        case .denied:
            self = .denied
        case .policyBlocked:
            self = .policyBlocked
        case .hookBlocked:
            self = .hookBlocked
        case .timeout:
            self = .timeout
        }
    }

    /// Positive signals should increase score, blocked/denied signals should reduce score.
    var scoreDelta: Double {
        switch self {
        case .allowed, .approved:
            return 1.0
        case .denied:
            return -0.2
        case .policyBlocked, .hookBlocked:
            return -0.35
        case .timeout:
            return -0.1
        }
    }
}

struct ToolUsageEvent: Codable, Sendable, Equatable {
    static let defaultWorkspaceId = "__global__"
    static let defaultAgentName = "__default__"

    let toolName: String
    let category: String
    let decision: ToolUsageDecision
    let latencyMs: Int
    let agentName: String
    let workspaceId: String
    let timestamp: Date
}

struct ToolContextProfile: Codable, Sendable, Equatable {
    let agentName: String
    let workspaceId: String
    var categoryScores: [String: Double]
    var toolScores: [String: Double]
    var lastUpdatedAt: Date

    init(
        agentName: String,
        workspaceId: String,
        categoryScores: [String: Double] = [:],
        toolScores: [String: Double] = [:],
        lastUpdatedAt: Date = Date()
    ) {
        self.agentName = agentName
        self.workspaceId = workspaceId
        self.categoryScores = categoryScores
        self.toolScores = toolScores
        self.lastUpdatedAt = lastUpdatedAt
    }
}

struct UserToolPreference: Codable, Sendable, Equatable {
    var preferredCategories: [String]
    var suppressedCategories: [String]
    var updatedAt: Date

    init(
        preferredCategories: [String] = [],
        suppressedCategories: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.preferredCategories = preferredCategories
        self.suppressedCategories = suppressedCategories
        self.updatedAt = updatedAt
    }
}

struct ToolContextFile: Codable, Sendable {
    var profiles: [String: ToolContextProfile]
    var userPreferences: [String: UserToolPreference]
    var recentEvents: [ToolUsageEvent]

    static let empty = ToolContextFile(
        profiles: [:],
        userPreferences: [:],
        recentEvents: []
    )
}
