import XCTest
@testable import Dochi

// MARK: - Mock MCP Service for Profile Tests

@MainActor
private final class MockMCPServiceForProfileTests: MCPServiceProtocol {
    var servers: [UUID: MCPServerConfig] = [:]
    var connectedServerIds: Set<UUID> = []
    var connectCallCount = 0
    var connectError: Error?

    func addServer(config: MCPServerConfig) {
        servers[config.id] = config
    }

    func removeServer(id: UUID) {
        servers.removeValue(forKey: id)
        connectedServerIds.remove(id)
    }

    func connect(serverId: UUID) async throws {
        connectCallCount += 1
        if let connectError { throw connectError }
        connectedServerIds.insert(serverId)
    }

    func disconnect(serverId: UUID) {
        connectedServerIds.remove(serverId)
    }

    func disconnectAll() {
        connectedServerIds.removeAll()
    }

    func updateServer(config: MCPServerConfig) async throws {
        servers[config.id] = config
    }

    func listServers() -> [MCPServerConfig] {
        Array(servers.values).sorted { $0.name < $1.name }
    }

    func getServer(id: UUID) -> MCPServerConfig? {
        servers[id]
    }

    func listTools() -> [MCPToolInfo] { [] }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        MCPToolResult(content: "ok", isError: false)
    }

    func activateProfile(_ profile: MCPServerProfile) async {
        for server in profile.servers {
            addServer(config: server)
            if server.isEnabled {
                try? await connect(serverId: server.id)
            }
        }
    }

    func deactivateProfile(_ profile: MCPServerProfile) {
        for server in profile.servers {
            removeServer(id: server.id)
        }
    }

    func serverStatus(for serverId: UUID) -> MCPServerStatus {
        if connectedServerIds.contains(serverId) { return .connected }
        return .disconnected
    }

    func healthReport(for profile: MCPServerProfile) -> MCPProfileHealthReport {
        let statuses = profile.servers.map { server in
            (serverName: server.name, status: serverStatus(for: server.id))
        }
        return MCPProfileHealthReport(profileName: profile.displayName, serverStatuses: statuses)
    }

    func fallbackMessage(for toolName: String) -> String {
        "MCP 서버가 현재 비가용 상태입니다. 잠시 후 다시 시도해 주세요."
    }
}

// MARK: - MCPServerProfile Model Tests

final class MCPServerProfileModelTests: XCTestCase {

    func testCodingProfileCreatesThreeServers() {
        let profile = MCPServerProfile.coding()
        XCTAssertEqual(profile.servers.count, 3)
        XCTAssertEqual(profile.name, "coding")
        XCTAssertEqual(profile.displayName, "코딩")
        XCTAssertTrue(profile.isEnabled)
        XCTAssertTrue(profile.autoRestart)
    }

    func testCodingProfileContainsExpectedServerNames() {
        let profile = MCPServerProfile.coding()
        let names = Set(profile.servers.map(\.name))
        XCTAssertTrue(names.contains("coding-filesystem"))
        XCTAssertTrue(names.contains("coding-git"))
        XCTAssertTrue(names.contains("coding-shell"))
    }

    func testProfileIsBuiltInForCoding() {
        let profile = MCPServerProfile.coding()
        XCTAssertTrue(profile.isBuiltIn)
    }

    func testProfileIsNotBuiltInForCustom() {
        let profile = MCPServerProfile(name: "custom-profile")
        XCTAssertFalse(profile.isBuiltIn)
    }

    func testServerNamedFindsCorrectServer() {
        let profile = MCPServerProfile.coding()
        let git = profile.server(named: "coding-git")
        XCTAssertNotNil(git)
        XCTAssertEqual(git?.name, "coding-git")
    }

    func testServerNamedReturnsNilForUnknown() {
        let profile = MCPServerProfile.coding()
        XCTAssertNil(profile.server(named: "nonexistent"))
    }

    func testWithUpdatedServerReplacesById() {
        let profile = MCPServerProfile.coding()
        guard let git = profile.server(named: "coding-git") else {
            return XCTFail("coding-git not found")
        }
        let updated = git.withUpdatedRepoPath("/new/repo")
        let newProfile = profile.withUpdatedServer(updated)

        XCTAssertEqual(newProfile.server(named: "coding-git")?.codingGitRepoPath, "/new/repo")
        XCTAssertEqual(newProfile.servers.count, profile.servers.count)
    }

