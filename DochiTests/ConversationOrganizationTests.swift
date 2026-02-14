import XCTest
@testable import Dochi

// MARK: - Conversation Model: Backward Compatibility

@MainActor
final class ConversationModelTests: XCTestCase {

    /// New fields (isFavorite, tags, folderId) have defaults and don't break existing JSON.
    func testDecodeExistingJSONWithoutNewFields() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "title": "기존 대화",
            "messages": [],
            "createdAt": "2026-02-10T12:00:00Z",
            "updatedAt": "2026-02-10T12:00:00Z",
            "source": "local"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let conversation = try decoder.decode(Conversation.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(conversation.title, "기존 대화")
        XCTAssertFalse(conversation.isFavorite)
        XCTAssertTrue(conversation.tags.isEmpty)
        XCTAssertNil(conversation.folderId)
    }

    /// New fields round-trip correctly through encode/decode.
    func testNewFieldsRoundtrip() throws {
        let folderId = UUID()
        let conv = Conversation(
            title: "정리된 대화",
            isFavorite: true,
            tags: ["중요", "업무"],
            folderId: folderId
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(conv)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode(Conversation.self, from: data)

        XCTAssertTrue(loaded.isFavorite)
        XCTAssertEqual(loaded.tags, ["중요", "업무"])
        XCTAssertEqual(loaded.folderId, folderId)
    }

    /// Default init values for new fields.
    func testDefaultInitValues() {
        let conv = Conversation()
        XCTAssertFalse(conv.isFavorite)
        XCTAssertTrue(conv.tags.isEmpty)
        XCTAssertNil(conv.folderId)
    }
}

// MARK: - ConversationTag Model

@MainActor
final class ConversationTagModelTests: XCTestCase {

    func testTagRoundtrip() throws {
        let tag = ConversationTag(name: "중요", color: "red")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(tag)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode(ConversationTag.self, from: data)

        XCTAssertEqual(loaded.id, tag.id)
        XCTAssertEqual(loaded.name, "중요")
        XCTAssertEqual(loaded.color, "red")
    }

    func testAvailableColors() {
        XCTAssertEqual(ConversationTag.availableColors.count, 9)
        XCTAssertTrue(ConversationTag.availableColors.contains("red"))
        XCTAssertTrue(ConversationTag.availableColors.contains("blue"))
    }
}

// MARK: - ConversationFolder Model

@MainActor
final class ConversationFolderModelTests: XCTestCase {

    func testFolderRoundtrip() throws {
        let folder = ConversationFolder(name: "업무", icon: "briefcase", sortOrder: 1)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(folder)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode(ConversationFolder.self, from: data)

        XCTAssertEqual(loaded.id, folder.id)
        XCTAssertEqual(loaded.name, "업무")
        XCTAssertEqual(loaded.icon, "briefcase")
        XCTAssertEqual(loaded.sortOrder, 1)
    }

    func testDefaultValues() {
        let folder = ConversationFolder(name: "테스트")
        XCTAssertEqual(folder.icon, "folder")
        XCTAssertEqual(folder.sortOrder, 0)
    }
}

// MARK: - ContextService: Tags & Folders

@MainActor
final class ContextServiceTagsFoldersTests: XCTestCase {
    private var service: ContextService!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DochiOrgTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        service = ContextService(baseURL: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testTagsSaveAndLoad() {
        XCTAssertTrue(service.loadTags().isEmpty)

        let tags = [
            ConversationTag(name: "중요", color: "red"),
            ConversationTag(name: "업무", color: "blue"),
        ]
        service.saveTags(tags)

        let loaded = service.loadTags()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].name, "중요")
        XCTAssertEqual(loaded[0].color, "red")
        XCTAssertEqual(loaded[1].name, "업무")
    }

    func testFoldersSaveAndLoad() {
        XCTAssertTrue(service.loadFolders().isEmpty)

        let folders = [
            ConversationFolder(name: "업무", sortOrder: 0),
            ConversationFolder(name: "개인", sortOrder: 1),
        ]
        service.saveFolders(folders)

        let loaded = service.loadFolders()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].name, "업무")
        XCTAssertEqual(loaded[1].name, "개인")
    }

    func testLoadMissingTagsReturnsEmpty() {
        XCTAssertTrue(service.loadTags().isEmpty)
    }

    func testLoadMissingFoldersReturnsEmpty() {
        XCTAssertTrue(service.loadFolders().isEmpty)
    }
}

