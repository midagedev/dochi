import XCTest
@testable import Dochi

final class ProfileAdminToolTests: XCTestCase {
    private func makeTempDir() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("DochiTest_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    final class FakeConversationService: ConversationServiceProtocol {
        private var store: [UUID: Conversation] = [:]
        func list() -> [Conversation] { Array(store.values) }
        func load(id: UUID) -> Conversation? { store[id] }
        func save(_ conversation: Conversation) { store[conversation.id] = conversation }
        func delete(id: UUID) { store.removeValue(forKey: id) }
    }

    func testProfileMergeAppendsMemoryAndMigratesConversations() async throws {
        let base = makeTempDir()
        let context = ContextService(baseDirectory: base)
        var profiles = context.loadProfiles()
        let source = UserProfile(name: "민수")
        let target = UserProfile(name: "민서")
        profiles.append(contentsOf: [source, target])
        context.saveProfiles(profiles)
        context.saveUserMemory(userId: source.id, content: "- 소스 메모")
        context.saveUserMemory(userId: target.id, content: "- 타깃 메모")

        // conversation referencing source
        let conv = Conversation(title: "t", messages: [], userId: source.id.uuidString)
        let fakeConv = FakeConversationService()
        fakeConv.save(conv)

        let tool = ProfileAdminTool()
        tool.contextService = context
        tool.conversationService = fakeConv

        let result = try await tool.callTool(name: "profile.merge", arguments: [
            "source": source.name,
            "target": target.name,
            "merge_memory": "append"
        ])
        XCTAssertFalse(result.isError)

        let merged = context.loadUserMemory(userId: target.id)
        XCTAssertTrue(merged.contains("타깃 메모"))
        XCTAssertTrue(merged.contains("소스 메모"))

        // profiles updated
        let updatedProfiles = context.loadProfiles()
        XCTAssertEqual(updatedProfiles.count, 1)
        XCTAssertEqual(updatedProfiles.first?.name, target.name)

        // conversation migrated
        let saved = fakeConv.list().first
        XCTAssertEqual(saved?.userId, target.id.uuidString)
    }
}

