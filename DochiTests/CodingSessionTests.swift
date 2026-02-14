import XCTest
@testable import Dochi

@MainActor
final class CodingSessionTests: XCTestCase {

    // MARK: - CodingAgentType

    func testAgentTypeCliNames() {
        XCTAssertEqual(CodingAgentType.claudeCode.cliName, "claude")
        XCTAssertEqual(CodingAgentType.codex.cliName, "codex")
    }

    func testAgentTypeDisplayNames() {
        XCTAssertEqual(CodingAgentType.claudeCode.displayName, "Claude Code")
        XCTAssertEqual(CodingAgentType.codex.displayName, "Codex")
    }

    func testAgentTypeCodable() throws {
        for type in CodingAgentType.allCases {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(CodingAgentType.self, from: data)
            XCTAssertEqual(decoded, type)
        }
    }

    func testAgentTypeRawValues() {
        XCTAssertEqual(CodingAgentType.claudeCode.rawValue, "claude_code")
        XCTAssertEqual(CodingAgentType.codex.rawValue, "codex")
    }

    // MARK: - CodingSessionStep

    func testStepInitDefaults() {
        let step = CodingSessionStep(instruction: "테스트 추가")
        XCTAssertEqual(step.instruction, "테스트 추가")
        XCTAssertNil(step.output)
        XCTAssertNil(step.isSuccess)
        XCTAssertNil(step.completedAt)
        XCTAssertNil(step.duration)
    }

    func testStepDuration() {
        let started = Date()
        let completed = started.addingTimeInterval(30)
        let step = CodingSessionStep(
            instruction: "test",
            output: "ok",
            isSuccess: true,
            startedAt: started,
            completedAt: completed
        )
        XCTAssertEqual(step.duration!, 30, accuracy: 0.01)
    }

    func testStepCodable() throws {
        let step = CodingSessionStep(
            instruction: "fix bug",
            output: "done",
            isSuccess: true,
            completedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(step)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CodingSessionStep.self, from: data)
        XCTAssertEqual(decoded.id, step.id)
        XCTAssertEqual(decoded.instruction, "fix bug")
        XCTAssertEqual(decoded.isSuccess, true)
    }

    // MARK: - CodingSession Model

    func testSessionInitDefaults() {
        let session = CodingSession(
            agentType: .claudeCode,
            workingDirectory: "/tmp/project"
        )
        XCTAssertEqual(session.agentType, .claudeCode)
        XCTAssertEqual(session.workingDirectory, "/tmp/project")
        XCTAssertEqual(session.status, .active)
        XCTAssertTrue(session.steps.isEmpty)
        XCTAssertEqual(session.stepCount, 0)
        XCTAssertEqual(session.successfulSteps, 0)
        XCTAssertEqual(session.failedSteps, 0)
        XCTAssertNil(session.summary)
        XCTAssertNil(session.lastOutput)
    }

    func testSessionStepCounts() {
        var session = CodingSession(agentType: .claudeCode, workingDirectory: "/tmp")
        session.steps = [
            CodingSessionStep(instruction: "a", isSuccess: true),
            CodingSessionStep(instruction: "b", isSuccess: false),
            CodingSessionStep(instruction: "c", isSuccess: true),
            CodingSessionStep(instruction: "d"), // in progress
        ]
        XCTAssertEqual(session.stepCount, 4)
        XCTAssertEqual(session.successfulSteps, 2)
        XCTAssertEqual(session.failedSteps, 1)
    }

    func testSessionLastOutput() {
        var session = CodingSession(agentType: .codex, workingDirectory: "/tmp")
        session.steps = [
            CodingSessionStep(instruction: "a", output: "first"),
            CodingSessionStep(instruction: "b", output: "second"),
        ]
        XCTAssertEqual(session.lastOutput, "second")
    }

