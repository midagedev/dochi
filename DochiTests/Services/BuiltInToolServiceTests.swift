import XCTest
@testable import Dochi

@MainActor
final class BuiltInToolServiceTests: XCTestCase {
    var sut: BuiltInToolService!

    override func setUp() {
        sut = BuiltInToolService()
    }

    override func tearDown() {
        sut = nil
    }

    // MARK: - Available Tools

    func testDefaultToolsIncludeReminders() {
        let toolNames = sut.availableTools.map(\.name)

        XCTAssertTrue(toolNames.contains(where: { $0.contains("reminder") }))
    }

    func testDefaultToolsIncludeAlarm() {
        let toolNames = sut.availableTools.map(\.name)

        XCTAssertTrue(toolNames.contains(where: { $0.contains("alarm") }))
    }

    func testWebSearchNotAvailableWithoutApiKey() {
        let toolNames = sut.availableTools.map(\.name)

        XCTAssertFalse(toolNames.contains("web_search"))
    }

    func testWebSearchAvailableWithApiKey() {
        sut.configure(tavilyApiKey: "tvly-test", falaiApiKey: "")

        let toolNames = sut.availableTools.map(\.name)

        XCTAssertTrue(toolNames.contains("web_search"))
    }

    func testImageGenerationNotAvailableWithoutApiKey() {
        let toolNames = sut.availableTools.map(\.name)

        XCTAssertFalse(toolNames.contains("generate_image"))
    }

    func testImageGenerationAvailableWithApiKey() {
        sut.configure(tavilyApiKey: "", falaiApiKey: "fal-test")

        let toolNames = sut.availableTools.map(\.name)

        XCTAssertTrue(toolNames.contains("generate_image"))
    }

    func testMemoryToolNotAvailableWithoutProfiles() {
        let toolNames = sut.availableTools.map(\.name)

        XCTAssertFalse(toolNames.contains("save_memory"))
    }

    func testMemoryToolAvailableWithContext() {
        let mockContext = MockContextService()
        sut.configureUserContext(contextService: mockContext, currentUserId: UUID())

        let toolNames = sut.availableTools.map(\.name)

        XCTAssertTrue(toolNames.contains("save_memory"))
    }

    // MARK: - Tool Routing

    func testCallUnknownToolThrowsError() async {
        do {
            _ = try await sut.callTool(name: "nonexistent_tool", arguments: [:])
            XCTFail("Should have thrown")
        } catch let error as BuiltInToolError {
            if case .unknownTool(let name) = error {
                XCTAssertEqual(name, "nonexistent_tool")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Configure

    func testConfigureSetsApiKeys() {
        sut.configure(tavilyApiKey: "tvly-key", falaiApiKey: "fal-key")

        XCTAssertEqual(sut.webSearchTool.apiKey, "tvly-key")
        XCTAssertEqual(sut.imageGenerationTool.apiKey, "fal-key")
    }
}