// MARK: - ConversationFilter

@MainActor
final class ConversationFilterTests: XCTestCase {

    func testDefaultFilterIsInactive() {
        let filter = ConversationFilter()
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.activeCount, 0)
    }

    func testFavoriteFilter() {
        var filter = ConversationFilter()
        filter.showFavoritesOnly = true

        XCTAssertTrue(filter.isActive)
        XCTAssertEqual(filter.activeCount, 1)

        let fav = Conversation(title: "즐겨찾기", isFavorite: true)
        let normal = Conversation(title: "일반")

        XCTAssertTrue(filter.matches(fav))
        XCTAssertFalse(filter.matches(normal))
    }

    func testTagFilter() {
        var filter = ConversationFilter()
        filter.selectedTags = ["중요"]

        let tagged = Conversation(title: "태그됨", tags: ["중요", "업무"])
        let untagged = Conversation(title: "미태그")

        XCTAssertTrue(filter.matches(tagged))
        XCTAssertFalse(filter.matches(untagged))
    }

    func testSourceFilter() {
        var filter = ConversationFilter()
        filter.source = .telegram

        let telegram = Conversation(title: "텔레그램", source: .telegram)
        let local = Conversation(title: "로컬")

        XCTAssertTrue(filter.matches(telegram))
        XCTAssertFalse(filter.matches(local))
    }

    func testReset() {
        var filter = ConversationFilter()
        filter.showFavoritesOnly = true
        filter.selectedTags = ["중요"]
        filter.source = .telegram

        XCTAssertTrue(filter.isActive)

        filter.reset()
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.activeCount, 0)
    }
}

// MARK: - DochiViewModel: Favorites, Tags, Folders

@MainActor
final class ViewModelOrganizationTests: XCTestCase {
    private var viewModel: DochiViewModel!
    private var contextService: MockContextService!
    private var conversationService: MockConversationService!
    private var settings: AppSettings!
    private var sessionContext: SessionContext!

    override func setUp() {
        super.setUp()
        contextService = MockContextService()
        conversationService = MockConversationService()
        settings = AppSettings()
        let wsId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        sessionContext = SessionContext(workspaceId: wsId)

        viewModel = DochiViewModel(
            llmService: MockLLMService(),
            toolService: MockBuiltInToolService(),
            contextService: contextService,
            conversationService: conversationService,
            keychainService: MockKeychainService(),
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: settings,
            sessionContext: sessionContext
        )
    }

    // MARK: - Favorites

    func testToggleFavorite() {
        let conv = Conversation(title: "테스트")
        conversationService.save(conversation: conv)
        viewModel.loadConversations()

        viewModel.toggleFavorite(id: conv.id)

        let loaded = conversationService.load(id: conv.id)
        XCTAssertTrue(loaded!.isFavorite)

        // Toggle back
        viewModel.toggleFavorite(id: conv.id)
        let loaded2 = conversationService.load(id: conv.id)
        XCTAssertFalse(loaded2!.isFavorite)
    }

    func testToggleFavoriteUpdatesCurrentConversation() {
        let conv = Conversation(title: "현재")
        conversationService.save(conversation: conv)
        viewModel.loadConversations()
        viewModel.selectConversation(id: conv.id)

        viewModel.toggleFavorite(id: conv.id)

        XCTAssertTrue(viewModel.currentConversation?.isFavorite == true)
    }

    // MARK: - Tags

    func testAddTag() {
        let tag = ConversationTag(name: "중요", color: "red")
        viewModel.addTag(tag)

        XCTAssertEqual(viewModel.conversationTags.count, 1)
        XCTAssertEqual(viewModel.conversationTags[0].name, "중요")
        XCTAssertEqual(contextService.conversationTags.count, 1)
    }

