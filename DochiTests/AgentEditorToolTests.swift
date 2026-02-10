import XCTest
@testable import Dochi

final class AgentEditorToolTests: XCTestCase {
    private func makeTempDir() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("DochiTest_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testAgentMemoryUpdate() async throws {
        let base = makeTempDir()
        let context = ContextService(baseDirectory: base)
        let settings = AppSettings(contextService: context)
        settings.activeAgentName = "테스트"
        context.createAgent(name: "테스트", wakeWord: "도치야", description: "")
        context.saveAgentMemory(agentName: "테스트", content: "- 제주 맛집\n- 부산 바다")

        let tool = AgentEditorTool()
        tool.contextService = context
        tool.settings = settings

        let result = try await tool.callTool(name: "agent.memory_update", arguments: [
            "find": "제주",
            "replace": "- 제주 맛집 지도 관리"
        ])
        XCTAssertFalse(result.isError)
        let mem = context.loadAgentMemory(agentName: "테스트")
        XCTAssertTrue(mem.contains("제주 맛집 지도 관리"))
        XCTAssertFalse(mem.contains("제주 맛집\n"))
    }
}

