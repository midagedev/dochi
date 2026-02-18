import XCTest
@testable import Dochi

@MainActor
final class ContextServiceTests: XCTestCase {
    private var service: ContextService!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DochiTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        service = ContextService(baseURL: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Base System Prompt

    func testSaveAndLoadBaseSystemPrompt() {
        XCTAssertNil(service.loadBaseSystemPrompt())

        service.saveBaseSystemPrompt("You are Dochi.")
        XCTAssertEqual(service.loadBaseSystemPrompt(), "You are Dochi.")

        service.saveBaseSystemPrompt("Updated prompt")
        XCTAssertEqual(service.loadBaseSystemPrompt(), "Updated prompt")
    }

    // MARK: - Profiles

    func testSaveAndLoadProfiles() {
        let profiles = service.loadProfiles()
        XCTAssertTrue(profiles.isEmpty)

        let profile = UserProfile(name: "테스트", aliases: ["test"], description: "테스트 유저")
        service.saveProfiles([profile])

        let loaded = service.loadProfiles()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].name, "테스트")
        XCTAssertEqual(loaded[0].aliases, ["test"])
        XCTAssertEqual(loaded[0].description, "테스트 유저")
    }

    func testMultipleProfiles() {
        let p1 = UserProfile(name: "유저1")
        let p2 = UserProfile(name: "유저2")
        service.saveProfiles([p1, p2])

        let loaded = service.loadProfiles()
        XCTAssertEqual(loaded.count, 2)
    }

    // MARK: - User Memory

    func testSaveAndLoadUserMemory() {
        XCTAssertNil(service.loadUserMemory(userId: "user1"))

        service.saveUserMemory(userId: "user1", content: "likes coffee")
        XCTAssertEqual(service.loadUserMemory(userId: "user1"), "likes coffee")
    }

    func testAppendUserMemory() {
        service.saveUserMemory(userId: "user1", content: "fact1")
        service.appendUserMemory(userId: "user1", content: "fact2")

        let memory = service.loadUserMemory(userId: "user1")
        XCTAssertNotNil(memory)
        XCTAssertTrue(memory!.contains("fact1"))
        XCTAssertTrue(memory!.contains("fact2"))
    }

    func testAppendUserMemoryWhenEmpty() {
        service.appendUserMemory(userId: "newuser", content: "first fact")
        let memory = service.loadUserMemory(userId: "newuser")
        XCTAssertNotNil(memory)
        XCTAssertTrue(memory!.contains("first fact"))
    }

    // MARK: - Workspace Memory

    func testSaveAndLoadWorkspaceMemory() {
        let wsId = UUID()
        XCTAssertNil(service.loadWorkspaceMemory(workspaceId: wsId))

        service.saveWorkspaceMemory(workspaceId: wsId, content: "workspace note")
        XCTAssertEqual(service.loadWorkspaceMemory(workspaceId: wsId), "workspace note")
    }

    func testAppendWorkspaceMemory() {
        let wsId = UUID()
        service.saveWorkspaceMemory(workspaceId: wsId, content: "note1")
        service.appendWorkspaceMemory(workspaceId: wsId, content: "note2")

        let memory = service.loadWorkspaceMemory(workspaceId: wsId)
        XCTAssertNotNil(memory)
        XCTAssertTrue(memory!.contains("note1"))
        XCTAssertTrue(memory!.contains("note2"))
    }

    // MARK: - Agent

    func testSaveAndLoadAgentConfig() {
        let wsId = UUID()
        XCTAssertNil(service.loadAgentConfig(workspaceId: wsId, agentName: "도치"))

        let config = AgentConfig(name: "도치", wakeWord: "도치야", description: "AI 비서")
        service.saveAgentConfig(workspaceId: wsId, config: config)

        let loaded = service.loadAgentConfig(workspaceId: wsId, agentName: "도치")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.name, "도치")
        XCTAssertEqual(loaded?.wakeWord, "도치야")
        XCTAssertEqual(loaded?.description, "AI 비서")
    }

    func testCreateAgent() {
        let wsId = UUID()
        service.createAgent(workspaceId: wsId, name: "도치", wakeWord: "도치야", description: "비서")

        let config = service.loadAgentConfig(workspaceId: wsId, agentName: "도치")
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.name, "도치")

        let agents = service.listAgents(workspaceId: wsId)
        XCTAssertTrue(agents.contains("도치"))
    }

    func testAgentPersona() {
        let wsId = UUID()
        service.createAgent(workspaceId: wsId, name: "도치", wakeWord: nil, description: nil)

        XCTAssertNil(service.loadAgentPersona(workspaceId: wsId, agentName: "도치"))

        service.saveAgentPersona(workspaceId: wsId, agentName: "도치", content: "You are a hedgehog.")
        XCTAssertEqual(service.loadAgentPersona(workspaceId: wsId, agentName: "도치"), "You are a hedgehog.")
    }

    func testAgentMemory() {
        let wsId = UUID()
        service.createAgent(workspaceId: wsId, name: "도치", wakeWord: nil, description: nil)

        XCTAssertNil(service.loadAgentMemory(workspaceId: wsId, agentName: "도치"))

        service.saveAgentMemory(workspaceId: wsId, agentName: "도치", content: "memory1")
        service.appendAgentMemory(workspaceId: wsId, agentName: "도치", content: "memory2")

        let memory = service.loadAgentMemory(workspaceId: wsId, agentName: "도치")
        XCTAssertNotNil(memory)
        XCTAssertTrue(memory!.contains("memory1"))
        XCTAssertTrue(memory!.contains("memory2"))
    }

    // MARK: - Isolation between users/workspaces

    func testUserMemoryIsolation() {
        service.saveUserMemory(userId: "alice", content: "alice data")
        service.saveUserMemory(userId: "bob", content: "bob data")

        XCTAssertEqual(service.loadUserMemory(userId: "alice"), "alice data")
        XCTAssertEqual(service.loadUserMemory(userId: "bob"), "bob data")
    }

    // MARK: - Project context

    func testRegisterAndLoadProject() {
        let wsId = UUID()
        let project = service.registerProject(
            workspaceId: wsId,
            repoRootPath: "~/repo/dochi",
            defaultBranch: "main"
        )

        let loaded = service.loadProject(workspaceId: wsId, projectId: project.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, project.id)
        XCTAssertEqual(loaded?.defaultBranch, "main")
        XCTAssertTrue(loaded?.repoRootPath.hasSuffix("/repo/dochi") == true)
    }

    func testListProjectsSortedByName() {
        let wsId = UUID()
        let p1 = ProjectContext(repoRootPath: "/tmp/zeta-repo", displayName: "Zeta")
        let p2 = ProjectContext(repoRootPath: "/tmp/alpha-repo", displayName: "Alpha")
        service.saveProject(workspaceId: wsId, project: p1)
        service.saveProject(workspaceId: wsId, project: p2)

        let listed = service.listProjects(workspaceId: wsId)
        XCTAssertEqual(listed.map(\.displayName), ["Alpha", "Zeta"])
    }

    func testProjectMemorySaveAndAppend() {
        let wsId = UUID()
        let project = ProjectContext(repoRootPath: "/tmp/my-repo")
        service.saveProject(workspaceId: wsId, project: project)

        service.saveProjectMemory(workspaceId: wsId, projectId: project.id, content: "rule1")
        service.appendProjectMemory(workspaceId: wsId, projectId: project.id, content: "rule2")

        let memory = service.loadProjectMemory(workspaceId: wsId, projectId: project.id)
        XCTAssertNotNil(memory)
        XCTAssertTrue(memory?.contains("rule1") == true)
        XCTAssertTrue(memory?.contains("rule2") == true)
    }
}
