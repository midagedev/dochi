import Foundation

// MARK: - DelegationStatus

enum DelegationStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

// MARK: - DelegationTask

struct DelegationTask: Identifiable, Codable, Sendable {
    let id: UUID
    let parentDelegationId: UUID?
    let originAgentName: String
    let targetAgentName: String
    let task: String
    let context: String?
    var status: DelegationStatus
    let createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var result: String?
    var errorMessage: String?
    let chainDepth: Int

    init(
        id: UUID = UUID(),
        parentDelegationId: UUID? = nil,
        originAgentName: String,
        targetAgentName: String,
        task: String,
        context: String? = nil,
        status: DelegationStatus = .pending,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        result: String? = nil,
        errorMessage: String? = nil,
        chainDepth: Int = 0
    ) {
        self.id = id
        self.parentDelegationId = parentDelegationId
        self.originAgentName = originAgentName
        self.targetAgentName = targetAgentName
        self.task = task
        self.context = context
        self.status = status
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.result = result
        self.errorMessage = errorMessage
        self.chainDepth = chainDepth
    }

    /// Duration in seconds from start to completion (nil if not started or not completed).
    var durationSeconds: TimeInterval? {
        guard let start = startedAt, let end = completedAt else { return nil }
        return end.timeIntervalSince(start)
    }
}

// MARK: - DelegationChain

struct DelegationChain: Identifiable, Sendable {
    let id: UUID
    var tasks: [DelegationTask]

    init(id: UUID = UUID(), tasks: [DelegationTask] = []) {
        self.id = id
        self.tasks = tasks
    }

    /// Current maximum depth in the chain.
    var currentDepth: Int {
        tasks.map(\.chainDepth).max() ?? 0
    }

    /// Whether all tasks in the chain are completed or failed/cancelled.
    var isComplete: Bool {
        guard !tasks.isEmpty else { return true }
        return tasks.allSatisfy { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
    }

    /// Whether any task in the chain has failed.
    var hasError: Bool {
        tasks.contains { $0.status == .failed }
    }

    /// All unique agent names involved in the chain.
    var involvedAgents: [String] {
        var agents: [String] = []
        for task in tasks {
            if !agents.contains(task.originAgentName) {
                agents.append(task.originAgentName)
            }
            if !agents.contains(task.targetAgentName) {
                agents.append(task.targetAgentName)
            }
        }
        return agents
    }

    /// Check if delegating to the target agent would create a cycle.
    func wouldCreateCycle(targetAgent: String) -> Bool {
        // A cycle occurs if the target agent already appears as an origin in the chain
        // that leads back to itself
        let origins = tasks.map(\.originAgentName)
        let targets = tasks.map(\.targetAgentName)
        let allAgents = Set(origins + targets)

        // Simple cycle check: if target is already an origin in the chain, it would create a cycle
        guard allAgents.contains(targetAgent) else { return false }

        // Build adjacency: if targetAgent delegates to someone who eventually delegates back to targetAgent
        return origins.contains(targetAgent)
    }
}

// MARK: - DelegationResult

struct DelegationResult: Sendable {
    let delegationId: UUID
    let targetAgentName: String
    let success: Bool
    let response: String
    let tokensUsed: Int?
    let duration: TimeInterval
    let subDelegations: [DelegationResult]?
}

// MARK: - DelegationPolicy

struct DelegationPolicy: Codable, Sendable, Equatable {
    var canDelegate: Bool
    var canReceiveDelegation: Bool
    var allowedTargets: [String]?
    var blockedTargets: [String]?
    var maxChainDepth: Int

    init(
        canDelegate: Bool = true,
        canReceiveDelegation: Bool = true,
        allowedTargets: [String]? = nil,
        blockedTargets: [String]? = nil,
        maxChainDepth: Int = 3
    ) {
        self.canDelegate = canDelegate
        self.canReceiveDelegation = canReceiveDelegation
        self.allowedTargets = allowedTargets
        self.blockedTargets = blockedTargets
        self.maxChainDepth = maxChainDepth
    }

    /// Check if delegation to a specific target is allowed by this policy.
    func allowsDelegationTo(_ targetAgent: String) -> Bool {
        guard canDelegate else { return false }

        // Check blocked targets first
        if let blocked = blockedTargets, blocked.contains(where: { $0.localizedCaseInsensitiveCompare(targetAgent) == .orderedSame }) {
            return false
        }

        // Check allowed targets (if specified, only those are allowed)
        if let allowed = allowedTargets {
            return allowed.contains(where: { $0.localizedCaseInsensitiveCompare(targetAgent) == .orderedSame })
        }

        return true
    }

    static let `default` = DelegationPolicy()
}
