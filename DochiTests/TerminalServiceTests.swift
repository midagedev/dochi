import XCTest
@testable import Dochi

@MainActor
final class TerminalServiceTests: XCTestCase {

    // MARK: - Session Management

    func testCreateSession() {
        let service = TerminalService(maxSessions: 4)
        let id = service.createSession(name: "테스트", shellPath: "/bin/zsh")

        XCTAssertEqual(service.sessions.count, 1)
        XCTAssertEqual(service.sessions.first?.name, "테스트")
        XCTAssertEqual(service.activeSessionId, id)
        XCTAssertTrue(service.sessions.first?.isRunning ?? false)
    }

    func testCreateSessionDefaultName() {
        let service = TerminalService(maxSessions: 4)
        service.createSession(name: nil, shellPath: "/bin/zsh")

        XCTAssertEqual(service.sessions.first?.name, "터미널 1")
    }

    func testMaxSessionsLimit() {
        let service = TerminalService(maxSessions: 2)
        service.createSession(name: "1", shellPath: "/bin/zsh")
        service.createSession(name: "2", shellPath: "/bin/zsh")
        service.createSession(name: "3", shellPath: "/bin/zsh") // Should not create

        XCTAssertEqual(service.sessions.count, 2)
    }

    func testCloseSession() {
        let service = TerminalService(maxSessions: 4)
        let id = service.createSession(name: "테스트", shellPath: "/bin/zsh")

        service.closeSession(id: id)

        XCTAssertEqual(service.sessions.count, 0)
        XCTAssertNil(service.activeSessionId)
    }

    func testCloseSessionSwitchesActive() {
        let service = TerminalService(maxSessions: 4)
        let id1 = service.createSession(name: "1", shellPath: "/bin/zsh")
        let id2 = service.createSession(name: "2", shellPath: "/bin/zsh")

        // Active should be id2 (latest)
        XCTAssertEqual(service.activeSessionId, id2)

        // Close id2, active should switch to id1
        service.closeSession(id: id2)
        XCTAssertEqual(service.activeSessionId, id1)
    }

    func testCloseAllSessions() {
        let service = TerminalService(maxSessions: 4)
        service.createSession(name: "1", shellPath: "/bin/zsh")
        service.createSession(name: "2", shellPath: "/bin/zsh")

        service.closeAllSessions()

        XCTAssertEqual(service.sessions.count, 0)
        XCTAssertNil(service.activeSessionId)
    }

    // MARK: - Welcome Message

    func testWelcomeMessage() {
        let service = TerminalService(maxSessions: 4)
        service.createSession(name: "테스트", shellPath: "/bin/zsh")

        let session = service.sessions.first!
        XCTAssertFalse(session.outputLines.isEmpty)
        XCTAssertEqual(session.outputLines.first?.type, .system)
        XCTAssertTrue(session.outputLines.first?.text.contains("쉘 시작됨") ?? false)
    }

    // MARK: - Clear Output

    func testClearOutput() {
        let service = TerminalService(maxSessions: 4)
        let id = service.createSession(name: "테스트", shellPath: "/bin/zsh")

        service.clearOutput(for: id)

        let session = service.sessions.first!
        XCTAssertEqual(session.outputLines.count, 1) // clear message
        XCTAssertEqual(session.outputLines.first?.type, .system)
        XCTAssertTrue(session.outputLines.first?.text.contains("출력이 지워졌습니다") ?? false)
    }

    // MARK: - Command History

    func testCommandHistory() {
        let service = TerminalService(maxSessions: 4)
        let id = service.createSession(name: "테스트", shellPath: "/bin/zsh")

        // Execute some commands
        service.executeCommand("echo hello", in: id)
        service.executeCommand("ls", in: id)

        let session = service.sessions.first!
        XCTAssertEqual(session.commandHistory, ["echo hello", "ls"])
    }

    func testHistoryNavigation() {
        let service = TerminalService(maxSessions: 4)
        let id = service.createSession(name: "테스트", shellPath: "/bin/zsh")

        service.executeCommand("cmd1", in: id)
        service.executeCommand("cmd2", in: id)
        service.executeCommand("cmd3", in: id)

        // Navigate up
        let prev1 = service.navigateHistory(sessionId: id, direction: -1)
        XCTAssertEqual(prev1, "cmd3")

        let prev2 = service.navigateHistory(sessionId: id, direction: -1)
        XCTAssertEqual(prev2, "cmd2")

        // Navigate down
        let next1 = service.navigateHistory(sessionId: id, direction: 1)
        XCTAssertEqual(next1, "cmd3")

        // Navigate down past end returns empty
        let next2 = service.navigateHistory(sessionId: id, direction: 1)
        XCTAssertEqual(next2, "")
    }

    func testHistoryNavigationEmptyHistory() {
        let service = TerminalService(maxSessions: 4)
        let id = service.createSession(name: "테스트", shellPath: "/bin/zsh")

        let result = service.navigateHistory(sessionId: id, direction: -1)
        XCTAssertNil(result)
    }

    // MARK: - Callbacks

    func testOnSessionClosedCallback() {
        let service = TerminalService(maxSessions: 4)
        var closedId: UUID?
        service.onSessionClosed = { id in closedId = id }

        let id = service.createSession(name: "테스트", shellPath: "/bin/zsh")
        service.closeSession(id: id)

        XCTAssertEqual(closedId, id)
    }

    func testOnOutputUpdateCallback() {
        let service = TerminalService(maxSessions: 4)
        var updatedId: UUID?
        service.onOutputUpdate = { id in updatedId = id }

        let id = service.createSession(name: "테스트", shellPath: "/bin/zsh")
        service.clearOutput(for: id)

        XCTAssertEqual(updatedId, id)
    }

    // MARK: - Model Tests

    func testTerminalSessionInit() {
        let session = TerminalSession()
        XCTAssertEqual(session.name, "터미널")
        XCTAssertTrue(session.outputLines.isEmpty)
        XCTAssertFalse(session.isRunning)
        XCTAssertTrue(session.commandHistory.isEmpty)
        XCTAssertNil(session.historyIndex)
    }

    func testTerminalOutputLineInit() {
        let line = TerminalOutputLine(text: "hello", type: .stdout)
        XCTAssertEqual(line.text, "hello")
        XCTAssertEqual(line.type, .stdout)
    }

    func testOutputType() {
        // Ensure all types exist
        let types: [OutputType] = [.stdout, .stderr, .system, .llmCommand, .llmPrompt]
        XCTAssertEqual(types.count, 5)
    }

    // MARK: - RunCommand

    func testRunCommandSuccess() async {
        let service = TerminalService(maxSessions: 4)
        let result = await service.runCommand("echo hello")

        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("hello"))
    }

    func testRunCommandFailure() async {
        let service = TerminalService(maxSessions: 4)
        let result = await service.runCommand("false")

        XCTAssertTrue(result.isError)
        XCTAssertNotEqual(result.exitCode, 0)
    }

    func testRunCommandWithOutput() async {
        let service = TerminalService(maxSessions: 4)
        let result = await service.runCommand("echo 'test output'")

        XCTAssertTrue(result.output.contains("test output"))
    }
}
