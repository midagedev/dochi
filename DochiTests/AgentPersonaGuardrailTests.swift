import XCTest
@testable import Dochi

@MainActor
final class AgentPersonaGuardrailTests: XCTestCase {
    private func makeTempDir() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("DochiTest_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testPersonaReplacePreviewAndConfirm() async throws {
        let base = makeTempDir()
        let context = ContextService(baseDirectory: base)
        let settings = AppSettings(contextService: context)
        settings.activeAgentName = "테스트"

        context.createAgent(name: "테스트", wakeWord: "도치야", description: "")
        // Persona with 6 matches
        let lines = Array(repeating: "AAA", count: 6).joined(separator: "\n")
        context.saveAgentPersona(agentName: "테스트", content: lines)

        let tool = AgentEditorTool()
        tool.contextService = context
        tool.settings = settings

        // Without confirm should error
        let noConfirm = try await tool.callTool(name: "agent.persona_replace", arguments: ["find": "AAA", "replace": "BBB"])
        XCTAssertTrue(noConfirm.isError)

        // Preview should return JSON with matches=6
        let preview = try await tool.callTool(name: "agent.persona_replace", arguments: ["find": "AAA", "replace": "BBB", "preview": true])
        XCTAssertFalse(preview.isError)
        XCTAssertTrue(preview.content.contains("matches"))

        // With confirm should apply
        let confirmed = try await tool.callTool(name: "agent.persona_replace", arguments: ["find": "AAA", "replace": "BBB", "confirm": true])
        XCTAssertFalse(confirmed.isError)
        let updated = context.loadAgentPersona(agentName: "테스트")
        XCTAssertTrue(updated.contains("BBB"))
        XCTAssertFalse(updated.contains("AAA"))
    }
}
