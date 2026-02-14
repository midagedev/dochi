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
}