    func testWithUpdatedServerNoOpForUnknownId() {
        let profile = MCPServerProfile.coding()
        let unknown = MCPServerConfig(name: "unknown", command: "echo")
        let newProfile = profile.withUpdatedServer(unknown)
        XCTAssertEqual(newProfile.servers.count, profile.servers.count)
    }

    func testDefaultInitValues() {
        let profile = MCPServerProfile(name: "test")
        XCTAssertEqual(profile.displayName, "test")
        XCTAssertEqual(profile.maxRestartAttempts, 3)
        XCTAssertEqual(profile.healthCheckIntervalSeconds, 8)
        XCTAssertTrue(profile.autoRestart)
        XCTAssertTrue(profile.isEnabled)
    }

    func testDisplayNameDefaultsToName() {
        let profile = MCPServerProfile(name: "my-profile")
        XCTAssertEqual(profile.displayName, "my-profile")
    }

    func testDisplayNameOverride() {
        let profile = MCPServerProfile(name: "my-profile", displayName: "My Profile")
        XCTAssertEqual(profile.displayName, "My Profile")
    }

    func testCodableRoundTrip() throws {
        let original = MCPServerProfile.coding()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(MCPServerProfile.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.displayName, original.displayName)
        XCTAssertEqual(decoded.isEnabled, original.isEnabled)
        XCTAssertEqual(decoded.autoRestart, original.autoRestart)
        XCTAssertEqual(decoded.maxRestartAttempts, original.maxRestartAttempts)
        XCTAssertEqual(decoded.healthCheckIntervalSeconds, original.healthCheckIntervalSeconds)
        XCTAssertEqual(decoded.servers.count, original.servers.count)
    }
}

// MARK: - MCPServerStatus Tests

final class MCPServerStatusTests: XCTestCase {

    func testConnectedIsAvailable() {
        XCTAssertTrue(MCPServerStatus.connected.isAvailable)
    }

    func testDisconnectedIsNotAvailable() {
        XCTAssertFalse(MCPServerStatus.disconnected.isAvailable)
    }

    func testErrorIsNotAvailable() {
        XCTAssertFalse(MCPServerStatus.error("test").isAvailable)
    }

    func testRestartingIsNotAvailable() {
        XCTAssertFalse(MCPServerStatus.restarting.isAvailable)
    }

    func testLocalizedDescriptions() {
        XCTAssertEqual(MCPServerStatus.connected.localizedDescription, "연결됨")
        XCTAssertEqual(MCPServerStatus.disconnected.localizedDescription, "연결 해제")
        XCTAssertEqual(MCPServerStatus.restarting.localizedDescription, "재시작 중")
        XCTAssertTrue(MCPServerStatus.error("timeout").localizedDescription.contains("timeout"))
    }
}

// MARK: - MCPProfileHealthReport Tests

final class MCPProfileHealthReportTests: XCTestCase {

    func testAllHealthyWhenAllConnected() {
        let report = MCPProfileHealthReport(
            profileName: "test",
            serverStatuses: [
                ("a", .connected),
                ("b", .connected),
            ]
        )
        XCTAssertTrue(report.allHealthy)
        XCTAssertEqual(report.healthyCount, 2)
        XCTAssertTrue(report.unhealthyServerNames.isEmpty)
    }

    func testNotAllHealthyWhenSomeDisconnected() {
        let report = MCPProfileHealthReport(
            profileName: "test",
            serverStatuses: [
                ("a", .connected),
                ("b", .disconnected),
                ("c", .error("fail")),
            ]
        )
        XCTAssertFalse(report.allHealthy)
        XCTAssertEqual(report.healthyCount, 1)
        XCTAssertEqual(Set(report.unhealthyServerNames), Set(["b", "c"]))
    }

    func testLocalizedSummaryAllHealthy() {
        let report = MCPProfileHealthReport(
            profileName: "코딩",
            serverStatuses: [
                ("a", .connected),
            ]
        )
        XCTAssertTrue(report.localizedSummary.contains("모든 서버 정상"))
    }

    func testLocalizedSummaryPartialHealth() {
        let report = MCPProfileHealthReport(
            profileName: "코딩",
            serverStatuses: [
                ("a", .connected),
                ("b", .disconnected),
            ]
        )
        XCTAssertTrue(report.localizedSummary.contains("1/2"))
        XCTAssertTrue(report.localizedSummary.contains("비정상"))
    }
}

