import XCTest
@testable import Dochi

final class ConversationServiceTests: XCTestCase {
    var sut: ConversationService!
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut = ConversationService(baseDirectory: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        tempDir = nil
    }

    // MARK: - Save and Load Tests

    func testSaveAndLoadConversation() {
        // Given
        let id = UUID()
        let messages = [
            Message(role: .user, content: "Hello"),
            Message(role: .assistant, content: "Hi there!")
        ]
        let conversation = Conversation(
            id: id,
            title: "Test Conversation",
            messages: messages
        )

        // When
        sut.save(conversation)
        let loaded = sut.load(id: id)

        // Then
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, id)
        XCTAssertEqual(loaded?.title, "Test Conversation")
        XCTAssertEqual(loaded?.messages.count, 2)
        XCTAssertEqual(loaded?.messages[0].content, "Hello")
        XCTAssertEqual(loaded?.messages[1].content, "Hi there!")
    }

    func testLoadReturnsNilWhenNotFound() {
        // Given
        let nonExistentId = UUID()

        // When
        let loaded = sut.load(id: nonExistentId)

        // Then
        XCTAssertNil(loaded)
    }

    // MARK: - List Tests

    func testListConversationsReturnsOrderedByDate() throws {
        // Given
        let oldDate = Date(timeIntervalSinceNow: -3600) // 1 hour ago
        let newDate = Date()

        let oldConversation = Conversation(
            id: UUID(),
            title: "Old",
            messages: [],
            createdAt: oldDate,
            updatedAt: oldDate
        )
        let newConversation = Conversation(
            id: UUID(),
            title: "New",
            messages: [],
            createdAt: newDate,
            updatedAt: newDate
        )

        // When - save in reverse order
        sut.save(newConversation)
        sut.save(oldConversation)
        let list = sut.list()

        // Then - should be sorted by updatedAt descending
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].title, "New")
        XCTAssertEqual(list[1].title, "Old")
    }

    func testListReturnsEmptyWhenNoConversations() {
        // Given - no conversations saved

        // When
        let list = sut.list()

        // Then
        XCTAssertTrue(list.isEmpty)
    }

    // MARK: - Delete Tests

    func testDeleteConversation() {
        // Given
        let id = UUID()
        let conversation = Conversation(
            id: id,
            title: "To Delete",
            messages: []
        )
        sut.save(conversation)

        // When
        sut.delete(id: id)
        let loaded = sut.load(id: id)

        // Then
        XCTAssertNil(loaded)
    }

    func testDeleteNonExistentConversationDoesNotThrow() {
        // Given
        let nonExistentId = UUID()

        // When / Then - should not throw
        sut.delete(id: nonExistentId)
    }

    // MARK: - Update Tests

    func testUpdateConversation() {
        // Given
        let id = UUID()
        let original = Conversation(
            id: id,
            title: "Original",
            messages: []
        )
        sut.save(original)

        // When
        let updated = Conversation(
            id: id,
            title: "Updated",
            messages: [Message(role: .user, content: "New message")],
            createdAt: original.createdAt,
            updatedAt: Date()
        )
        sut.save(updated)
        let loaded = sut.load(id: id)

        // Then
        XCTAssertEqual(loaded?.title, "Updated")
        XCTAssertEqual(loaded?.messages.count, 1)
    }
}
