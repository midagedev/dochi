import XCTest
@testable import Dochi

// MARK: - AppGuideContentBuilder Tests

final class AppGuideContentBuilderTests: XCTestCase {

    // MARK: - Overview (no topic, no query)

    @MainActor
    func testBuildOverview() {
        let response = AppGuideContentBuilder.build(topic: nil, query: nil, toolRegistry: nil)
        XCTAssertEqual(response.topic, "overview")
        XCTAssertFalse(response.items.isEmpty)
        XCTAssertEqual(response.relatedTopics, AppGuideContentBuilder.allTopics)
    }

    @MainActor
    func testBuildOverviewWithExplicitTopic() {
        let response = AppGuideContentBuilder.build(topic: "overview", query: nil, toolRegistry: nil)
        XCTAssertEqual(response.topic, "overview")
        XCTAssertFalse(response.items.isEmpty)
    }

    @MainActor
    func testBuildOverviewContainsKeyItems() {
        let response = AppGuideContentBuilder.build(topic: nil, query: nil, toolRegistry: nil)
        let titles = response.items.map(\.title)
        XCTAssertTrue(titles.contains("기능 카테고리"))
        XCTAssertTrue(titles.contains("에이전트"))
        XCTAssertTrue(titles.contains("커맨드 팔레트"))
    }

    // MARK: - Topic-specific

    @MainActor
    func testBuildFeatures() {
        let response = AppGuideContentBuilder.build(topic: "features", query: nil, toolRegistry: nil)
        XCTAssertEqual(response.topic, "features")
        XCTAssertEqual(response.items.count, 8) // 8 categories
        XCTAssertTrue(response.relatedTopics.contains("tools"))
    }

    @MainActor
    func testBuildShortcuts() {
        let response = AppGuideContentBuilder.build(topic: "shortcuts", query: nil, toolRegistry: nil)
        XCTAssertEqual(response.topic, "shortcuts")
        XCTAssertFalse(response.items.isEmpty)
        // All shortcut items should have a shortcut key
        for item in response.items {
            XCTAssertNotNil(item.shortcut, "Shortcut item '\(item.title)' should have shortcut key")
        }
    }

    @MainActor
    func testBuildShortcutsContainsTerminal() {
        let response = AppGuideContentBuilder.build(topic: "shortcuts", query: nil, toolRegistry: nil)
        let hasTerminal = response.items.contains { $0.category == "터미널" }
        XCTAssertTrue(hasTerminal, "Shortcuts should include terminal section")
    }

    @MainActor
    func testBuildSettings() {
        let response = AppGuideContentBuilder.build(topic: "settings", query: nil, toolRegistry: nil)
        XCTAssertEqual(response.topic, "settings")
        XCTAssertFalse(response.items.isEmpty)
        let titles = response.items.map(\.title)
        XCTAssertTrue(titles.contains("일반"))
        XCTAssertTrue(titles.contains("AI 모델"))
        XCTAssertTrue(titles.contains("API 키"))
    }

    @MainActor
    func testBuildAgents() {
        let response = AppGuideContentBuilder.build(topic: "agents", query: nil, toolRegistry: nil)
        XCTAssertEqual(response.topic, "agents")
        XCTAssertFalse(response.items.isEmpty)
    }

    @MainActor
    func testBuildWorkspaces() {
        let response = AppGuideContentBuilder.build(topic: "workspaces", query: nil, toolRegistry: nil)
        XCTAssertEqual(response.topic, "workspaces")
        XCTAssertFalse(response.items.isEmpty)
    }

    @MainActor
    func testBuildKanban() {
        let response = AppGuideContentBuilder.build(topic: "kanban", query: nil, toolRegistry: nil)
        XCTAssertEqual(response.topic, "kanban")
        XCTAssertFalse(response.items.isEmpty)
    }

    @MainActor
    func testBuildVoice() {
        let response = AppGuideContentBuilder.build(topic: "voice", query: nil, toolRegistry: nil)
        XCTAssertEqual(response.topic, "voice")
        XCTAssertFalse(response.items.isEmpty)
    }