// MARK: - MCPRestartTracker Tests

final class MCPRestartTrackerTests: XCTestCase {

    func testInitialStateCanRestart() {
        let tracker = MCPRestartTracker(maxAttempts: 3)
        XCTAssertTrue(tracker.canRestart)
        XCTAssertEqual(tracker.attempts, 0)
    }

    func testRecordAttemptIncrementsCount() {
        var tracker = MCPRestartTracker(maxAttempts: 3)
        tracker.recordAttempt()
        XCTAssertEqual(tracker.attempts, 1)
        XCTAssertTrue(tracker.canRestart)
    }

    func testCannotRestartAfterMaxAttempts() {
        var tracker = MCPRestartTracker(maxAttempts: 2)
        tracker.recordAttempt()
        tracker.recordAttempt()
        XCTAssertFalse(tracker.canRestart)
    }

    func testResetClearsAttempts() {
        var tracker = MCPRestartTracker(maxAttempts: 2)
        tracker.recordAttempt()
        tracker.recordAttempt()
        tracker.reset()
        XCTAssertTrue(tracker.canRestart)
        XCTAssertEqual(tracker.attempts, 0)
    }

    func testMaxAttemptsMinimumIsOne() {
        let tracker = MCPRestartTracker(maxAttempts: 0)
        XCTAssertEqual(tracker.maxAttempts, 1)
    }
}

// MARK: - MCPServiceError Tests

final class MCPServiceErrorTests: XCTestCase {

    func testServerUnavailableErrorDescription() {
        let error = MCPServiceError.serverUnavailable(serverName: "coding-shell", toolName: "execute")
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("coding-shell"))
        XCTAssertTrue(desc.contains("execute"))
        XCTAssertTrue(desc.contains("사용 불가"))
    }

    func testExistingErrorCasesUnchanged() {
        XCTAssertEqual(
            MCPServiceError.serverNotFound.errorDescription,
            "MCP 서버를 찾을 수 없습니다."
        )
        XCTAssertEqual(
            MCPServiceError.notConnected.errorDescription,
            "MCP 서버에 연결되어 있지 않습니다."
        )
        XCTAssertEqual(
            MCPServiceError.toolNotFound.errorDescription,
            "MCP 도구를 찾을 수 없습니다."
        )
    }
}

// MARK: - Profile Lifecycle Integration Tests

@MainActor
final class MCPProfileLifecycleTests: XCTestCase {

    func testActivateProfileAddsAllServers() async {
        let mcpService = MockMCPServiceForProfileTests()
        let profile = MCPServerProfile.coding()

        await mcpService.activateProfile(profile)

        XCTAssertEqual(mcpService.listServers().count, 3)
    }

    func testActivateProfileConnectsEnabledServers() async {
        let mcpService = MockMCPServiceForProfileTests()
        let profile = MCPServerProfile.coding()

        await mcpService.activateProfile(profile)

        let enabledCount = profile.servers.filter(\.isEnabled).count
        XCTAssertEqual(mcpService.connectedServerIds.count, enabledCount)
    }

    func testDeactivateProfileRemovesAllServers() async {
        let mcpService = MockMCPServiceForProfileTests()
        let profile = MCPServerProfile.coding()

        await mcpService.activateProfile(profile)
        mcpService.deactivateProfile(profile)

        XCTAssertTrue(mcpService.listServers().isEmpty)
        XCTAssertTrue(mcpService.connectedServerIds.isEmpty)
    }

    func testHealthReportReflectsConnectionState() async {
        let mcpService = MockMCPServiceForProfileTests()
        let profile = MCPServerProfile.coding()

        await mcpService.activateProfile(profile)

        let report = mcpService.healthReport(for: profile)
        XCTAssertEqual(report.profileName, "코딩")
        XCTAssertEqual(report.serverStatuses.count, 3)

        let enabledCount = profile.servers.filter(\.isEnabled).count
        XCTAssertEqual(report.healthyCount, enabledCount)
    }

    func testFallbackMessageContainsSuggestion() {
        let mcpService = MockMCPServiceForProfileTests()
        let message = mcpService.fallbackMessage(for: "shell_execute")
        XCTAssertTrue(message.contains("비가용"))
    }

    func testServerStatusForUnknownServerIsDisconnected() {
        let mcpService = MockMCPServiceForProfileTests()
        XCTAssertEqual(mcpService.serverStatus(for: UUID()), .disconnected)
    }
}
