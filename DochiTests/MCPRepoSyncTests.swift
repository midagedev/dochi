import XCTest
@testable import Dochi

// MARK: - Mock MCP Service for Repo Sync Tests

@MainActor
private final class MockMCPServiceForRepoSync: MCPServiceProtocol {
    var servers: [UUID: MCPServerConfig] = [:]
    var updateServerCallCount = 0
    var lastUpdatedConfig: MCPServerConfig?
    var updateServerError: Error?

    func addServer(config: MCPServerConfig) {
        servers[config.id] = config
    }

    func removeServer(id: UUID) {
        servers.removeValue(forKey: id)
    }

    func connect(serverId: UUID) async throws {}
    func disconnect(serverId: UUID) {}
    func disconnectAll() {}

    func updateServer(config: MCPServerConfig) async throws {
        updateServerCallCount += 1
        lastUpdatedConfig = config
        if let error = updateServerError {
            throw error
        }
        servers.removeValue(forKey: config.id)
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

    func activateProfile(_ profile: MCPServerProfile) async {}
    func deactivateProfile(_ profile: MCPServerProfile) {}
    func serverStatus(for serverId: UUID) -> MCPServerStatus { .disconnected }
    func healthReport(for profile: MCPServerProfile) -> MCPProfileHealthReport {
        MCPProfileHealthReport(profileName: profile.displayName, serverStatuses: [])
    }
    func fallbackMessage(for toolName: String) -> String { "" }
}

// MARK: - MCPServerConfig Helpers Tests

final class MCPServerConfigRepoHelperTests: XCTestCase {

    func testIsCodingGitProfileReturnsTrueForCodingGit() {
        let config = MCPServerConfig(
            name: "coding-git",
            command: "uvx",
            arguments: ["mcp-server-git", "--repository", "/tmp/repo"]
        )
        XCTAssertTrue(config.isCodingGitProfile)
    }

    func testIsCodingGitProfileReturnsFalseForOtherProfiles() {
        let config = MCPServerConfig(
            name: "coding-filesystem",
            command: "npx",
            arguments: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
        )
        XCTAssertFalse(config.isCodingGitProfile)
    }

    func testCodingGitRepoPathExtractsRepositoryArgument() {
        let config = MCPServerConfig(
            name: "coding-git",
            command: "uvx",
            arguments: ["mcp-server-git", "--repository", "/Users/test/project"]
        )
        XCTAssertEqual(config.codingGitRepoPath, "/Users/test/project")
    }

    func testCodingGitRepoPathReturnsNilWhenMissingRepositoryFlag() {
        let config = MCPServerConfig(
            name: "coding-git",
            command: "uvx",
            arguments: ["mcp-server-git"]
        )
        XCTAssertNil(config.codingGitRepoPath)
    }

    func testCodingGitRepoPathReturnsNilForNonGitProfile() {
        let config = MCPServerConfig(
            name: "coding-filesystem",
            command: "npx",
            arguments: ["--repository", "/tmp"]
        )
        XCTAssertNil(config.codingGitRepoPath)
    }

    func testCodingGitRepoPathReturnsNilWhenRepositoryValueIsEmpty() {
        let config = MCPServerConfig(
            name: "coding-git",
            command: "uvx",
            arguments: ["mcp-server-git", "--repository", ""]
        )
        XCTAssertNil(config.codingGitRepoPath)
    }

    func testWithUpdatedRepoPathReplacesExistingRepository() {
        let config = MCPServerConfig(
            name: "coding-git",
            command: "uvx",
            arguments: ["mcp-server-git", "--repository", "/old/path"],
            isEnabled: false
        )

        let updated = config.withUpdatedRepoPath("/new/path")
        XCTAssertEqual(updated.codingGitRepoPath, "/new/path")
        XCTAssertTrue(updated.isEnabled, "Should enable the profile when updating repo path")
        XCTAssertEqual(updated.id, config.id, "Should preserve ID")
        XCTAssertEqual(updated.name, "coding-git")
        XCTAssertEqual(updated.command, "uvx")
    }

    func testWithUpdatedRepoPathAppendsWhenRepositoryFlagMissing() {
        let config = MCPServerConfig(
            name: "coding-git",
            command: "uvx",
            arguments: ["mcp-server-git"],
            isEnabled: false
        )

        let updated = config.withUpdatedRepoPath("/some/repo")
        XCTAssertEqual(updated.codingGitRepoPath, "/some/repo")
        XCTAssertTrue(updated.arguments.contains("--repository"))
        XCTAssertTrue(updated.isEnabled)
    }

