import Foundation

// MARK: - K-4: External AI Tool Session Manager Models

enum ExternalToolStatus: String, Codable, Sendable {
    case idle
    case busy
    case waiting
    case error
    case dead
    case unknown
}

enum DiscoveredCodingSessionSource: String, Codable, Sendable {
    case codexSessionFile = "codex_session_file"
    case claudeProjectFile = "claude_project_file"
    case claudeTaskDirectory = "claude_task_directory"
}

struct DiscoveredCodingSession: Sendable, Equatable {
    let source: DiscoveredCodingSessionSource
    let provider: String
    let sessionId: String
    let workingDirectory: String?
    let gitBranch: String?
    let path: String
    let updatedAt: Date
    let isActive: Bool
    let sessionHintKeys: [String]
    let title: String?
    let summary: String?
    let titleSource: String?
    let titleConfidence: Double?
    let originator: String?
    let sessionSource: String?
    let clientKind: String?

    init(
        source: DiscoveredCodingSessionSource,
        provider: String,
        sessionId: String,
        workingDirectory: String?,
        gitBranch: String? = nil,
        path: String,
        updatedAt: Date,
        isActive: Bool,
        sessionHintKeys: [String] = [],
        title: String? = nil,
        summary: String? = nil,
        titleSource: String? = nil,
        titleConfidence: Double? = nil,
        originator: String? = nil,
        sessionSource: String? = nil,
        clientKind: String? = nil
    ) {
        self.source = source
        self.provider = provider
        self.sessionId = sessionId
        self.workingDirectory = workingDirectory
        self.gitBranch = gitBranch
        self.path = path
        self.updatedAt = updatedAt
        self.isActive = isActive
        self.sessionHintKeys = sessionHintKeys
        self.title = title
        self.summary = summary
        self.titleSource = titleSource
        self.titleConfidence = titleConfidence
        self.originator = originator
        self.sessionSource = sessionSource
        self.clientKind = clientKind
    }
}

enum ManagedGitRepositorySource: String, Codable, Sendable {
    case initialized = "initialized"
    case cloned = "cloned"
    case attached = "attached"
}

struct ManagedGitRepository: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var rootPath: String
    var source: ManagedGitRepositorySource
    var originURL: String?
    var defaultBranch: String?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        rootPath: String,
        source: ManagedGitRepositorySource,
        originURL: String?,
        defaultBranch: String?,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.source = source
        self.originURL = originURL
        self.defaultBranch = defaultBranch
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum CodingSessionRuntimeType: String, Codable, Sendable {
    case tmux
    case process
    case file
}

enum CodingSessionControllabilityTier: String, Codable, Sendable {
    case t0Full = "t0_full"
    case t1Attach = "t1_attach"
    case t2Observe = "t2_observe"
    case t3Unknown = "t3_unknown"
}

enum CodingSessionActivityState: String, Codable, Sendable {
    case active
    case idle
    case stale
    case dead
}

struct CodingSessionActivitySignals: Codable, Sendable, Equatable {
    let runtimeAliveScore: Int
    let recentOutputScore: Int
    let recentCommandScore: Int
    let fileFreshnessScore: Int
    let errorPenaltyScore: Int
}

struct CodingSessionActivityScoringConfig: Sendable, Equatable {
    let runtimeAliveWeight: Int
    let recentOutputWeight: Int
    let recentCommandWeight: Int
    let fileFreshnessWeight: Int
    let errorPenaltyWeight: Int

    let outputHotWindow: TimeInterval
    let commandHotWindow: TimeInterval
    let fileHotWindow: TimeInterval
    let staleWindow: TimeInterval
    let deadWindow: TimeInterval

    let activeThreshold: Int
    let idleThreshold: Int
    let staleThreshold: Int

    static let standard = CodingSessionActivityScoringConfig(
        runtimeAliveWeight: 32,
        recentOutputWeight: 23,
        recentCommandWeight: 20,
        fileFreshnessWeight: 15,
        errorPenaltyWeight: 24,
        outputHotWindow: 2 * 60,
        commandHotWindow: 3 * 60,
        fileHotWindow: 10 * 60,
        staleWindow: 2 * 60 * 60,
        deadWindow: 24 * 60 * 60,
        activeThreshold: 70,
        idleThreshold: 42,
        staleThreshold: 20
    )
}

