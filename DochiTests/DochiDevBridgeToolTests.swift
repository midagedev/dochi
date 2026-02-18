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
        XCTAssertTrue(result.content.contains("selection_reason: requested_working_directory"))
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
        XCTAssertTrue(result.content.contains("selection_reason: existing_session_reused"))
    }

    func testBridgeOpenPreservesExistingProfileWorkingDirectoryWithoutForce() async {
        let manager = MockExternalToolSessionManager()
        let existingProfile = ExternalToolProfile(
            name: "Dochi Bridge Codex",
            command: "codex",
            workingDirectory: "~/repo/existing"
        )
        manager.saveProfile(existingProfile)
        let tool = DochiBridgeOpenTool(manager: manager)

        let result = await tool.execute(arguments: [
            "agent": "codex",
            "working_directory": "/tmp/new"
        ])

        XCTAssertFalse(result.isError)
        XCTAssertEqual(manager.startSessionCallCount, 1)
        let saved = manager.profiles.first(where: { $0.id == existingProfile.id })
        XCTAssertEqual(saved?.workingDirectory, "~/repo/existing")
        XCTAssertTrue(result.content.contains("working_directory: ~/repo/existing"))
        XCTAssertTrue(result.content.contains("selection_reason: existing_profile_preserved"))
    }

    func testBridgeOpenForceWorkingDirectoryOverridesExistingProfile() async {
        let manager = MockExternalToolSessionManager()
        let existingProfile = ExternalToolProfile(
            name: "Dochi Bridge Codex",
            command: "codex",
            workingDirectory: "~/repo/existing"
        )
        manager.saveProfile(existingProfile)
        let tool = DochiBridgeOpenTool(manager: manager)

        let result = await tool.execute(arguments: [
            "agent": "codex",
            "working_directory": "/tmp/new",
            "force_working_directory": true,
        ])

        XCTAssertFalse(result.isError)
        XCTAssertEqual(manager.startSessionCallCount, 1)
        let saved = manager.profiles.first(where: { $0.id == existingProfile.id })
        XCTAssertEqual(saved?.workingDirectory, "/tmp/new")
        XCTAssertTrue(result.content.contains("working_directory: /tmp/new"))
        XCTAssertTrue(result.content.contains("selection_reason: existing_profile_overridden"))
    }

    func testBridgeOpenFallsBackToRecommendedRootForNewProfile() async {
        let manager = MockExternalToolSessionManager()
        manager.mockGitRepositoryInsights = [
            GitRepositoryInsight(
                workDomain: "company",
                workDomainConfidence: 0.9,
                workDomainReason: "test",
                path: "/Users/me/repo/top",
                name: "top",
                branch: "main",
                originURL: "git@github.com:acme/top.git",
                remoteHost: "github.com",
                remoteOwner: "acme",
                remoteRepository: "top",
                lastCommitEpoch: 1_700_000_000,
                lastCommitISO8601: "2023-11-14T22:13:20.000Z",
                lastCommitRelative: "1d ago",
                upstreamLastCommitEpoch: 1_700_000_000,
                upstreamLastCommitISO8601: "2023-11-14T22:13:20.000Z",
                upstreamLastCommitRelative: "1d ago",
                daysSinceLastCommit: 1,
                recentCommitCount30d: 12,
                changedFileCount: 3,
                untrackedFileCount: 1,
                aheadCount: 0,
                behindCount: 0,
                score: 67
            )
        ]
        let tool = DochiBridgeOpenTool(manager: manager)

        let result = await tool.execute(arguments: ["agent": "codex"])

        XCTAssertFalse(result.isError)
        XCTAssertEqual(manager.startSessionCallCount, 1)
        let saved = manager.profiles.first(where: { $0.name == "Dochi Bridge Codex" })
        XCTAssertEqual(saved?.workingDirectory, "/Users/me/repo/top")
        XCTAssertTrue(result.content.contains("working_directory: /Users/me/repo/top"))
        XCTAssertTrue(result.content.contains("selection_reason: recommended_git_root"))
    }

    func testBridgeOpenIgnoresForceWhenSessionAlreadyRunning() async throws {
        let manager = MockExternalToolSessionManager()
        let existingProfile = ExternalToolProfile(
            name: "Dochi Bridge Codex",
            command: "codex",
            workingDirectory: "~/repo/existing"
        )
        manager.saveProfile(existingProfile)
        try await manager.startSession(profileId: existingProfile.id)
        let tool = DochiBridgeOpenTool(manager: manager)

        let result = await tool.execute(arguments: [
            "agent": "codex",
            "working_directory": "/tmp/new",
            "force_working_directory": true,
        ])

        XCTAssertFalse(result.isError)
        XCTAssertEqual(manager.startSessionCallCount, 1)
        XCTAssertTrue(result.content.contains("working_directory: ~/repo/existing"))
        XCTAssertTrue(result.content.contains("selection_reason: existing_session_reused_force_ignored"))
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

    func testBridgeRootsReturnsRankedInsights() async {
        let manager = MockExternalToolSessionManager()
        manager.mockGitRepositoryInsights = [
            GitRepositoryInsight(
                workDomain: "company",
                workDomainConfidence: 0.8,
                workDomainReason: "test",
                path: "/Users/me/repo/a",
                name: "a",
                branch: "main",
                originURL: "git@github.com:acme/a.git",
                remoteHost: "github.com",
                remoteOwner: "acme",
                remoteRepository: "a",
                lastCommitEpoch: 1_700_000_000,
                lastCommitISO8601: "2023-11-14T22:13:20.000Z",
                lastCommitRelative: "1d ago",
                upstreamLastCommitEpoch: 1_700_000_000,
                upstreamLastCommitISO8601: "2023-11-14T22:13:20.000Z",
                upstreamLastCommitRelative: "1d ago",
                daysSinceLastCommit: 1,
                recentCommitCount30d: 12,
                changedFileCount: 3,
                untrackedFileCount: 1,
                aheadCount: 0,
                behindCount: 0,
                score: 67
            ),
            GitRepositoryInsight(
                workDomain: "personal",
                workDomainConfidence: 0.6,
                workDomainReason: "test",
                path: "/Users/me/repo/b",
                name: "b",
                branch: "feature/x",
                originURL: "git@github.com:me/b.git",
                remoteHost: "github.com",
                remoteOwner: "me",
                remoteRepository: "b",
                lastCommitEpoch: 1_699_000_000,
                lastCommitISO8601: "2023-11-03T08:26:40.000Z",
                lastCommitRelative: "12d ago",
                upstreamLastCommitEpoch: 1_699_000_000,
                upstreamLastCommitISO8601: "2023-11-03T08:26:40.000Z",
                upstreamLastCommitRelative: "12d ago",
                daysSinceLastCommit: 12,
                recentCommitCount30d: 3,
                changedFileCount: 0,
                untrackedFileCount: 0,
                aheadCount: nil,
                behindCount: nil,
                score: 21
            ),
        ]
        let tool = DochiBridgeRootsTool(manager: manager)

        let result = await tool.execute(arguments: ["limit": 5])

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("[67] a"))
        XCTAssertTrue(result.content.contains("/Users/me/repo/a"))
        XCTAssertTrue(result.content.contains("/Users/me/repo/b"))
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
