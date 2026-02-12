import XCTest
@testable import Dochi

@MainActor
final class ConversationServiceTests: XCTestCase {
    private var service: ConversationService!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DochiConvTests-\(UUID().uuidString)")
        service = ConversationService(baseURL: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - CRUD

    func testListEmptyReturnsEmpty() {
        XCTAssertTrue(service.list().isEmpty)
    }

    func testSaveAndLoad() {
        let conv = Conversation(title: "테스트 대화")
        service.save(conversation: conv)

        let loaded = service.load(id: conv.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.title, "테스트 대화")
        XCTAssertEqual(loaded?.id, conv.id)
    }

    func testSaveAndList() {
        let conv1 = Conversation(title: "대화1", updatedAt: Date(timeIntervalSince1970: 1000))
        let conv2 = Conversation(title: "대화2", updatedAt: Date(timeIntervalSince1970: 2000))
        service.save(conversation: conv1)
        service.save(conversation: conv2)

        let listed = service.list()
        XCTAssertEqual(listed.count, 2)
        // Should be sorted by updatedAt descending
        XCTAssertEqual(listed[0].title, "대화2")
        XCTAssertEqual(listed[1].title, "대화1")
    }

    func testDelete() {
        let conv = Conversation(title: "삭제 대상")
        service.save(conversation: conv)
        XCTAssertNotNil(service.load(id: conv.id))

        service.delete(id: conv.id)
        XCTAssertNil(service.load(id: conv.id))
    }

    func testDeleteNonExistent() {
        // Should not crash
        service.delete(id: UUID())
    }

    func testLoadNonExistent() {
        XCTAssertNil(service.load(id: UUID()))
    }

    // MARK: - Messages

    func testSaveConversationWithMessages() {
        let msg = Message(role: .user, content: "안녕하세요")
        var conv = Conversation(title: "메시지 테스트", messages: [msg])
        conv.updatedAt = Date()

        service.save(conversation: conv)

        let loaded = service.load(id: conv.id)
        XCTAssertEqual(loaded?.messages.count, 1)
        XCTAssertEqual(loaded?.messages[0].content, "안녕하세요")
        XCTAssertEqual(loaded?.messages[0].role, .user)
    }

    func testSaveConversationWithToolCalls() {
        let toolCall = CodableToolCall(id: "tc1", name: "tools.list", argumentsJSON: "{}")
        let msg = Message(role: .assistant, content: "", toolCalls: [toolCall])
        let conv = Conversation(title: "도구 테스트", messages: [msg])

        service.save(conversation: conv)

        let loaded = service.load(id: conv.id)
        XCTAssertEqual(loaded?.messages[0].toolCalls?.count, 1)
        XCTAssertEqual(loaded?.messages[0].toolCalls?[0].name, "tools.list")
        XCTAssertEqual(loaded?.messages[0].toolCalls?[0].id, "tc1")
    }

    // MARK: - Update

    func testOverwriteConversation() {
        var conv = Conversation(title: "원래 제목")
        service.save(conversation: conv)

        conv.title = "변경된 제목"
        service.save(conversation: conv)

        let loaded = service.load(id: conv.id)
        XCTAssertEqual(loaded?.title, "변경된 제목")

        // Should still be only one
        XCTAssertEqual(service.list().count, 1)
    }
}