    func testSessionCodable() throws {
        let session = CodingSession(
            agentType: .codex,
            workingDirectory: "/home/project",
            summary: "테스트 완료"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CodingSession.self, from: data)
        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.agentType, .codex)
        XCTAssertEqual(decoded.summary, "테스트 완료")
    }

    // MARK: - Session Manager: Create

    func testCreateSession() {
        let manager = CodingSessionManager()
        let session = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp/test")
        XCTAssertEqual(session.status, .active)
        XCTAssertEqual(session.agentType, .claudeCode)
        XCTAssertNotNil(manager.session(id: session.id))
    }

    func testCreateMultipleSessions() {
        let manager = CodingSessionManager()
        manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp/a")
        manager.createSession(agentType: .codex, workingDirectory: "/tmp/b")
        XCTAssertEqual(manager.allSessions().count, 2)
    }

    // MARK: - Session Manager: Active Sessions

    func testActiveSessions() {
        let manager = CodingSessionManager()
        let s1 = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp/a")
        manager.createSession(agentType: .codex, workingDirectory: "/tmp/b")

        XCTAssertEqual(manager.activeSessions().count, 2)

        _ = manager.pauseSession(id: s1.id)
        XCTAssertEqual(manager.activeSessions().count, 1)
    }

    // MARK: - Session Manager: Steps

    func testAddStep() {
        let manager = CodingSessionManager()
        let session = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp")
        let step = manager.addStep(sessionId: session.id, instruction: "테스트 작성")
        XCTAssertNotNil(step)
        XCTAssertEqual(manager.session(id: session.id)!.stepCount, 1)
    }

    func testAddStepToNonActiveSession() {
        let manager = CodingSessionManager()
        let session = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp")
        _ = manager.completeSession(id: session.id)
        let step = manager.addStep(sessionId: session.id, instruction: "more work")
        XCTAssertNil(step) // can't add to completed session
    }

    func testCompleteStep() {
        let manager = CodingSessionManager()
        let session = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp")
        let step = manager.addStep(sessionId: session.id, instruction: "fix bug")!
        let result = manager.completeStep(sessionId: session.id, stepId: step.id, output: "fixed!", isSuccess: true)
        XCTAssertTrue(result)

        let updated = manager.session(id: session.id)!
        XCTAssertEqual(updated.steps[0].output, "fixed!")
        XCTAssertEqual(updated.steps[0].isSuccess, true)
        XCTAssertNotNil(updated.steps[0].completedAt)
    }

    func testCompleteStepNonExistent() {
        let manager = CodingSessionManager()
        let session = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp")
        let result = manager.completeStep(sessionId: session.id, stepId: UUID(), output: "ok", isSuccess: true)
        XCTAssertFalse(result)
    }

    // MARK: - Session Manager: Status Updates

    func testPauseAndResume() {
        let manager = CodingSessionManager()
        let session = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp")

        XCTAssertTrue(manager.pauseSession(id: session.id))
        XCTAssertEqual(manager.session(id: session.id)!.status, .paused)

        XCTAssertTrue(manager.resumeSession(id: session.id))
        XCTAssertEqual(manager.session(id: session.id)!.status, .active)
    }

    func testPauseNonActive() {
        let manager = CodingSessionManager()
        let session = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp")
        _ = manager.completeSession(id: session.id)
        XCTAssertFalse(manager.pauseSession(id: session.id)) // can't pause completed
    }

    func testResumeNonPaused() {
        let manager = CodingSessionManager()
        let session = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp")
        XCTAssertFalse(manager.resumeSession(id: session.id)) // active, not paused
    }

    func testCompleteSession() {
        let manager = CodingSessionManager()
        let session = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp")
        XCTAssertTrue(manager.completeSession(id: session.id, summary: "All done"))
        let updated = manager.session(id: session.id)!
        XCTAssertEqual(updated.status, .completed)
        XCTAssertEqual(updated.summary, "All done")
    }

    func testCompleteFromPaused() {
        let manager = CodingSessionManager()
        let session = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp")
        _ = manager.pauseSession(id: session.id)
        XCTAssertTrue(manager.completeSession(id: session.id))
    }

    func testCompleteAlreadyCompleted() {
        let manager = CodingSessionManager()
        let session = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp")
        _ = manager.completeSession(id: session.id)
        XCTAssertFalse(manager.completeSession(id: session.id)) // already completed
    }

    func testFailSession() {
        let manager = CodingSessionManager()
        let session = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp")
        XCTAssertTrue(manager.failSession(id: session.id, summary: "Build error"))
        let updated = manager.session(id: session.id)!
        XCTAssertEqual(updated.status, .failed)
        XCTAssertEqual(updated.summary, "Build error")
    }

    // MARK: - Session Manager: Cleanup

    func testRemoveSession() {
        let manager = CodingSessionManager()
        let session = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp")
        XCTAssertTrue(manager.removeSession(id: session.id))
        XCTAssertNil(manager.session(id: session.id))
    }

    func testRemoveNonExistent() {
        let manager = CodingSessionManager()
        XCTAssertFalse(manager.removeSession(id: UUID()))
    }

    func testCleanupCompleted() {
        let manager = CodingSessionManager()
        let session = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp")
        _ = manager.completeSession(id: session.id)

        // Move lastActivityAt to distant past
        manager.sessions[session.id]!.lastActivityAt = Date().addingTimeInterval(-1_000_000)

        manager.cleanupCompleted(olderThan: 86400 * 7)
        XCTAssertNil(manager.session(id: session.id))
    }

    func testCleanupKeepsRecent() {
        let manager = CodingSessionManager()
        let session = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp")
        _ = manager.completeSession(id: session.id)

        manager.cleanupCompleted(olderThan: 86400 * 7)
        XCTAssertNotNil(manager.session(id: session.id)) // recent
    }

    func testCleanupKeepsActive() {
        let manager = CodingSessionManager()
        let session = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp")
        manager.sessions[session.id]!.lastActivityAt = Date().addingTimeInterval(-1_000_000)

        manager.cleanupCompleted(olderThan: 86400 * 7)
        XCTAssertNotNil(manager.session(id: session.id)) // active, not cleaned
    }

    // MARK: - Session Tools

    func testSessionListToolEmpty() async {
        let manager = CodingSessionManager()
        let tool = CodingSessionListTool(sessionManager: manager)
        XCTAssertEqual(tool.name, "coding.sessions")
        XCTAssertEqual(tool.category, .safe)
        XCTAssertFalse(tool.isBaseline)

        let result = await tool.execute(arguments: [:])
        XCTAssertTrue(result.content.contains("없습니다"))
    }

    func testSessionListToolWithSessions() async {
        let manager = CodingSessionManager()
        manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp/a")
        manager.createSession(agentType: .codex, workingDirectory: "/tmp/b")

        let tool = CodingSessionListTool(sessionManager: manager)
        let result = await tool.execute(arguments: [:])
        XCTAssertTrue(result.content.contains("2개"))
    }

    func testSessionListToolFilterActive() async {
        let manager = CodingSessionManager()
        let s1 = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp/a")
        manager.createSession(agentType: .codex, workingDirectory: "/tmp/b")
        _ = manager.pauseSession(id: s1.id)

        let tool = CodingSessionListTool(sessionManager: manager)
        let result = await tool.execute(arguments: ["status": "active"])
        XCTAssertTrue(result.content.contains("1개"))
    }

    func testSessionStartTool() async {
        let manager = CodingSessionManager()
        let tool = CodingSessionStartTool(sessionManager: manager)
        XCTAssertEqual(tool.name, "coding.session_start")
        XCTAssertEqual(tool.category, .restricted)

        let result = await tool.execute(arguments: ["work_dir": "/tmp"])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("세션 시작"))
        XCTAssertEqual(manager.allSessions().count, 1)
    }

    func testSessionStartToolMissingDir() async {
        let manager = CodingSessionManager()
        let tool = CodingSessionStartTool(sessionManager: manager)
        let result = await tool.execute(arguments: [:])
        XCTAssertTrue(result.isError)
    }

    func testSessionStartToolNonExistentDir() async {
        let manager = CodingSessionManager()
        let tool = CodingSessionStartTool(sessionManager: manager)
        let result = await tool.execute(arguments: ["work_dir": "/nonexistent/path/xyz"])
        XCTAssertTrue(result.isError)
    }

    func testSessionPauseTool() async {
        let manager = CodingSessionManager()
        let session = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp")
        let tool = CodingSessionPauseTool(sessionManager: manager)

        let result = await tool.execute(arguments: [
            "session_id": session.id.uuidString,
            "action": "pause",
        ])
        XCTAssertFalse(result.isError)
        XCTAssertEqual(manager.session(id: session.id)!.status, .paused)
    }

    func testSessionPauseToolPartialId() async {
        let manager = CodingSessionManager()
        let session = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp")
        let shortId = String(session.id.uuidString.prefix(8))
        let tool = CodingSessionPauseTool(sessionManager: manager)

        let result = await tool.execute(arguments: [
            "session_id": shortId,
            "action": "pause",
        ])
        XCTAssertFalse(result.isError)
    }

    func testSessionEndTool() async {
        let manager = CodingSessionManager()
        let session = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp")
        _ = manager.addStep(sessionId: session.id, instruction: "test")

        let tool = CodingSessionEndTool(sessionManager: manager)
        let result = await tool.execute(arguments: [
            "session_id": session.id.uuidString,
            "summary": "작업 완료",
        ])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("완료"))
        XCTAssertEqual(manager.session(id: session.id)!.status, .completed)
    }

    func testSessionEndToolFailed() async {
        let manager = CodingSessionManager()
        let session = manager.createSession(agentType: .claudeCode, workingDirectory: "/tmp")
        let tool = CodingSessionEndTool(sessionManager: manager)

        let result = await tool.execute(arguments: [
            "session_id": session.id.uuidString,
            "result": "failed",
            "summary": "빌드 에러",
        ])
        XCTAssertFalse(result.isError)
        XCTAssertEqual(manager.session(id: session.id)!.status, .failed)
    }
}