struct UnifiedCodingSession: Sendable, Equatable {
    let source: String
    let runtimeType: CodingSessionRuntimeType
    let controllabilityTier: CodingSessionControllabilityTier
    let provider: String
    let nativeSessionId: String
    let runtimeSessionId: String?
    let workingDirectory: String?
    let repositoryRoot: String?
    let path: String
    let updatedAt: Date
    let isActive: Bool
    let title: String?
    let summary: String?
    let titleSource: String?
    let titleConfidence: Double?
    let originator: String?
    let sessionSource: String?
    let clientKind: String?
    let activityScore: Int
    let activityState: CodingSessionActivityState
    let activitySignals: CodingSessionActivitySignals

    var isUnassigned: Bool { repositoryRoot == nil }

    init(
        source: String,
        runtimeType: CodingSessionRuntimeType,
        controllabilityTier: CodingSessionControllabilityTier,
        provider: String,
        nativeSessionId: String,
        runtimeSessionId: String?,
        workingDirectory: String?,
        repositoryRoot: String?,
        path: String,
        updatedAt: Date,
        isActive: Bool,
        title: String? = nil,
        summary: String? = nil,
        titleSource: String? = nil,
        titleConfidence: Double? = nil,
        originator: String? = nil,
        sessionSource: String? = nil,
        clientKind: String? = nil,
        activityScore: Int = 0,
        activityState: CodingSessionActivityState = .stale,
        activitySignals: CodingSessionActivitySignals = CodingSessionActivitySignals(
            runtimeAliveScore: 0,
            recentOutputScore: 0,
            recentCommandScore: 0,
            fileFreshnessScore: 0,
            errorPenaltyScore: 0
        )
    ) {
        self.source = source
        self.runtimeType = runtimeType
        self.controllabilityTier = controllabilityTier
        self.provider = provider
        self.nativeSessionId = nativeSessionId
        self.runtimeSessionId = runtimeSessionId
        self.workingDirectory = workingDirectory
        self.repositoryRoot = repositoryRoot
        self.path = path
        self.updatedAt = updatedAt
        self.isActive = isActive
        self.title = title
        self.summary = summary
        self.titleSource = titleSource
        self.titleConfidence = titleConfidence
        self.originator = originator
        self.sessionSource = sessionSource
        self.clientKind = clientKind
        self.activityScore = activityScore
        self.activityState = activityState
        self.activitySignals = activitySignals
    }
}

struct SessionHistoryEvent: Codable, Sendable, Equatable {
    let id: String
    let provider: String
    let sessionId: String
    let repositoryRoot: String?
    let workingDirectory: String?
    let branch: String?
    let eventType: String
    let content: String
    let timestamp: Date
    let sourcePath: String
}

struct SessionHistoryChunk: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let provider: String
    let sessionId: String
    let repositoryRoot: String?
    let workingDirectory: String?
    let branch: String?
    let sourcePath: String
    let startAt: Date
    let endAt: Date
    let tags: [String]
    let content: String
    let embedding: [Float]
}

struct SessionHistorySearchQuery: Sendable, Equatable {
    let query: String
    let repositoryRoot: String?
    let branch: String?
    let since: Date?
    let until: Date?
    let limit: Int

    init(
        query: String,
        repositoryRoot: String? = nil,
        branch: String? = nil,
        since: Date? = nil,
        until: Date? = nil,
        limit: Int = 20
    ) {
        self.query = query
        self.repositoryRoot = repositoryRoot
        self.branch = branch
        self.since = since
        self.until = until
        self.limit = limit
    }
}

struct SessionHistorySearchResult: Identifiable, Sendable, Equatable {
    let id: UUID
    let provider: String
    let sessionId: String
    let repositoryRoot: String?
    let branch: String?
    let sourcePath: String
    let score: Double
    let maskedSnippet: String
    let startAt: Date
    let endAt: Date
    let tags: [String]
}

struct SessionHistoryIndexStatus: Sendable, Equatable {
    let chunkCount: Int
    let lastIndexedAt: Date?
    let latestChunkEndAt: Date?
}