    func testDeleteTag() {
        let tag = ConversationTag(name: "삭제될태그", color: "gray")
        viewModel.addTag(tag)

        // Add tag to a conversation
        var conv = Conversation(title: "대화", tags: ["삭제될태그"])
        conversationService.save(conversation: conv)
        viewModel.loadConversations()

        viewModel.deleteTag(id: tag.id)

        XCTAssertTrue(viewModel.conversationTags.isEmpty)
        // Tag should be removed from conversation
        let loaded = conversationService.load(id: conv.id)
        XCTAssertFalse(loaded!.tags.contains("삭제될태그"))
    }

    func testUpdateTag() {
        let tag = ConversationTag(name: "원래이름", color: "blue")
        viewModel.addTag(tag)

        var conv = Conversation(title: "대화", tags: ["원래이름"])
        conversationService.save(conversation: conv)
        viewModel.loadConversations()

        var updated = tag
        updated.name = "새이름"
        updated.color = "red"
        viewModel.updateTag(updated)

        XCTAssertEqual(viewModel.conversationTags[0].name, "새이름")
        XCTAssertEqual(viewModel.conversationTags[0].color, "red")

        // Conversation's tag name should be updated
        let loaded = conversationService.load(id: conv.id)
        XCTAssertTrue(loaded!.tags.contains("새이름"))
        XCTAssertFalse(loaded!.tags.contains("원래이름"))
    }

    func testToggleTagOnConversation() {
        let tag = ConversationTag(name: "업무", color: "green")
        viewModel.addTag(tag)

        let conv = Conversation(title: "대화")
        conversationService.save(conversation: conv)
        viewModel.loadConversations()

        // Add tag
        viewModel.toggleTagOnConversation(conversationId: conv.id, tagName: "업무")
        var loaded = conversationService.load(id: conv.id)
        XCTAssertTrue(loaded!.tags.contains("업무"))

        // Remove tag
        viewModel.toggleTagOnConversation(conversationId: conv.id, tagName: "업무")
        loaded = conversationService.load(id: conv.id)
        XCTAssertFalse(loaded!.tags.contains("업무"))
    }

    // MARK: - Folders

    func testAddFolder() {
        let folder = ConversationFolder(name: "업무")
        viewModel.addFolder(folder)

        XCTAssertEqual(viewModel.conversationFolders.count, 1)
        XCTAssertEqual(viewModel.conversationFolders[0].name, "업무")
        XCTAssertEqual(contextService.conversationFolders.count, 1)
    }

    func testDeleteFolder() {
        let folder = ConversationFolder(name: "삭제폴더")
        viewModel.addFolder(folder)

        let conv = Conversation(title: "대화", folderId: folder.id)
        conversationService.save(conversation: conv)
        viewModel.loadConversations()

        viewModel.deleteFolder(id: folder.id)

        XCTAssertTrue(viewModel.conversationFolders.isEmpty)
        let loaded = conversationService.load(id: conv.id)
        XCTAssertNil(loaded!.folderId)
    }

    func testRenameFolder() {
        let folder = ConversationFolder(name: "원래")
        viewModel.addFolder(folder)

        viewModel.renameFolder(id: folder.id, name: "변경됨")

        XCTAssertEqual(viewModel.conversationFolders[0].name, "변경됨")
    }

    func testMoveConversationToFolder() {
        let folder = ConversationFolder(name: "업무")
        viewModel.addFolder(folder)

        let conv = Conversation(title: "이동할대화")
        conversationService.save(conversation: conv)
        viewModel.loadConversations()

        viewModel.moveConversationToFolder(conversationId: conv.id, folderId: folder.id)

        let loaded = conversationService.load(id: conv.id)
        XCTAssertEqual(loaded!.folderId, folder.id)
    }

    func testMoveConversationOutOfFolder() {
        let folder = ConversationFolder(name: "업무")
        viewModel.addFolder(folder)

        let conv = Conversation(title: "대화", folderId: folder.id)
        conversationService.save(conversation: conv)
        viewModel.loadConversations()

        viewModel.moveConversationToFolder(conversationId: conv.id, folderId: nil)

        let loaded = conversationService.load(id: conv.id)
        XCTAssertNil(loaded!.folderId)
    }

    // MARK: - Multi-select