    @MainActor
    func testBuildMemory() {
        let response = AppGuideContentBuilder.build(topic: "memory", query: nil, toolRegistry: nil)
        XCTAssertEqual(response.topic, "memory")
        XCTAssertFalse(response.items.isEmpty)
    }

    @MainActor
    func testBuildMCP() {
        let response = AppGuideContentBuilder.build(topic: "mcp", query: nil, toolRegistry: nil)
        XCTAssertEqual(response.topic, "mcp")
        XCTAssertFalse(response.items.isEmpty)
    }

    @MainActor
    func testBuildTelegram() {
        let response = AppGuideContentBuilder.build(topic: "telegram", query: nil, toolRegistry: nil)
        XCTAssertEqual(response.topic, "telegram")
        XCTAssertFalse(response.items.isEmpty)
    }

    @MainActor
    func testBuildTerminal() {
        let response = AppGuideContentBuilder.build(topic: "terminal", query: nil, toolRegistry: nil)
        XCTAssertEqual(response.topic, "terminal")
        XCTAssertFalse(response.items.isEmpty)
        XCTAssertTrue(response.relatedTopics.contains("tools"))
    }

    // MARK: - Query filtering

    @MainActor
    func testQueryFilterWithinTopic() {
        let response = AppGuideContentBuilder.build(topic: "shortcuts", query: "에이전트", toolRegistry: nil)
        XCTAssertEqual(response.topic, "shortcuts")
        XCTAssertFalse(response.items.isEmpty)
        for item in response.items {
            let matches = item.title.localizedCaseInsensitiveContains("에이전트") ||
                          item.description.localizedCaseInsensitiveContains("에이전트") ||
                          (item.category?.localizedCaseInsensitiveContains("에이전트") ?? false)
            XCTAssertTrue(matches, "Item '\(item.title)' should match query '에이전트'")
        }
    }

    @MainActor
    func testQueryOnlySearchesAllTopics() {
        let response = AppGuideContentBuilder.build(topic: nil, query: "칸반", toolRegistry: nil)
        XCTAssertTrue(response.topic.hasPrefix("검색:"))
        XCTAssertFalse(response.items.isEmpty)
    }

    @MainActor
    func testQueryNoResults() {
        let response = AppGuideContentBuilder.build(topic: "voice", query: "칸반보드", toolRegistry: nil)
        XCTAssertTrue(response.items.isEmpty)
    }

    @MainActor
    func testSearchResultsLimitedTo20() {
        // Build a query that matches many items across all topics
        let response = AppGuideContentBuilder.build(topic: nil, query: "설정", toolRegistry: nil)
        XCTAssertLessThanOrEqual(response.items.count, AppGuideContentBuilder.maxSearchResults)
    }

    // MARK: - Tools with ToolRegistry

    @MainActor
    func testBuildToolsWithRegistry() {
        let registry = ToolRegistry()
        let response = AppGuideContentBuilder.build(topic: "tools", query: nil, toolRegistry: registry)
        XCTAssertEqual(response.topic, "tools")
        // Empty registry returns empty tools
        XCTAssertTrue(response.items.isEmpty)
    }

    @MainActor
    func testBuildToolsWithoutRegistry() {
        let response = AppGuideContentBuilder.build(topic: "tools", query: nil, toolRegistry: nil)
        XCTAssertEqual(response.topic, "tools")
        // Without registry, returns fallback message
        XCTAssertEqual(response.items.count, 1)
        XCTAssertTrue(response.items[0].description.contains("tools.list"))
    }

    // MARK: - Related Topics

    @MainActor
    func testRelatedTopicsForFeatures() {
        let response = AppGuideContentBuilder.build(topic: "features", query: nil, toolRegistry: nil)
        XCTAssertTrue(response.relatedTopics.contains("tools"))
        XCTAssertTrue(response.relatedTopics.contains("shortcuts"))
    }

    @MainActor
    func testRelatedTopicsForAgents() {
        let response = AppGuideContentBuilder.build(topic: "agents", query: nil, toolRegistry: nil)
        XCTAssertTrue(response.relatedTopics.contains("workspaces"))
        XCTAssertTrue(response.relatedTopics.contains("memory"))
    }

