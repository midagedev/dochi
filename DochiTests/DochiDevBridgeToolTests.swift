import XCTest
@testable import Dochi

@MainActor
final class DochiDevBridgeToolTests: XCTestCase {

    func testBridgeOpenCreatesProfileAndSession() async {
        let manager = MockExternalToolSessionManager()
        let tool = DochiBridgeOpenTool(manager: manager)

        let result = await tool.execute(arguments: [
            "agent": "codex",
            "working_directory": "/tmp"
        ])

        XCTAssertFalse(result.isError)
        XCTAssertEqual(manager.saveProfileCallCount, 1)
        XCTAssertEqual(manager.startSessionCallCount, 1)
        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertTrue(result.content.contains("session_id"))
    }

    func testBridgeOpenReusesExistingSession() async throws {
        let manager = MockExternalToolSessionManager()
        let existingProfile = ExternalToolProfile(
            name: "Dochi Bridge Codex",
            command: "codex",
            workingDirectory: "~/repo"
        )
        manager.saveProfile(existingProfile)
        try await manager.startSession(profileId: existingProfile.id)

        let tool = DochiBridgeOpenTool(manager: manager)
        let result = await tool.execute(arguments: ["agent": "codex"])

        XCTAssertFalse(result.isError)
        XCTAssertEqual(manager.startSessionCallCount, 1)
        XCTAssertTrue(result.content.contains("이미 열려 있습니다"))
    }

    func testBridgeSendDispatchesCommand() async throws {
        let manager = MockExternalToolSessionManager()
        let profile = ExternalToolProfile(name: "Dochi Bridge Codex", command: "codex")
        manager.saveProfile(profile)
        try await manager.startSession(profileId: profile.id)

        let sessionId = try XCTUnwrap(manager.sessions.first?.id)
        let tool = DochiBridgeSendTool(manager: manager)

        let result = await tool.execute(arguments: [
            "session_id": sessionId.uuidString,
            "command": "status"
        ])

        XCTAssertFalse(result.isError)
        XCTAssertEqual(manager.sendCommandCallCount, 1)
        XCTAssertEqual(manager.lastSentCommand, "status")
    }

    func testBridgeReadReturnsOutput() async throws {
        let manager = MockExternalToolSessionManager()
        manager.mockOutputLines = ["line one", "line two", "line three"]

        let profile = ExternalToolProfile(name: "Dochi Bridge Codex", command: "codex")
        manager.saveProfile(profile)
        try await manager.startSession(profileId: profile.id)

        let sessionId = try XCTUnwrap(manager.sessions.first?.id)
        let tool = DochiBridgeReadTool(manager: manager)

        let result = await tool.execute(arguments: [
            "session_id": sessionId.uuidString,
            "lines": 2
        ])

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("line one"))
        XCTAssertTrue(result.content.contains("line two"))
        XCTAssertFalse(result.content.contains("line three"))
    }

    func testBridgeStatusShowsSingleSession() async throws {
        let manager = MockExternalToolSessionManager()
        let profile = ExternalToolProfile(name: "Dochi Bridge Codex", command: "codex")
        manager.saveProfile(profile)
        try await manager.startSession(profileId: profile.id)

        let sessionId = try XCTUnwrap(manager.sessions.first?.id)
        let tool = DochiBridgeStatusTool(manager: manager)

        let result = await tool.execute(arguments: ["session_id": sessionId.uuidString])

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("status="))
        XCTAssertTrue(result.content.contains(sessionId.uuidString))
    }

    func testLogRecentWithInjectedFetcherFormatsOutput() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tool = DochiLogRecentTool(fetcher: { minutes, category, level, contains, limit in
            XCTAssertEqual(minutes, 5)
            XCTAssertEqual(category, "Tool")
            XCTAssertEqual(level, "error")
            XCTAssertEqual(contains, "bridge")
            XCTAssertEqual(limit, 2)
            return [
                DochiLogLine(date: now, category: "Tool", level: "error", message: "bridge failed"),
                DochiLogLine(date: now.addingTimeInterval(1), category: "Tool", level: "error", message: "retry success")
            ]
        })

        let result = await tool.execute(arguments: [
            "minutes": 5,
            "limit": 2,
            "category": "Tool",
            "level": "error",
            "contains": "bridge"
        ])

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("최근 로그 2건"))
        XCTAssertTrue(result.content.contains("bridge failed"))
        XCTAssertTrue(result.content.contains("retry success"))
    }

    func testLogRecentRejectsInvalidLevel() async {
        let tool = DochiLogRecentTool(fetcher: { _, _, _, _, _ in
            XCTFail("Fetcher should not be called for invalid level")
            return []
        })

        let result = await tool.execute(arguments: ["level": "warn"])

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("level은"))
    }

    func testLogRecentReturnsErrorWhenFetcherFails() async {
        let tool = DochiLogRecentTool(fetcher: { _, _, _, _, _ in
            throw DochiLogFetchError.storeAccessFailed("store unavailable")
        })

        let result = await tool.execute(arguments: [:])

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("로그 조회 실패"))
    }
}
