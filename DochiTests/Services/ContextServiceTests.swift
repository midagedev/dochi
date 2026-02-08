import XCTest
@testable import Dochi

@MainActor
final class ContextServiceTests: XCTestCase {
    var sut: ContextService!
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut = ContextService(baseDirectory: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        tempDir = nil
    }

    // MARK: - System Tests

    func testSaveAndLoadSystem() {
        // Given
        let content = "# System Prompt\nYou are a helpful assistant."

        // When
        sut.saveSystem(content)
        let loaded = sut.loadSystem()

        // Then
        XCTAssertEqual(loaded, content)
    }

    func testLoadSystemReturnsEmptyStringWhenNoFile() {
        // Given - no file saved

        // When
        let loaded = sut.loadSystem()

        // Then
        XCTAssertEqual(loaded, "")
    }

    func testSystemPath() {
        // When
        let path = sut.systemPath

        // Then
        XCTAssertTrue(path.hasSuffix("system.md"))
        XCTAssertTrue(path.contains(tempDir.path))
    }

    // MARK: - Memory Tests

    func testSaveAndLoadMemory() {
        // Given
        let content = "User prefers Korean responses."

        // When
        sut.saveMemory(content)
        let loaded = sut.loadMemory()

        // Then
        XCTAssertEqual(loaded, content)
    }

    func testAppendMemory() {
        // Given
        sut.saveMemory("First entry")

        // When
        sut.appendMemory("Second entry")
        let loaded = sut.loadMemory()

        // Then
        XCTAssertEqual(loaded, "First entry\nSecond entry")
    }

    func testAppendMemoryToEmpty() {
        // Given - empty memory

        // When
        sut.appendMemory("First entry")
        let loaded = sut.loadMemory()

        // Then
        XCTAssertEqual(loaded, "First entry")
    }

    func testAppendMemoryPreservesNewline() {
        // Given
        sut.saveMemory("First entry\n")

        // When
        sut.appendMemory("Second entry")
        let loaded = sut.loadMemory()

        // Then
        XCTAssertEqual(loaded, "First entry\nSecond entry")
    }

    func testMemorySize() {
        // Given
        let content = "Test content"
        sut.saveMemory(content)

        // When
        let size = sut.memorySize

        // Then
        XCTAssertEqual(size, content.utf8.count)
    }

    func testMemorySizeReturnsZeroWhenNoFile() {
        // Given - no file saved

        // When
        let size = sut.memorySize

        // Then
        XCTAssertEqual(size, 0)
    }

    func testMemoryPath() {
        // When
        let path = sut.memoryPath

        // Then
        XCTAssertTrue(path.hasSuffix("memory.md"))
        XCTAssertTrue(path.contains(tempDir.path))
    }
}