    // MARK: - Formatted Output

    @MainActor
    func testFormattedOutput() {
        let response = AppGuideContentBuilder.build(topic: "kanban", query: nil, toolRegistry: nil)
        let formatted = response.formatted()
        XCTAssertTrue(formatted.contains("[kanban]"))
        XCTAssertTrue(formatted.contains("가이드"))
        XCTAssertTrue(formatted.contains("관련 주제:"))
    }

    // MARK: - All Topics Covered

    @MainActor
    func testAllTopicsListIsComplete() {
        let topics = AppGuideContentBuilder.allTopics
        XCTAssertEqual(topics.count, 12)
        XCTAssertTrue(topics.contains("features"))
        XCTAssertTrue(topics.contains("shortcuts"))
        XCTAssertTrue(topics.contains("settings"))
        XCTAssertTrue(topics.contains("tools"))
        XCTAssertTrue(topics.contains("agents"))
        XCTAssertTrue(topics.contains("workspaces"))
        XCTAssertTrue(topics.contains("kanban"))
        XCTAssertTrue(topics.contains("voice"))
        XCTAssertTrue(topics.contains("memory"))
        XCTAssertTrue(topics.contains("mcp"))
        XCTAssertTrue(topics.contains("telegram"))
        XCTAssertTrue(topics.contains("terminal"))
    }

    // MARK: - All Topics Return Non-Empty Content

    @MainActor
    func testAllTopicsReturnContent() {
        for topic in AppGuideContentBuilder.allTopics {
            let response = AppGuideContentBuilder.build(topic: topic, query: nil, toolRegistry: nil)
            XCTAssertFalse(response.items.isEmpty, "Topic '\(topic)' should return non-empty items")
        }
    }

    // MARK: - Unknown Topic

    @MainActor
    func testUnknownTopicReturnsEmpty() {
        let response = AppGuideContentBuilder.build(topic: "nonexistent", query: nil, toolRegistry: nil)
        XCTAssertTrue(response.items.isEmpty)
    }
}

// MARK: - AppGuideTool Tests

final class AppGuideToolTests: XCTestCase {

    @MainActor
    func testToolMetadata() {
        let tool = AppGuideTool()
        XCTAssertEqual(tool.name, "app.guide")
        XCTAssertEqual(tool.category, .safe)
        XCTAssertTrue(tool.isBaseline)
    }

    @MainActor
    func testExecuteNoArgs() async {
        let tool = AppGuideTool()
        let result = await tool.execute(arguments: [:])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("[overview]"))
    }

    @MainActor
    func testExecuteWithOverviewTopic() async {
        let tool = AppGuideTool()
        let result = await tool.execute(arguments: ["topic": "overview"])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("[overview]"))
    }

    @MainActor
    func testExecuteWithTopic() async {
        let tool = AppGuideTool()
        let result = await tool.execute(arguments: ["topic": "shortcuts"])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("[shortcuts]"))
        XCTAssertTrue(result.content.contains("⌘"))
    }

    @MainActor
    func testExecuteWithQuery() async {
        let tool = AppGuideTool()
        let result = await tool.execute(arguments: ["query": "칸반"])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("칸반"))
    }

    @MainActor
    func testExecuteWithTopicAndQuery() async {
        let tool = AppGuideTool()
        let result = await tool.execute(arguments: ["topic": "shortcuts", "query": "에이전트"])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("[shortcuts]"))
        XCTAssertTrue(result.content.contains("에이전트"))
    }

    @MainActor
    func testExecuteInvalidTopic() async {
        let tool = AppGuideTool()
        let result = await tool.execute(arguments: ["topic": "invalid_topic"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("알 수 없는 주제"))
    }

    @MainActor
    func testExecuteQueryNoResults() async {
        let tool = AppGuideTool()
        let result = await tool.execute(arguments: ["topic": "voice", "query": "칸반보드"])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("찾을 수 없습니다"))
    }

    @MainActor
    func testExecuteTerminalTopic() async {
        let tool = AppGuideTool()
        let result = await tool.execute(arguments: ["topic": "terminal"])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("[terminal]"))
        XCTAssertTrue(result.content.contains("터미널"))
    }

    @MainActor
    func testExecuteToolsWithRegistry() async {
        let registry = ToolRegistry()
        let tool = AppGuideTool(toolRegistry: registry)
        let result = await tool.execute(arguments: ["topic": "tools"])
        XCTAssertFalse(result.isError)
    }

    @MainActor
    func testInputSchemaHasTopicAndQuery() {
        let tool = AppGuideTool()
        let schema = tool.inputSchema
        guard let properties = schema["properties"] as? [String: Any] else {
            XCTFail("Schema should have properties")
            return
        }
        XCTAssertNotNil(properties["topic"])
        XCTAssertNotNil(properties["query"])
    }

    @MainActor
    func testInputSchemaTopicEnum() {
        let tool = AppGuideTool()
        let schema = tool.inputSchema
        guard let properties = schema["properties"] as? [String: Any],
              let topicProp = properties["topic"] as? [String: Any],
              let topicEnum = topicProp["enum"] as? [String] else {
            XCTFail("Schema should have topic enum")
            return
        }
        XCTAssertTrue(topicEnum.contains("overview"))
        XCTAssertTrue(topicEnum.contains("features"))
        XCTAssertTrue(topicEnum.contains("shortcuts"))
        XCTAssertTrue(topicEnum.contains("terminal"))
    }
}

