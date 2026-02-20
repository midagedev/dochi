import XCTest
@testable import Dochi

@MainActor
final class ToolContextStoreTests: XCTestCase {
    private func makeTempDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DochiToolContextTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    func testRecordAllowedEventUpdatesCategoryAndToolScores() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ToolContextStore(baseURL: tempDir)
        let event = ToolUsageEvent(
            toolName: "agent.list",
            category: "agent",
            decision: .allowed,
            latencyMs: 24,
            agentName: "코디",
            workspaceId: "ws-1",
            timestamp: Date()
        )

        await store.record(event)
        let profile = await store.profile(workspaceId: "ws-1", agentName: "코디")

        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.categoryScores["agent"] ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(profile?.toolScores["agent.list"] ?? 0, 1.0, accuracy: 0.001)
    }

    func testDeniedEventReducesScore() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ToolContextStore(baseURL: tempDir)
        let baseDate = Date()

        await store.record(ToolUsageEvent(
            toolName: "coding.sessions",
            category: "coding",
            decision: .allowed,
            latencyMs: 12,
            agentName: "코디",
            workspaceId: "ws-1",
            timestamp: baseDate
        ))

        await store.record(ToolUsageEvent(
            toolName: "coding.sessions",
            category: "coding",
            decision: .denied,
            latencyMs: 11,
            agentName: "코디",
            workspaceId: "ws-1",
            timestamp: baseDate.addingTimeInterval(1)
        ))

        let profile = await store.profile(workspaceId: "ws-1", agentName: "코디")
        let categoryScore = profile?.categoryScores["coding"] ?? 0
        let toolScore = profile?.toolScores["coding.sessions"] ?? 0

        XCTAssertLessThan(categoryScore, 1.0)
        XCTAssertGreaterThan(categoryScore, 0.5)
        XCTAssertLessThan(toolScore, 1.0)
        XCTAssertGreaterThan(toolScore, 0.5)
    }

    func testFlushAndReloadPersistsProfileAndPreferences() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ToolContextStore(baseURL: tempDir)

        await store.record(ToolUsageEvent(
            toolName: "agent.list",
            category: "agent",
            decision: .approved,
            latencyMs: 45,
            agentName: "코디",
            workspaceId: "ws-1",
            timestamp: Date()
        ))

        let preference = UserToolPreference(
            preferredCategories: ["coding", "agent"],
            suppressedCategories: ["calendar"],
            updatedAt: Date()
        )
        await store.updateUserPreference(preference, workspaceId: "ws-1")
        await store.flushToDisk()

        let reloaded = ToolContextStore(baseURL: tempDir)
        let profile = await reloaded.profile(workspaceId: "ws-1", agentName: "코디")
        let savedPreference = await reloaded.userPreference(workspaceId: "ws-1")

        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.toolScores["agent.list"] ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(savedPreference.preferredCategories, ["coding", "agent"])
        XCTAssertEqual(savedPreference.suppressedCategories, ["calendar"])
    }

    func testUpdateUserPreferenceNormalizesAndDeduplicatesCategories() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ToolContextStore(baseURL: tempDir)
        let preference = UserToolPreference(
            preferredCategories: [" Coding ", "coding", "AGENT"],
            suppressedCategories: [" calendar ", "Calendar", "coding", ""]
        )

        await store.updateUserPreference(preference, workspaceId: "ws-1")
        let savedPreference = await store.userPreference(workspaceId: "ws-1")

        XCTAssertEqual(savedPreference.preferredCategories, ["coding", "agent"])
        XCTAssertEqual(savedPreference.suppressedCategories, ["calendar"])
    }

    func testRankingContextAggregatesProfileAndPreferenceSignals() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ToolContextStore(baseURL: tempDir)
        await store.record(ToolUsageEvent(
            toolName: "agent.list",
            category: "agent",
            decision: .allowed,
            latencyMs: 10,
            agentName: "코디",
            workspaceId: "ws-1",
            timestamp: Date()
        ))
        await store.updateUserPreference(
            UserToolPreference(
                preferredCategories: ["Agent", " coding "],
                suppressedCategories: ["finder", "coding"]
            ),
            workspaceId: "ws-1"
        )

        let context = store.rankingContext(workspaceId: "ws-1", agentName: "코디")
        XCTAssertEqual(context.preferredCategories, ["agent", "coding"])
        XCTAssertEqual(context.suppressedCategories, ["finder"])
        XCTAssertEqual(context.toolScores["agent.list"] ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(context.categoryScores["agent"] ?? 0, 1.0, accuracy: 0.001)
    }

    func testMalformedJSONFallsBackToEmptyStore() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let malformedURL = tempDir.appendingPathComponent("tool_context.json")
        try "not valid json".write(to: malformedURL, atomically: true, encoding: .utf8)

        let store = ToolContextStore(baseURL: tempDir)
        let emptyProfile = await store.profile(workspaceId: "ws-1", agentName: "코디")
        XCTAssertNil(emptyProfile)

        await store.record(ToolUsageEvent(
            toolName: "agent.list",
            category: "agent",
            decision: .allowed,
            latencyMs: 10,
            agentName: "코디",
            workspaceId: "ws-1",
            timestamp: Date()
        ))

        let recoveredProfile = await store.profile(workspaceId: "ws-1", agentName: "코디")
        XCTAssertNotNil(recoveredProfile)
    }

    func testWriteFailureKeepsInMemoryState() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let blockedPath = tempDir.appendingPathComponent("file-not-directory")
        try "x".write(to: blockedPath, atomically: true, encoding: .utf8)

        let store = ToolContextStore(baseURL: blockedPath)
        await store.record(ToolUsageEvent(
            toolName: "agent.list",
            category: "agent",
            decision: .allowed,
            latencyMs: 10,
            agentName: "코디",
            workspaceId: "ws-1",
            timestamp: Date()
        ))
        await store.flushToDisk()

        // Save may fail on disk, but the in-memory profile should still be available.
        let profile = await store.profile(workspaceId: "ws-1", agentName: "코디")
        XCTAssertNotNil(profile)
    }
}
