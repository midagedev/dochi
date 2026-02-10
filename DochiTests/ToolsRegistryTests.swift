import XCTest
@testable import Dochi

@MainActor
final class ToolsRegistryTests: XCTestCase {
    private func makeTempDir() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("DochiTest_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testEnableCategoriesAndReset() async throws {
        // Prepare app settings/context so settings tool is available
        let base = makeTempDir()
        let context = ContextService(baseDirectory: base)
        let settings = AppSettings(contextService: context)

        let host = BuiltInToolService()
        host.configureSettings(settings)

        let registry = ToolsRegistryTool()
        registry.registryHost = host

        // Enable settings category
        let res = try await registry.callTool(name: "tools.enable_categories", arguments: ["categories": ["settings"]])
        XCTAssertFalse(res.isError)

        // After enabling, settings.set should be exposed in available tools
        let names = Set(host.availableTools.map { $0.name })
        XCTAssertTrue(names.contains("settings.set"))

        // Reset and ensure settings.set is hidden (baseline-only)
        _ = try await registry.callTool(name: "tools.reset", arguments: [:])
        let namesAfter = Set(host.availableTools.map { $0.name })
        XCTAssertFalse(namesAfter.contains("settings.set"))
    }
}
