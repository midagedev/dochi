import Foundation

// MARK: - Coding Agent Types

enum CodingAgentType: String, Codable, Sendable, CaseIterable {
    case claudeCode = "claude_code"
    case codex

    var cliName: String {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        }
    }

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }
}

enum CodingSessionStatus: String, Codable, Sendable {
    case active
    case paused
    case completed
    case failed
}

// MARK: - Session Step

struct CodingSessionStep: Codable, Identifiable, Sendable {
    let id: UUID
    let instruction: String
    var output: String?
    var isSuccess: Bool?
    let startedAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        instruction: String,
        output: String? = nil,
        isSuccess: Bool? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.instruction = instruction
        self.output = output
        self.isSuccess = isSuccess
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    var duration: TimeInterval? {
        guard let completedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt)
    }
}

// MARK: - Session Model

struct CodingSession: Codable, Identifiable, Sendable {
    let id: UUID
    var agentType: CodingAgentType
    var workingDirectory: String
    var status: CodingSessionStatus
    var steps: [CodingSessionStep]
    let startedAt: Date
    var lastActivityAt: Date
    var summary: String?

    init(
        id: UUID = UUID(),
        agentType: CodingAgentType,
        workingDirectory: String,
        status: CodingSessionStatus = .active,
        steps: [CodingSessionStep] = [],
        startedAt: Date = Date(),
        lastActivityAt: Date = Date(),
        summary: String? = nil
    ) {
        self.id = id
        self.agentType = agentType
        self.workingDirectory = workingDirectory
        self.status = status
        self.steps = steps
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.summary = summary
    }

    var totalDuration: TimeInterval {
        lastActivityAt.timeIntervalSince(startedAt)
    }

    var stepCount: Int { steps.count }

    var successfulSteps: Int {
        steps.filter { $0.isSuccess == true }.count
    }

    var failedSteps: Int {
        steps.filter { $0.isSuccess == false }.count
    }

    var lastOutput: String? {
        steps.last?.output
    }
}

// MARK: - Session Manager

@MainActor
final class CodingSessionManager {
    var sessions: [UUID: CodingSession] = [:]

    init() {}

    // MARK: - Session CRUD

    @discardableResult
    func createSession(
        agentType: CodingAgentType,
        workingDirectory: String
    ) -> CodingSession {
        let session = CodingSession(
            agentType: agentType,
            workingDirectory: workingDirectory
        )
        sessions[session.id] = session
        Log.tool.info("Coding session created: \(agentType.displayName) @ \(workingDirectory)")
        return session
    }

    func session(id: UUID) -> CodingSession? {
        sessions[id]
    }

    func activeSessions() -> [CodingSession] {
        sessions.values
            .filter { $0.status == .active }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    func allSessions(limit: Int = 20) -> [CodingSession] {
        Array(
            sessions.values
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(limit)
        )
    }

    // MARK: - Step Tracking

    @discardableResult
    func addStep(sessionId: UUID, instruction: String) -> CodingSessionStep? {
        guard var session = sessions[sessionId], session.status == .active else { return nil }
        let step = CodingSessionStep(instruction: instruction)
        session.steps.append(step)
        session.lastActivityAt = Date()
        sessions[sessionId] = session
        Log.tool.debug("Step added to session [\(sessionId.uuidString.prefix(8))]: \(instruction.prefix(60))")
        return step
    }

    func completeStep(sessionId: UUID, stepId: UUID, output: String, isSuccess: Bool) -> Bool {
        guard var session = sessions[sessionId] else { return false }
        guard let idx = session.steps.firstIndex(where: { $0.id == stepId }) else { return false }

        session.steps[idx].output = output
        session.steps[idx].isSuccess = isSuccess
        session.steps[idx].completedAt = Date()
        session.lastActivityAt = Date()
        sessions[sessionId] = session
        return true
    }

    // MARK: - Status Updates

    func pauseSession(id: UUID) -> Bool {
        guard var session = sessions[id], session.status == .active else { return false }
        session.status = .paused
        session.lastActivityAt = Date()
        sessions[id] = session
        Log.tool.info("Coding session paused: [\(id.uuidString.prefix(8))]")
        return true
    }

    func resumeSession(id: UUID) -> Bool {
        guard var session = sessions[id], session.status == .paused else { return false }
        session.status = .active
        session.lastActivityAt = Date()
        sessions[id] = session
        Log.tool.info("Coding session resumed: [\(id.uuidString.prefix(8))]")
        return true
    }

    func completeSession(id: UUID, summary: String? = nil) -> Bool {
        guard var session = sessions[id],
              session.status == .active || session.status == .paused else { return false }
        session.status = .completed
        session.summary = summary
        session.lastActivityAt = Date()
        sessions[id] = session
        Log.tool.info("Coding session completed: [\(id.uuidString.prefix(8))]")
        return true
    }

    func failSession(id: UUID, summary: String? = nil) -> Bool {
        guard var session = sessions[id],
              session.status == .active || session.status == .paused else { return false }
        session.status = .failed
        session.summary = summary
        session.lastActivityAt = Date()
        sessions[id] = session
        Log.tool.error("Coding session failed: [\(id.uuidString.prefix(8))]")
        return true
    }

    // MARK: - Cleanup

    func removeSession(id: UUID) -> Bool {
        sessions.removeValue(forKey: id) != nil
    }

    func cleanupCompleted(olderThan interval: TimeInterval = 86400 * 7) {
        let cutoff = Date().addingTimeInterval(-interval)
        let toRemove = sessions.values.filter {
            ($0.status == .completed || $0.status == .failed) && $0.lastActivityAt < cutoff
        }
        for session in toRemove {
            sessions.removeValue(forKey: session.id)
        }
        if !toRemove.isEmpty {
            Log.tool.debug("Cleaned up \(toRemove.count) old coding sessions")
        }
    }
}
