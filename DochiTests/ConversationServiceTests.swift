import XCTest
@testable import Dochi

@MainActor
final class ConversationServiceTests: XCTestCase {
    private func makeService() -> (ConversationService, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dochi-conv-tests-\(UUID().uuidString)")
        return (ConversationService(baseURL: dir), dir)
    }

    func testSaveLoadRoundtrip() {
        let (service, dir) = makeService()
        defer { try? FileManager.default.removeItem(at: dir) }

        var conversation = Conversation(title: "테스트 대화")
        conversation.messages.append(Message(role: .user, content: "안녕"))
        conversation.messages.append(Message(role: .assistant, content: "안녕하세요"))
        service.save(conversation: conversation)

        let loaded = service.load(id: conversation.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.title, "테스트 대화")
        XCTAssertEqual(loaded?.messages.count, 2)
        XCTAssertEqual(loaded?.messages.last?.content, "안녕하세요")
    }

    func testListAndDelete() {
        let (service, dir) = makeService()
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = Conversation(title: "A")
        let b = Conversation(title: "B")
        service.save(conversation: a)
        service.save(conversation: b)
        XCTAssertEqual(service.list().count, 2)

        service.delete(id: a.id)
        let remaining = service.list()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.title, "B")
    }
}