    func testToggleMultiSelectMode() {
        XCTAssertFalse(viewModel.isMultiSelectMode)

        viewModel.toggleMultiSelectMode()
        XCTAssertTrue(viewModel.isMultiSelectMode)

        // Disable clears selection
        let conv = Conversation(title: "대화")
        conversationService.save(conversation: conv)
        viewModel.loadConversations()
        viewModel.toggleConversationSelection(id: conv.id)
        XCTAssertFalse(viewModel.selectedConversationIds.isEmpty)

        viewModel.toggleMultiSelectMode()
        XCTAssertFalse(viewModel.isMultiSelectMode)
        XCTAssertTrue(viewModel.selectedConversationIds.isEmpty)
    }

    func testSelectAllAndDeselectAll() {
        let c1 = Conversation(title: "1")
        let c2 = Conversation(title: "2")
        conversationService.save(conversation: c1)
        conversationService.save(conversation: c2)
        viewModel.loadConversations()

        viewModel.selectAllConversations()
        XCTAssertEqual(viewModel.selectedConversationIds.count, 2)

        viewModel.deselectAllConversations()
        XCTAssertTrue(viewModel.selectedConversationIds.isEmpty)
    }

    // MARK: - Bulk Actions

    func testBulkDelete() {
        let c1 = Conversation(title: "삭제1")
        let c2 = Conversation(title: "삭제2")
        let c3 = Conversation(title: "유지")
        conversationService.save(conversation: c1)
        conversationService.save(conversation: c2)
        conversationService.save(conversation: c3)
        viewModel.loadConversations()

        viewModel.toggleMultiSelectMode()
        viewModel.toggleConversationSelection(id: c1.id)
        viewModel.toggleConversationSelection(id: c2.id)
        viewModel.bulkDelete()

        XCTAssertNil(conversationService.load(id: c1.id))
        XCTAssertNil(conversationService.load(id: c2.id))
        XCTAssertNotNil(conversationService.load(id: c3.id))
        XCTAssertFalse(viewModel.isMultiSelectMode)
    }

    func testBulkMoveToFolder() {
        let folder = ConversationFolder(name: "업무")
        viewModel.addFolder(folder)

        let c1 = Conversation(title: "1")
        let c2 = Conversation(title: "2")
        conversationService.save(conversation: c1)
        conversationService.save(conversation: c2)
        viewModel.loadConversations()

        viewModel.selectedConversationIds = [c1.id, c2.id]
        viewModel.bulkMoveToFolder(folderId: folder.id)

        XCTAssertEqual(conversationService.load(id: c1.id)?.folderId, folder.id)
        XCTAssertEqual(conversationService.load(id: c2.id)?.folderId, folder.id)
    }

    func testBulkSetFavorite() {
        let c1 = Conversation(title: "1")
        let c2 = Conversation(title: "2")
        conversationService.save(conversation: c1)
        conversationService.save(conversation: c2)
        viewModel.loadConversations()

        viewModel.selectedConversationIds = [c1.id, c2.id]
        viewModel.bulkSetFavorite(true)

        XCTAssertTrue(conversationService.load(id: c1.id)!.isFavorite)
        XCTAssertTrue(conversationService.load(id: c2.id)!.isFavorite)
    }

    func testBulkAddTag() {
        let tag = ConversationTag(name: "긴급", color: "red")
        viewModel.addTag(tag)

        let c1 = Conversation(title: "1")
        let c2 = Conversation(title: "2", tags: ["긴급"]) // already has tag
        conversationService.save(conversation: c1)
        conversationService.save(conversation: c2)
        viewModel.loadConversations()

        viewModel.selectedConversationIds = [c1.id, c2.id]
        viewModel.bulkAddTag(tagName: "긴급")

        XCTAssertTrue(conversationService.load(id: c1.id)!.tags.contains("긴급"))
        // Should not duplicate
        XCTAssertEqual(conversationService.load(id: c2.id)!.tags.filter { $0 == "긴급" }.count, 1)
    }

    // MARK: - Load Organization Data

    func testLoadOrganizationData() {
        contextService.conversationTags = [
            ConversationTag(name: "태그1", color: "blue"),
        ]
        contextService.conversationFolders = [
            ConversationFolder(name: "폴더1"),
        ]

        viewModel.loadOrganizationData()

        XCTAssertEqual(viewModel.conversationTags.count, 1)
        XCTAssertEqual(viewModel.conversationFolders.count, 1)
    }
}
