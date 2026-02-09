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
    
    func testCreateAndLoadWorkspace() {
        // Given
        let workspace = Workspace(id: UUID(), name: "Test Workspace", ownerId: UUID(), createdAt: Date())
        
        // When
        sut.saveWorkspaceConfig(workspace)
        
        // Then
        let loaded = sut.loadWorkspaceConfig(id: workspace.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.name, "Test Workspace")
    }
    
    // MARK: - Workspace Memory
    
    func testWorkspaceMemory() {
        // Given
        let wsId = UUID()
        
        // When
        sut.saveWorkspaceMemory(workspaceId: wsId, content: "Shared Memory")
        
        // Then
        XCTAssertEqual(sut.loadWorkspaceMemory(workspaceId: wsId), "Shared Memory")
    }
    
    func testAppendWorkspaceMemory() {
        // Given
        let wsId = UUID()
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
        let wsId = UUID()
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
        let ws1Id = UUID()
        let ws2Id = UUID()
        let agentName = "Agent"
        
        // When
        sut.createAgent(workspaceId: ws1Id, name: agentName, wakeWord: "Hey", description: "Desc")
        sut.saveAgentMemory(workspaceId: ws1Id, agentName: agentName, content: "WS1 Memory")
        
        sut.createAgent(workspaceId: ws2Id, name: agentName, wakeWord: "Hi", description: "Desc")
        sut.saveAgentMemory(workspaceId: ws2Id, agentName: agentName, content: "WS2 Memory")
        
        // Then
        XCTAssertEqual(sut.loadAgentMemory(workspaceId: ws1Id, agentName: agentName), "WS1 Memory")
        XCTAssertEqual(sut.loadAgentMemory(workspaceId: ws2Id, agentName: agentName), "WS2 Memory")
    }
}