enum OrchestrationSessionSelectionAction: String, Codable, Sendable {
    case reuseT0Active = "reuse_t0_active"
    case attachT1 = "attach_t1"
    case createT0 = "create_t0"
    case analyzeOnly = "analyze_only"
    case none = "none"
}

struct OrchestrationSessionSelection: Sendable, Equatable {
    let action: OrchestrationSessionSelectionAction
    let reason: String
    let repositoryRoot: String?
    let selectedSession: UnifiedCodingSession?
}

enum OrchestrationExecutionDecisionKind: String, Codable, Sendable {
    case allowed
    case confirmationRequired = "confirmation_required"
    case denied
}

enum OrchestrationCommandClass: String, Codable, Sendable {
    case nonDestructive = "non_destructive"
    case destructive
}

enum OrchestrationGuardPolicyCode: String, Codable, Sendable {
    case t0AllowAll = "policy_t0_allow_all"
    case t1AllowNonDestructive = "policy_t1_allow_non_destructive"
    case t1ConfirmDestructive = "policy_t1_confirm_destructive"
    case t2DenyExecution = "policy_t2_deny_execution"
    case t3DenyExecution = "policy_t3_deny_execution"
}

struct OrchestrationGuardPolicyRule: Sendable, Equatable {
    let tier: CodingSessionControllabilityTier
    let commandClass: OrchestrationCommandClass
    let decisionKind: OrchestrationExecutionDecisionKind
    let policyCode: OrchestrationGuardPolicyCode
    let reason: String
}

struct OrchestrationExecutionDecision: Sendable, Equatable {
    let kind: OrchestrationExecutionDecisionKind
    let policyCode: OrchestrationGuardPolicyCode
    let commandClass: OrchestrationCommandClass
    let reason: String
    let isDestructiveCommand: Bool
}

struct SessionHistoryMaskingRule: Sendable, Equatable {
    let code: String
    let pattern: String
    let replacement: String
    let optionsRawValue: UInt

    init(
        code: String,
        pattern: String,
        replacement: String,
        options: NSRegularExpression.Options = []
    ) {
        self.code = code
        self.pattern = pattern
        self.replacement = replacement
        optionsRawValue = options.rawValue
    }

    var options: NSRegularExpression.Options {
        NSRegularExpression.Options(rawValue: optionsRawValue)
    }
}

struct SessionManagementKPICounters: Sendable, Equatable {
    var repositoryAssignedCount: Int = 0
    var repositoryTotalCount: Int = 0
    var dedupCandidateCount: Int = 0
    var dedupCorrectionCount: Int = 0
    var selectionAttemptCount: Int = 0
    var selectionFailureCount: Int = 0
    var historySearchQueryCount: Int = 0
    var historySearchHitCount: Int = 0
    var activityFeedbackSampleCount: Int = 0
    var activityFeedbackMatchedCount: Int = 0
    var activityStateDistribution: [String: Int] = [:]
    var clientKindSampleCount: Int = 0
    var clientKindUnknownCount: Int = 0
    var clientKindDistribution: [String: Int] = [:]
}

struct SessionManagementKPIReport: Sendable, Equatable {
    let generatedAt: Date
    let repositoryAssignmentSuccessRate: Double
    let dedupCorrectionRate: Double
    let activityClassificationAccuracy: Double?
    let sessionSelectionFailureRate: Double
    let historySearchHitRate: Double
    let clientKindUnknownRate: Double?
    let counters: SessionManagementKPICounters

    init(
        generatedAt: Date,
        repositoryAssignmentSuccessRate: Double,
        dedupCorrectionRate: Double,
        activityClassificationAccuracy: Double?,
        sessionSelectionFailureRate: Double,
        historySearchHitRate: Double,
        clientKindUnknownRate: Double? = nil,
        counters: SessionManagementKPICounters
    ) {
        self.generatedAt = generatedAt
        self.repositoryAssignmentSuccessRate = repositoryAssignmentSuccessRate
        self.dedupCorrectionRate = dedupCorrectionRate
        self.activityClassificationAccuracy = activityClassificationAccuracy
        self.sessionSelectionFailureRate = sessionSelectionFailureRate
        self.historySearchHitRate = historySearchHitRate
        self.clientKindUnknownRate = clientKindUnknownRate
        self.counters = counters
    }
}

