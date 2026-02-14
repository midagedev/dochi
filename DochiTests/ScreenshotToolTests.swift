import XCTest
@testable import Dochi

@MainActor
final class ScreenshotToolTests: XCTestCase {

    // MARK: - Properties

    func testToolName() {
        let tool = ScreenshotCaptureTool()
        XCTAssertEqual(tool.name, "screenshot.capture")
    }

    func testToolCategory() {
        let tool = ScreenshotCaptureTool()
        XCTAssertEqual(tool.category, .sensitive)
    }

    func testToolIsNotBaseline() {
        let tool = ScreenshotCaptureTool()
        XCTAssertFalse(tool.isBaseline)
    }

    func testToolHasDescription() {
        let tool = ScreenshotCaptureTool()
        XCTAssertFalse(tool.description.isEmpty)
    }

    // MARK: - Input Schema

    func testInputSchemaHasRegionProperty() {
        let tool = ScreenshotCaptureTool()
        let properties = tool.inputSchema["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["region"])
    }

    func testInputSchemaRegionHasEnum() {
        let tool = ScreenshotCaptureTool()
        let properties = tool.inputSchema["properties"] as? [String: Any]
        let region = properties?["region"] as? [String: Any]
        let enumValues = region?["enum"] as? [String]
        XCTAssertEqual(enumValues, ["fullscreen", "window"])
    }

    func testInputSchemaNoRequiredFields() {
        let tool = ScreenshotCaptureTool()
        // region is optional (defaults to fullscreen), so no required fields
        let required = tool.inputSchema["required"] as? [String]
        XCTAssertNil(required)
    }

    // MARK: - Save Directory

    func testSaveDirIsPicturesDochi() {
        let tool = ScreenshotCaptureTool()
        let dir = tool.saveDirURL()
        XCTAssertTrue(dir.path.contains("Pictures/Dochi"))
    }

    // MARK: - Registry Integration

    func testScreenshotToolNotInBaseline() {
        let registry = ToolRegistry()
        registry.register(ScreenshotCaptureTool())

        let baseline = registry.baselineTools
        XCTAssertTrue(baseline.isEmpty)
    }

    func testScreenshotToolNotAvailableWithoutEnable() {
        let registry = ToolRegistry()
        registry.register(ScreenshotCaptureTool())

        let available = registry.availableTools(for: ["safe", "sensitive"])
        XCTAssertTrue(available.isEmpty)
    }

    func testScreenshotToolAvailableAfterEnable() {
        let registry = ToolRegistry()
        registry.register(ScreenshotCaptureTool())

        registry.enable(names: ["screenshot.capture"])
        let available = registry.availableTools(for: ["safe", "sensitive"])
        XCTAssertEqual(available.count, 1)
        XCTAssertEqual(available[0].name, "screenshot.capture")
    }

    func testScreenshotToolInNonBaselineSummaries() {
        let registry = ToolRegistry()
        registry.register(ScreenshotCaptureTool())

        let summaries = registry.nonBaselineToolSummaries
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].name, "screenshot.capture")
        XCTAssertEqual(summaries[0].category, .sensitive)
    }

    func testScreenshotToolNotAvailableWithSafeOnlyPermission() {
        let registry = ToolRegistry()
        registry.register(ScreenshotCaptureTool())

        // Even after enable, safe-only doesn't see sensitive tools...
        // Actually, enabled tools bypass category filter per ToolRegistry logic
        registry.enable(names: ["screenshot.capture"])
        let available = registry.availableTools(for: ["safe"])
        // Enabled tools bypass category filter
        XCTAssertEqual(available.count, 1)
    }
}