    func testWithUpdatedRepoPathIgnoresEmptyPath() {
        let config = MCPServerConfig(
            name: "coding-git",
            command: "uvx",
            arguments: ["mcp-server-git", "--repository", "/old/path"],
            isEnabled: false
        )

        let updated = config.withUpdatedRepoPath("  ")
        XCTAssertEqual(updated.codingGitRepoPath, "/old/path", "Should not change when path is empty")
        XCTAssertFalse(updated.isEnabled, "Should not enable when path is empty")
    }

    func testIsValidGitRepositoryReturnsTrueForGitRepo() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let gitDir = tempDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        XCTAssertTrue(MCPServerConfig.isValidGitRepository(at: tempDir.path))
    }

    func testIsValidGitRepositoryReturnsFalseForNonGitDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        XCTAssertFalse(MCPServerConfig.isValidGitRepository(at: tempDir.path))
    }

    func testIsValidGitRepositoryReturnsFalseForNonExistentPath() {
        XCTAssertFalse(MCPServerConfig.isValidGitRepository(at: "/nonexistent/path/\(UUID().uuidString)"))
    }

    func testIsValidGitRepositoryReturnsFalseForEmptyPath() {
        XCTAssertFalse(MCPServerConfig.isValidGitRepository(at: ""))
    }
}

// MARK: - MCPRepoSyncService Tests

@MainActor
final class MCPRepoSyncServiceTests: XCTestCase {

    private var mockMCPService: MockMCPServiceForRepoSync!
    private var settings: AppSettings!
    private var syncService: MCPRepoSyncService!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        mockMCPService = MockMCPServiceForRepoSync()
        settings = AppSettings()
        syncService = MCPRepoSyncService(mcpService: mockMCPService, settings: settings)

        // Create a temp git repo for valid path tests
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("dochi-test-\(UUID().uuidString)")
        let gitDir = tempDir.appendingPathComponent(".git")
        try? FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    func testSyncRepoPathUpdatesProfileSuccessfully() async {
        let gitConfig = MCPServerConfig(
            name: "coding-git",
            command: "uvx",
            arguments: ["mcp-server-git", "--repository", "/old/path"],
            isEnabled: false
        )
        mockMCPService.addServer(config: gitConfig)

        let result = await syncService.syncRepoPath(tempDir.path)

        guard case .updated(let oldPath, let newPath) = result else {
            return XCTFail("Expected .updated, got \(result)")
        }
        XCTAssertEqual(oldPath, "/old/path")
        XCTAssertEqual(newPath, tempDir.path)
        XCTAssertEqual(mockMCPService.updateServerCallCount, 1)

        // Verify the updated config
        let updated = mockMCPService.lastUpdatedConfig
        XCTAssertEqual(updated?.codingGitRepoPath, tempDir.path)
        XCTAssertTrue(updated?.isEnabled ?? false)
    }

    func testSyncRepoPathReturnsAlreadyInSyncWhenPathMatches() async {
        let gitConfig = MCPServerConfig(
            name: "coding-git",
            command: "uvx",
            arguments: ["mcp-server-git", "--repository", tempDir.path],
            isEnabled: true
        )
        mockMCPService.addServer(config: gitConfig)

        let result = await syncService.syncRepoPath(tempDir.path)
        XCTAssertEqual(result, .alreadyInSync)
        XCTAssertEqual(mockMCPService.updateServerCallCount, 0)
    }