enum OrchestrationRunState: String, Codable, Sendable {
    case planned
    case resolvingSession = "resolving_session"
    case executing
    case verifying
    case completed
    case failed
}

enum ExternalTerminalApp: String, CaseIterable, Codable, Sendable {
    case auto
    case terminal
    case ghostty

    var displayName: String {
        switch self {
        case .auto:
            return "자동 (Ghostty 우선)"
        case .terminal:
            return "Terminal.app"
        case .ghostty:
            return "Ghostty"
        }
    }
}

struct HealthCheckPatterns: Codable, Sendable, Equatable {
    var idlePattern: String
    var busyPattern: String
    var waitingPattern: String
    var errorPattern: String

    static let claudeCode = HealthCheckPatterns(
        idlePattern: "^>\\s*$",
        busyPattern: "(Thinking|Writing|Reading|Editing)",
        waitingPattern: "\\[Y/n\\]|\\[y/N\\]",
        errorPattern: "(Error|error|FAILED)"
    )

    static let codexCLI = HealthCheckPatterns(
        idlePattern: "^\\$\\s*$",
        busyPattern: "(Running|Generating)",
        waitingPattern: "\\[Y/n\\]|\\[y/N\\]",
        errorPattern: "(Error|error|FAILED)"
    )

    static let aider = HealthCheckPatterns(
        idlePattern: "^>\\s*$",
        busyPattern: "(Thinking|Editing|Committing)",
        waitingPattern: "\\[Y/n\\]|\\[y/N\\]",
        errorPattern: "(Error|error|FAILED)"
    )
}

struct SSHConfig: Codable, Sendable, Equatable {
    var host: String
    var port: Int
    var user: String
    var keyPath: String?

    init(host: String, port: Int = 22, user: String, keyPath: String? = nil) {
        self.host = host
        self.port = port
        self.user = user
        self.keyPath = keyPath
    }
}

struct ExternalToolProfile: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var icon: String
    var command: String
    var arguments: [String]
    var workingDirectory: String
    var sshConfig: SSHConfig?
    var healthCheckPatterns: HealthCheckPatterns

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "terminal.fill",
        command: String,
        arguments: [String] = [],
        workingDirectory: String = "~",
        sshConfig: SSHConfig? = nil,
        healthCheckPatterns: HealthCheckPatterns = .claudeCode
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.sshConfig = sshConfig
        self.healthCheckPatterns = healthCheckPatterns
    }

    var isRemote: Bool { sshConfig != nil }
}

// MARK: - Presets

enum ExternalToolPreset: String, CaseIterable, Sendable {
    case claudeCode = "Claude Code"
    case codexCLI = "Codex CLI"
    case aider = "aider"

    var profile: ExternalToolProfile {
        switch self {
        case .claudeCode:
            return ExternalToolProfile(
                name: "Claude Code",
                icon: "terminal.fill",
                command: "claude",
                arguments: [],
                healthCheckPatterns: .claudeCode
            )
        case .codexCLI:
            return ExternalToolProfile(
                name: "Codex CLI",
                icon: "terminal.fill",
                command: "codex",
                arguments: [],
                healthCheckPatterns: .codexCLI
            )
        case .aider:
            return ExternalToolProfile(
                name: "aider",
                icon: "terminal.fill",
                command: "aider",
                arguments: [],
                healthCheckPatterns: .aider
            )
        }
    }
}

// MARK: - Session

@MainActor
@Observable
final class ExternalToolSession: Identifiable, @unchecked Sendable {
    let id: UUID
    let profileId: UUID
    var tmuxSessionName: String
    var status: ExternalToolStatus
    var lastOutput: [String]
    var lastHealthCheckDate: Date?
    var startedAt: Date?
    var lastActivityText: String?
    var lastCommandDate: Date?
    var lastTerminalTitle: String?

    init(
        id: UUID = UUID(),
        profileId: UUID,
        tmuxSessionName: String,
        status: ExternalToolStatus = .unknown,
        lastOutput: [String] = [],
        startedAt: Date? = Date()
    ) {
        self.id = id
        self.profileId = profileId
        self.tmuxSessionName = tmuxSessionName
        self.status = status
        self.lastOutput = lastOutput
        self.startedAt = startedAt
    }
}
