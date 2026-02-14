import XCTest
import OSLog
@testable import Dochi

@MainActor
final class LogViewerViewModelTests: XCTestCase {

    private func makeSampleEntries() -> [LogEntry] {
        [
            LogEntry(id: UUID(), date: Date(), category: "LLM", level: .info, composedMessage: "Sending request to OpenAI"),
            LogEntry(id: UUID(), date: Date(), category: "Tool", level: .debug, composedMessage: "Registry loaded 35 tools"),
            LogEntry(id: UUID(), date: Date(), category: "LLM", level: .error, composedMessage: "API key invalid"),
            LogEntry(id: UUID(), date: Date(), category: "STT", level: .info, composedMessage: "Speech recognition started"),
            LogEntry(id: UUID(), date: Date(), category: "MCP", level: .notice, composedMessage: "Server connected"),
            LogEntry(id: UUID(), date: Date(), category: "Tool", level: .error, composedMessage: "Tool execution failed"),
        ]
    }

    // MARK: - Category Filter

    func testFilterByCategory() {
        let vm = LogViewerViewModel()
        vm.entries = makeSampleEntries()

        vm.selectedCategory = "LLM"
        XCTAssertEqual(vm.filteredEntries.count, 2)
        XCTAssertTrue(vm.filteredEntries.allSatisfy { $0.category == "LLM" })
    }

    func testFilterByCategoryNilShowsAll() {
        let vm = LogViewerViewModel()
        vm.entries = makeSampleEntries()

        vm.selectedCategory = nil
        XCTAssertEqual(vm.filteredEntries.count, 6)
    }

    // MARK: - Level Filter

    func testFilterByLevel() {
        let vm = LogViewerViewModel()
        vm.entries = makeSampleEntries()

        vm.selectedLevel = .error
        XCTAssertEqual(vm.filteredEntries.count, 2)
        XCTAssertTrue(vm.filteredEntries.allSatisfy { $0.level == .error })
    }

    func testFilterByLevelNilShowsAll() {
        let vm = LogViewerViewModel()
        vm.entries = makeSampleEntries()

        vm.selectedLevel = nil
        XCTAssertEqual(vm.filteredEntries.count, 6)
    }

    // MARK: - Text Search

    func testSearchText() {
        let vm = LogViewerViewModel()
        vm.entries = makeSampleEntries()

        vm.searchText = "registry"
        XCTAssertEqual(vm.filteredEntries.count, 1)
        XCTAssertEqual(vm.filteredEntries.first?.category, "Tool")
    }

    func testSearchTextCaseInsensitive() {
        let vm = LogViewerViewModel()
        vm.entries = makeSampleEntries()

        vm.searchText = "OPENAI"
        XCTAssertEqual(vm.filteredEntries.count, 1)
        XCTAssertEqual(vm.filteredEntries.first?.composedMessage, "Sending request to OpenAI")
    }

    func testSearchTextEmpty() {
        let vm = LogViewerViewModel()
        vm.entries = makeSampleEntries()

        vm.searchText = ""
        XCTAssertEqual(vm.filteredEntries.count, 6)
    }

    // MARK: - Combined Filters

    func testCombinedCategoryAndLevel() {
        let vm = LogViewerViewModel()
        vm.entries = makeSampleEntries()

        vm.selectedCategory = "Tool"
        vm.selectedLevel = .error
        XCTAssertEqual(vm.filteredEntries.count, 1)
        XCTAssertEqual(vm.filteredEntries.first?.composedMessage, "Tool execution failed")
    }

    func testCombinedCategoryLevelAndSearch() {
        let vm = LogViewerViewModel()
        vm.entries = makeSampleEntries()

        vm.selectedCategory = "LLM"
        vm.selectedLevel = .info
        vm.searchText = "request"
        XCTAssertEqual(vm.filteredEntries.count, 1)
        XCTAssertEqual(vm.filteredEntries.first?.composedMessage, "Sending request to OpenAI")
    }

    func testCombinedFiltersNoMatch() {
        let vm = LogViewerViewModel()
        vm.entries = makeSampleEntries()

        vm.selectedCategory = "STT"
        vm.selectedLevel = .error
        XCTAssertEqual(vm.filteredEntries.count, 0)
    }

    // MARK: - Clear Entries

    func testClearEntries() {
        let vm = LogViewerViewModel()
        vm.entries = makeSampleEntries()
        vm.lastRefreshDate = Date()

        XCTAssertFalse(vm.entries.isEmpty)
        XCTAssertNotNil(vm.lastRefreshDate)

        vm.clearEntries()

        XCTAssertTrue(vm.entries.isEmpty)
        XCTAssertNil(vm.lastRefreshDate)
    }

    // MARK: - Auto Refresh Toggle

    func testAutoRefreshStartStop() {
        let vm = LogViewerViewModel()

        vm.isAutoRefresh = true
        XCTAssertTrue(vm.isAutoRefresh)

        vm.isAutoRefresh = false
        XCTAssertFalse(vm.isAutoRefresh)
    }

    // MARK: - Level Labels

    func testLevelLabels() {
        let levels: [(OSLogEntryLog.Level, String)] = [
            (.debug, "debug"),
            (.info, "info"),
            (.notice, "notice"),
            (.error, "error"),
            (.fault, "fault"),
        ]
        for (level, expected) in levels {
            let entry = LogEntry(id: UUID(), date: Date(), category: "App", level: level, composedMessage: "test")
            XCTAssertEqual(entry.levelLabel, expected)
        }
    }

    // MARK: - All Categories

    func testAllCategoriesNotEmpty() {
        XCTAssertEqual(Log.allCategories.count, 10)
        XCTAssertTrue(Log.allCategories.contains("App"))
        XCTAssertTrue(Log.allCategories.contains("LLM"))
        XCTAssertTrue(Log.allCategories.contains("Avatar"))
    }
}