    func testSyncRepoPathReturnsInvalidPathForNonGitDirectory() async {
        let nonGitDir = FileManager.default.temporaryDirectory.appendingPathComponent("dochi-nongit-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: nonGitDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: nonGitDir) }

        let gitConfig = MCPServerConfig(
            name: "coding-git",
            command: "uvx",
            arguments: ["mcp-server-git", "--repository", "/old"]
        )
        mockMCPService.addServer(config: gitConfig)

        let result = await syncService.syncRepoPath(nonGitDir.path)
        guard case .invalidPath = result else {
            return XCTFail("Expected .invalidPath, got \(result)")
        }
        XCTAssertEqual(mockMCPService.updateServerCallCount, 0)
    }

    func testSyncRepoPathReturnsInvalidPathForEmptyString() async {
        let result = await syncService.syncRepoPath("")
        guard case .invalidPath = result else {
            return XCTFail("Expected .invalidPath, got \(result)")
        }
    }

    func testSyncRepoPathReturnsProfileNotFoundWhenNoCodingGitExists() async {
        // No coding-git profile added
        let filesystemConfig = MCPServerConfig(
            name: "coding-filesystem",
            command: "npx",
            arguments: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
        )
        mockMCPService.addServer(config: filesystemConfig)

        let result = await syncService.syncRepoPath(tempDir.path)
        XCTAssertEqual(result, .profileNotFound)
    }

    func testSyncRepoPathUpdatesEvenWhenProfileIsDisabledButPathDiffers() async {
        let gitConfig = MCPServerConfig(
            name: "coding-git",
            command: "uvx",
            arguments: ["mcp-server-git", "--repository", "/different/path"],
            isEnabled: false
        )
        mockMCPService.addServer(config: gitConfig)

        let result = await syncService.syncRepoPath(tempDir.path)
        guard case .updated = result else {
            return XCTFail("Expected .updated, got \(result)")
        }

        let updated = mockMCPService.lastUpdatedConfig
        XCTAssertTrue(updated?.isEnabled ?? false, "Should enable the profile after sync")
    }

    func testSyncFromSessionContextSyncsWhenRepoPathIsSet() async {
        let gitConfig = MCPServerConfig(
            name: "coding-git",
            command: "uvx",
            arguments: ["mcp-server-git", "--repository", "/old"],
            isEnabled: false
        )
        mockMCPService.addServer(config: gitConfig)

        let context = SessionContext(workspaceId: UUID(), currentRepoPath: tempDir.path)
        let result = await syncService.syncFromSessionContext(context)

        guard case .updated = result else {
            return XCTFail("Expected .updated, got \(String(describing: result))")
        }
    }

    func testSyncFromSessionContextReturnsNilWhenRepoPathIsNil() async {
        let context = SessionContext(workspaceId: UUID(), currentRepoPath: nil)
        let result = await syncService.syncFromSessionContext(context)
        XCTAssertNil(result)
    }

    func testCurrentCodingGitRepoPathReturnsCurrentPath() {
        let gitConfig = MCPServerConfig(
            name: "coding-git",
            command: "uvx",
            arguments: ["mcp-server-git", "--repository", "/some/repo"]
        )
        mockMCPService.addServer(config: gitConfig)

        XCTAssertEqual(syncService.currentCodingGitRepoPath, "/some/repo")
    }

    func testIsCodingGitEnabledReflectsProfileState() {
        let disabledGit = MCPServerConfig(
            name: "coding-git",
            command: "uvx",
            arguments: ["mcp-server-git"],
            isEnabled: false
        )
        mockMCPService.addServer(config: disabledGit)

        XCTAssertFalse(syncService.isCodingGitEnabled)
    }
}

// MARK: - SessionContext Repo Path Callback Tests

@MainActor
final class SessionContextRepoPathTests: XCTestCase {

    func testOnRepoPathChangedCalledWhenPathChanges() async {
        let context = SessionContext(workspaceId: UUID())
        let expectation = XCTestExpectation(description: "onRepoPathChanged called")
        var receivedPath: String?

        context.onRepoPathChanged = { newPath in
            receivedPath = newPath
            expectation.fulfill()
        }

        context.currentRepoPath = "/new/repo"

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(receivedPath, "/new/repo")
    }

    func testOnRepoPathChangedNotCalledWhenSetToSameValue() async {
        let context = SessionContext(workspaceId: UUID(), currentRepoPath: "/same/path")
        var callCount = 0

        context.onRepoPathChanged = { _ in
            callCount += 1
        }

        context.currentRepoPath = "/same/path"

        // Give a brief moment for any async task to fire
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(callCount, 0, "Should not fire when value doesn't change")
    }

    func testOnRepoPathChangedNotCalledWhenSetToNil() async {
        let context = SessionContext(workspaceId: UUID(), currentRepoPath: "/old/path")
        var callCount = 0

        context.onRepoPathChanged = { _ in
            callCount += 1
        }

        context.currentRepoPath = nil

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(callCount, 0, "Should not fire when set to nil")
    }
}
