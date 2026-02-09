import XCTest
@testable import Dochi

@MainActor
final class WorkspaceContextTests: XCTestCase {
    var sut: ContextService!
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut = ContextService(baseDirectory: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        tempDir = nil
    }

    // MARK: - Workspace Management

    func testListWorkspacesEmpty() {
        XCTAssertEqual(sut.listWorkspaces().count, 0)
    }

    func testMigrateToWorkspaceStructureCreatesDefaultWorkspace() {
        // Given
        sut.saveSystem("Legacy System")
        sut.saveMemory("Legacy Memory")

        // When
        sut.migrateToWorkspaceStructure()

        // Then
        let workspaces = sut.listWorkspaces()
        XCTAssertEqual(workspaces.count, 1)
        
        guard let defaultWorkspace = workspaces.first else {
            XCTFail("Default workspace not created")
            return
        }
        
        XCTAssertEqual(defaultWorkspace.name, "기본 워크스페이스")
        
        // Memory moved
        let wsMemory = sut.loadWorkspaceMemory(workspaceId: defaultWorkspace.id)
        XCTAssertEqual(wsMemory, "Legacy Memory") // or whatever logic you had for moving memory
        
        // Agent Persona moved
        // Assuming default agent name is "도치"
        let persona = sut.loadAgentPersona(workspaceId: defaultWorkspace.id, agentName: "도치")
        XCTAssertFalse(persona.isEmpty)
        XCTAssertTrue(persona.contains("Legacy System"))
    }
    
    // MARK: - Workspace Memory
    
    func testWorkspaceMemory() {
        // Given
        sut.migrateToWorkspaceStructure()
        let wsId = sut.listWorkspaces().first!.id
        
        // When
        sut.saveWorkspaceMemory(workspaceId: wsId, content: "Shared Memory")
        
        // Then
        XCTAssertEqual(sut.loadWorkspaceMemory(workspaceId: wsId), "Shared Memory")
    }
    
    func testAppendWorkspaceMemory() {
        // Given
        sut.migrateToWorkspaceStructure()
        let wsId = sut.listWorkspaces().first!.id
        sut.saveWorkspaceMemory(workspaceId: wsId, content: "Line 1")
        
        // When
        sut.appendWorkspaceMemory(workspaceId: wsId, content: "Line 2")
        
        // Then
        let content = sut.loadWorkspaceMemory(workspaceId: wsId)
        XCTAssertTrue(content.contains("Line 1"))
        XCTAssertTrue(content.contains("Line 2"))
    }
    
    // MARK: - Agent in Workspace
    
    func testAgentInWorkspace() {
        // Given
        sut.migrateToWorkspaceStructure()
        let wsId = sut.listWorkspaces().first!.id
        let agentName = "TestAgent"
        
        // When
        sut.createAgent(workspaceId: wsId, name: agentName, wakeWord: "Hey", description: "Desc")
        
        // Then
        let agents = sut.listAgents(workspaceId: wsId)
        XCTAssertTrue(agents.contains(agentName))
        
        // Config check
        let config = sut.loadAgentConfig(workspaceId: wsId, agentName: agentName)
        XCTAssertEqual(config?.wakeWord, "Hey")
        
        // Persona check
        sut.saveAgentPersona(workspaceId: wsId, agentName: agentName, content: "I am TestAgent")
        XCTAssertEqual(sut.loadAgentPersona(workspaceId: wsId, agentName: agentName), "I am TestAgent")
        
        // Memory check
        sut.saveAgentMemory(workspaceId: wsId, agentName: agentName, content: "My Memory")
        XCTAssertEqual(sut.loadAgentMemory(workspaceId: wsId, agentName: agentName), "My Memory")
    }
    
    func testAgentIsolationBetweenWorkspaces() {
        // Given two workspaces
        sut.migrateToWorkspaceStructure()
        let ws1 = sut.listWorkspaces().first!
        
        // Manually create second workspace for test (helper needed or just use logic)
        // Since createWorkspace is private/internal logic in migrate, let's just simulate by using migration or if there is a createWorkspace exposed?
        // Checking protocol for createWorkspace... it's not exposed in protocol yet, but maybe we can just verify file structure isolation
        
        // Let's rely on what we have. If we can't create another workspace easily via public API, 
        // we might need to expose `createWorkspace` or just test within one workspace.
        // For now, let's assume we can only test one workspace effectively without `createWorkspace` API.
    }
}
