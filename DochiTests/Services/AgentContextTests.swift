import XCTest
@testable import Dochi

@MainActor
final class AgentContextTests: XCTestCase {
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

    // MARK: - Base System Prompt

    func testSaveAndLoadBaseSystemPrompt() {
        let content = "기본 규칙 내용"
        sut.saveBaseSystemPrompt(content)
        XCTAssertEqual(sut.loadBaseSystemPrompt(), content)
    }

    func testLoadBaseSystemPromptReturnsEmptyWhenNoFile() {
        XCTAssertEqual(sut.loadBaseSystemPrompt(), "")
    }

    func testBaseSystemPromptPath() {
        XCTAssertTrue(sut.baseSystemPromptPath.hasSuffix("system_prompt.md"))
    }

    // MARK: - Agent Persona

    func testSaveAndLoadAgentPersona() {
        let persona = "이름: 도치\n성격: 친근한 비서"
        sut.saveAgentPersona(agentName: "도치", content: persona)
        XCTAssertEqual(sut.loadAgentPersona(agentName: "도치"), persona)
    }

    func testLoadAgentPersonaReturnsEmptyWhenNoFile() {
        XCTAssertEqual(sut.loadAgentPersona(agentName: "없는에이전트"), "")
    }

    // MARK: - Agent Memory

    func testSaveAndLoadAgentMemory() {
        let memory = "사용자 취미: 프로그래밍"
        sut.saveAgentMemory(agentName: "도치", content: memory)
        XCTAssertEqual(sut.loadAgentMemory(agentName: "도치"), memory)
    }

    func testAppendAgentMemory() {
        sut.saveAgentMemory(agentName: "도치", content: "기억1")
        sut.appendAgentMemory(agentName: "도치", content: "기억2")
        let result = sut.loadAgentMemory(agentName: "도치")
        XCTAssertTrue(result.contains("기억1"))
        XCTAssertTrue(result.contains("기억2"))
    }

    func testAppendAgentMemoryOnEmpty() {
        sut.appendAgentMemory(agentName: "도치", content: "첫 기억")
        XCTAssertEqual(sut.loadAgentMemory(agentName: "도치"), "첫 기억")
    }

    // MARK: - Agent Config

    func testSaveAndLoadAgentConfig() {
        let config = AgentConfig(name: "도치", wakeWord: "도치야", description: "테스트 에이전트")
        sut.saveAgentConfig(config)

        let loaded = sut.loadAgentConfig(agentName: "도치")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.name, "도치")
        XCTAssertEqual(loaded?.wakeWord, "도치야")
        XCTAssertEqual(loaded?.description, "테스트 에이전트")
    }

    func testLoadAgentConfigReturnsNilWhenNoFile() {
        XCTAssertNil(sut.loadAgentConfig(agentName: "없는에이전트"))
    }

    // MARK: - Agent Management

    func testCreateAgent() {
        sut.createAgent(name: "테스트", wakeWord: "테스트야", description: "설명")

        let agents = sut.listAgents()
        XCTAssertTrue(agents.contains("테스트"))

        let config = sut.loadAgentConfig(agentName: "테스트")
        XCTAssertEqual(config?.name, "테스트")
        XCTAssertEqual(config?.wakeWord, "테스트야")

        // 기본 페르소나가 생성됨
        let persona = sut.loadAgentPersona(agentName: "테스트")
        XCTAssertFalse(persona.isEmpty)
    }

    func testListAgentsEmpty() {
        XCTAssertEqual(sut.listAgents(), [])
    }

    func testListAgentsMultiple() {
        sut.createAgent(name: "에이전트A", wakeWord: "A야", description: "A")
        sut.createAgent(name: "에이전트B", wakeWord: "B야", description: "B")

        let agents = sut.listAgents()
        XCTAssertEqual(agents.count, 2)
        XCTAssertTrue(agents.contains("에이전트A"))
        XCTAssertTrue(agents.contains("에이전트B"))
    }

    // MARK: - Legacy Methods (Deprecated)
    // Migration tests removed - migration should be done manually via local files

    // MARK: - buildInstructions Integration

    func testBuildInstructionsUsesAgentFiles() {
        // 에이전트 구조 셋업
        sut.saveBaseSystemPrompt("기본 규칙")
        sut.saveAgentPersona(agentName: "도치", content: "도치 페르소나")
        sut.saveAgentMemory(agentName: "도치", content: "도치 기억")

        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("도치", forKey: "settings.activeAgentName")
        defaults.set(true, forKey: "settings.migratedToAgentStructure")

        let settings = AppSettings(contextService: sut, defaults: defaults)
        let instructions = settings.buildInstructions()

        XCTAssertTrue(instructions.contains("기본 규칙"))
        XCTAssertTrue(instructions.contains("도치 페르소나"))
        XCTAssertTrue(instructions.contains("도치 기억"))
    }

}