// MARK: - GuideResponse Formatting Tests

final class GuideResponseFormattingTests: XCTestCase {

    func testFormattedWithShortcut() {
        let response = GuideResponse(
            topic: "test",
            items: [
                GuideItem(title: "테스트", description: "테스트 설명", shortcut: "⌘T", category: "일반", example: "예시")
            ],
            relatedTopics: ["other"]
        )
        let formatted = response.formatted()
        XCTAssertTrue(formatted.contains("[test]"))
        XCTAssertTrue(formatted.contains("(⌘T)"))
        XCTAssertTrue(formatted.contains("[일반]"))
        XCTAssertTrue(formatted.contains("예시: \"예시\""))
        XCTAssertTrue(formatted.contains("관련 주제: other"))
    }

    func testFormattedWithoutOptionalFields() {
        let response = GuideResponse(
            topic: "test",
            items: [
                GuideItem(title: "제목만", description: "설명만", shortcut: nil, category: nil, example: nil)
            ],
            relatedTopics: []
        )
        let formatted = response.formatted()
        XCTAssertTrue(formatted.contains("- 제목만"))
        XCTAssertTrue(formatted.contains("설명만"))
        XCTAssertFalse(formatted.contains("관련 주제:"))
    }

    func testFormattedItemCount() {
        let response = GuideResponse(
            topic: "test",
            items: [
                GuideItem(title: "A", description: "a", shortcut: nil, category: nil, example: nil),
                GuideItem(title: "B", description: "b", shortcut: nil, category: nil, example: nil),
            ],
            relatedTopics: []
        )
        let formatted = response.formatted()
        XCTAssertTrue(formatted.contains("2개 항목"))
    }
}

// MARK: - AppSettings appGuideEnabled Tests

final class AppSettingsAppGuideTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "appGuideEnabled")
    }

    @MainActor
    func testAppGuideEnabledDefaultTrue() {
        let settings = AppSettings()
        XCTAssertTrue(settings.appGuideEnabled)
    }

    @MainActor
    func testAppGuideEnabledSetFalse() {
        let settings = AppSettings()
        settings.appGuideEnabled = false
        XCTAssertFalse(settings.appGuideEnabled)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "appGuideEnabled"))
    }

    @MainActor
    func testAppGuideEnabledPersists() {
        let settings = AppSettings()
        settings.appGuideEnabled = false

        // Simulate reading from UserDefaults on next launch
        let freshSettings = AppSettings()
        XCTAssertFalse(freshSettings.appGuideEnabled)

        // Restore
        settings.appGuideEnabled = true
    }
}
