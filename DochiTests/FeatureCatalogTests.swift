import XCTest
@testable import Dochi

final class FeatureCatalogTests: XCTestCase {

    // MARK: - FeatureSuggestion

    func testSuggestionsNotEmpty() {
        XCTAssertFalse(FeatureCatalog.suggestions.isEmpty)
    }

    func testEachSuggestionHasPrompts() {
        for suggestion in FeatureCatalog.suggestions {
            XCTAssertFalse(suggestion.icon.isEmpty, "\(suggestion.category) has no icon")
            XCTAssertFalse(suggestion.category.isEmpty, "suggestion has no category")
            XCTAssertFalse(suggestion.prompts.isEmpty, "\(suggestion.category) has no prompts")
        }
    }

    func testContextualSuggestionsReturnsThree() {
        let suggestions = FeatureCatalog.contextualSuggestions()
        XCTAssertEqual(suggestions.count, 3)
    }

    func testContextualSuggestionsAreUnique() {
        let suggestions = FeatureCatalog.contextualSuggestions()
        let ids = suggestions.map { $0.category }
        XCTAssertEqual(Set(ids).count, ids.count, "Contextual suggestions should be unique categories")
    }

    // MARK: - SlashCommand

    func testSlashCommandsNotEmpty() {
        XCTAssertFalse(FeatureCatalog.slashCommands.isEmpty)
    }

    func testSlashCommandNamesStartWithSlash() {
        for command in FeatureCatalog.slashCommands {
            XCTAssertTrue(command.name.hasPrefix("/"), "\(command.name) should start with /")
        }
    }

    func testSlashCommandUniqueNames() {
        let names = FeatureCatalog.slashCommands.map { $0.name }
        XCTAssertEqual(Set(names).count, names.count, "Slash command names should be unique")
    }

    // MARK: - matchingCommands

    func testMatchingCommandsForSlashOnly() {
        let results = FeatureCatalog.matchingCommands(for: "/")
        XCTAssertEqual(results.count, FeatureCatalog.slashCommands.count,
                       "Typing / alone should show all commands")
    }

    func testMatchingCommandsForPrefix() {
        let results = FeatureCatalog.matchingCommands(for: "/칸")
        XCTAssertTrue(results.contains { $0.name == "/칸반" })
    }

    func testMatchingCommandsForNoMatch() {
        let results = FeatureCatalog.matchingCommands(for: "/zzzzz")
        XCTAssertTrue(results.isEmpty)
    }

    func testMatchingCommandsForNonSlash() {
        let results = FeatureCatalog.matchingCommands(for: "hello")
        XCTAssertTrue(results.isEmpty, "Non-slash input should return empty")
    }

    func testMatchingCommandsByDescription() {
        // /일정 has description "오늘 일정 확인" — searching by description keyword
        let results = FeatureCatalog.matchingCommands(for: "/일정")
        XCTAssertTrue(results.contains { $0.name == "/일정" })
    }

    func testHelpCommandExists() {
        let helpCmd = FeatureCatalog.slashCommands.first { $0.name == "/도움말" }
        XCTAssertNotNil(helpCmd)
        XCTAssertNil(helpCmd?.toolGroup, "Help command should have no tool group")
    }

    // MARK: - Group Normalization

    func testToolGroupNormalization() {
        // 레거시 도구명이 논리적 그룹으로 정규화되는지 확인
        let reminderTool = ToolInfo(name: "create_reminder", description: "", category: .safe, isBaseline: true, isEnabled: true, parameters: [])
        XCTAssertEqual(reminderTool.group, "reminders")

        let timerTool = ToolInfo(name: "set_timer", description: "", category: .safe, isBaseline: true, isEnabled: true, parameters: [])
        XCTAssertEqual(timerTool.group, "timer")

        let memoryTool = ToolInfo(name: "save_memory", description: "", category: .safe, isBaseline: true, isEnabled: true, parameters: [])
        XCTAssertEqual(memoryTool.group, "memory")

        let calendarTool = ToolInfo(name: "list_calendar_events", description: "", category: .safe, isBaseline: true, isEnabled: true, parameters: [])
        XCTAssertEqual(calendarTool.group, "calendar")

        // dot-notation 도구는 첫 세그먼트 사용
        let kanbanTool = ToolInfo(name: "kanban.create_board", description: "", category: .safe, isBaseline: true, isEnabled: true, parameters: [])
        XCTAssertEqual(kanbanTool.group, "kanban")
    }

    func testSlashCommandToolGroupsMatchNormalizedGroups() {
        // 슬래시 명령의 toolGroup이 정규화된 그룹명과 일치하는지 확인
        let knownGroups: Set<String> = [
            "calendar", "reminders", "timer", "alarm", "kanban", "search",
            "file", "screenshot", "clipboard", "calculator", "datetime",
            "music", "contacts", "git", "github", "memory", "image",
            "shell", "workflow", "settings", "agent",
        ]

        for command in FeatureCatalog.slashCommands {
            guard let toolGroup = command.toolGroup else { continue }
            XCTAssertTrue(knownGroups.contains(toolGroup),
                          "SlashCommand \(command.name) has toolGroup '\(toolGroup)' which is not a known normalized group")
        }
    }

    // MARK: - Contextual Suggestions (time-parameterized)

    func testContextualSuggestionsMorning() {
        let suggestions = FeatureCatalog.contextualSuggestions(hour: 7)
        let categories = suggestions.map { $0.category }
        XCTAssertTrue(categories.contains("일정"), "Morning should include 일정")
    }

    func testContextualSuggestionsEvening() {
        let suggestions = FeatureCatalog.contextualSuggestions(hour: 20)
        let categories = suggestions.map { $0.category }
        XCTAssertTrue(categories.contains("기억"), "Evening should include 기억")
    }

    func testContextualSuggestionsAfternoon() {
        let suggestions = FeatureCatalog.contextualSuggestions(hour: 15)
        let categories = suggestions.map { $0.category }
        XCTAssertTrue(categories.contains("개발"), "Afternoon should include 개발")
    }
}
