import XCTest
@testable import Dochi

@MainActor
final class ClipboardToolTests: XCTestCase {

    // MARK: - ClipboardReadTool Properties

    func testReadToolName() {
        let tool = ClipboardReadTool()
        XCTAssertEqual(tool.name, "clipboard.read")
    }

    func testReadToolCategory() {
        let tool = ClipboardReadTool()
        XCTAssertEqual(tool.category, .safe)
    }

    func testReadToolIsNotBaseline() {
        let tool = ClipboardReadTool()
        XCTAssertFalse(tool.isBaseline)
    }

    func testReadToolHasDescription() {
        let tool = ClipboardReadTool()
        XCTAssertFalse(tool.description.isEmpty)
    }

    // MARK: - ClipboardWriteTool Properties

    func testWriteToolName() {
        let tool = ClipboardWriteTool()
        XCTAssertEqual(tool.name, "clipboard.write")
    }

    func testWriteToolCategory() {
        let tool = ClipboardWriteTool()
        XCTAssertEqual(tool.category, .sensitive)
    }

    func testWriteToolIsNotBaseline() {
        let tool = ClipboardWriteTool()
        XCTAssertFalse(tool.isBaseline)
    }

    func testWriteToolHasDescription() {
        let tool = ClipboardWriteTool()
        XCTAssertFalse(tool.description.isEmpty)
    }

    func testWriteToolRequiresTextParameter() {
        let tool = ClipboardWriteTool()
        let required = tool.inputSchema["required"] as? [String]
        XCTAssertEqual(required, ["text"])
    }

    // MARK: - ClipboardWriteTool Execution

    func testWriteToolMissingTextReturnsError() async {
        let tool = ClipboardWriteTool()
        let result = await tool.execute(arguments: [:])
        XCTAssertTrue(result.isError)
    }

    func testWriteToolEmptyTextReturnsError() async {
        let tool = ClipboardWriteTool()
        let result = await tool.execute(arguments: ["text": ""])
        XCTAssertTrue(result.isError)
    }

    func testWriteToolSuccess() async {
        let tool = ClipboardWriteTool()
        let result = await tool.execute(arguments: ["text": "테스트 텍스트"])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("복사"))
    }

    // MARK: - ClipboardReadTool Execution

    func testReadToolAfterWrite() async {
        // Write first
        let writeTool = ClipboardWriteTool()
        _ = await writeTool.execute(arguments: ["text": "읽기 테스트"])

        // Then read
        let readTool = ClipboardReadTool()
        let result = await readTool.execute(arguments: [:])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("읽기 테스트"))
    }

    // MARK: - Registry Integration

    func testClipboardToolsAreNonBaseline() {
        let registry = ToolRegistry()
        registry.register(ClipboardReadTool())
        registry.register(ClipboardWriteTool())

        // Non-baseline tools should not appear in baseline list
        let baseline = registry.baselineTools
        let clipboardBaseline = baseline.filter { $0.name.hasPrefix("clipboard.") }
        XCTAssertTrue(clipboardBaseline.isEmpty)
    }

    func testClipboardToolsNotAvailableWithoutEnable() {
        let registry = ToolRegistry()
        registry.register(ClipboardReadTool())
        registry.register(ClipboardWriteTool())

        // Without enable, non-baseline tools are not available
        let available = registry.availableTools(for: ["safe", "sensitive"])
        let clipboardAvailable = available.filter { $0.name.hasPrefix("clipboard.") }
        XCTAssertTrue(clipboardAvailable.isEmpty)
    }

    func testClipboardToolsAvailableAfterEnable() {
        let registry = ToolRegistry()
        registry.register(ClipboardReadTool())
        registry.register(ClipboardWriteTool())

        registry.enable(names: ["clipboard.read", "clipboard.write"])

        let available = registry.availableTools(for: ["safe", "sensitive"])
        let clipboardAvailable = available.filter { $0.name.hasPrefix("clipboard.") }
        XCTAssertEqual(clipboardAvailable.count, 2)
    }

    func testClipboardToolsAppearInNonBaselineSummaries() {
        let registry = ToolRegistry()
        registry.register(ClipboardReadTool())
        registry.register(ClipboardWriteTool())

        let summaries = registry.nonBaselineToolSummaries
        let clipboardSummaries = summaries.filter { $0.name.hasPrefix("clipboard.") }
        XCTAssertEqual(clipboardSummaries.count, 2)

        let readSummary = clipboardSummaries.first { $0.name == "clipboard.read" }
        XCTAssertEqual(readSummary?.category, .safe)

        let writeSummary = clipboardSummaries.first { $0.name == "clipboard.write" }
        XCTAssertEqual(writeSummary?.category, .sensitive)
    }
}
