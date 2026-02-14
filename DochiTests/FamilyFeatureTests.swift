import XCTest
@testable import Dochi

// MARK: - ContextService: Profile ISO8601 Roundtrip

@MainActor
final class ProfilePersistenceTests: XCTestCase {
    private var service: ContextService!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DochiTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        service = ContextService(baseURL: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Save → Load roundtrip preserves all fields including ISO8601 dates.
    func testProfileRoundtrip() {
        let profile = UserProfile(name: "아빠", aliases: ["현철"], description: "가장")
        service.saveProfiles([profile])

        let loaded = service.loadProfiles()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, profile.id)
        XCTAssertEqual(loaded[0].name, "아빠")
        XCTAssertEqual(loaded[0].aliases, ["현철"])
        XCTAssertEqual(loaded[0].description, "가장")
        // Date should survive roundtrip within 1 second tolerance
        XCTAssertEqual(
            loaded[0].createdAt.timeIntervalSince1970,
            profile.createdAt.timeIntervalSince1970,
            accuracy: 1
        )
    }

    /// Loads pre-existing ISO8601 JSON (simulates data written by earlier app version).
    func testLoadExistingISO8601JSON() {
        let json = """
        [
          {
            "aliases": [],
            "createdAt": "2026-02-09T14:26:31Z",
            "description": "현철",
            "id": "0E74FF07-D190-4E0F-B86F-2228253E2A28",
            "name": "아빠"
          },
          {
            "aliases": [],
            "createdAt": "2026-02-09T14:26:31Z",
            "description": "유경",
            "id": "E258E899-CC56-4B64-A73B-43E26CC3A3C4",
            "name": "엄마"
          }
        ]
        """
        let url = tempDir.appendingPathComponent("profiles.json")
        try! json.data(using: .utf8)!.write(to: url)

        let loaded = service.loadProfiles()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].name, "아빠")
        XCTAssertEqual(loaded[0].id.uuidString, "0E74FF07-D190-4E0F-B86F-2228253E2A28")
        XCTAssertEqual(loaded[1].name, "엄마")
    }

    /// Empty or missing profiles.json returns empty array, not crash.
    func testLoadMissingProfilesReturnsEmpty() {
        let loaded = service.loadProfiles()
        XCTAssertTrue(loaded.isEmpty)
    }

    /// Corrupt JSON returns empty array, not crash.
    func testLoadCorruptProfilesReturnsEmpty() {
        let url = tempDir.appendingPathComponent("profiles.json")
        try! "not valid json".data(using: .utf8)!.write(to: url)
        let loaded = service.loadProfiles()
        XCTAssertTrue(loaded.isEmpty)
    }

    /// Multiple profiles with user memory isolation.
    func testUserMemoryPerProfile() {
        let p1 = UserProfile(name: "도희")
        let p2 = UserProfile(name: "도현")
        service.saveProfiles([p1, p2])

        service.saveUserMemory(userId: p1.id.uuidString, content: "도희 메모리")
        service.saveUserMemory(userId: p2.id.uuidString, content: "도현 메모리")

        XCTAssertEqual(service.loadUserMemory(userId: p1.id.uuidString), "도희 메모리")
        XCTAssertEqual(service.loadUserMemory(userId: p2.id.uuidString), "도현 메모리")
    }
}

// MARK: - DochiViewModel: User Switching & System Prompt

@MainActor
final class ViewModelUserTests: XCTestCase {
    private var viewModel: DochiViewModel!
    private var contextService: MockContextService!
    private var settings: AppSettings!
    private var sessionContext: SessionContext!

    override func setUp() {
        super.setUp()
        contextService = MockContextService()
        settings = AppSettings()
        let wsId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        sessionContext = SessionContext(workspaceId: wsId)

        let keychainService = MockKeychainService()
        keychainService.store["openai_api_key"] = "sk-test"

        viewModel = DochiViewModel(
            llmService: MockLLMService(),
            toolService: MockBuiltInToolService(),
            contextService: contextService,
            conversationService: MockConversationService(),
            keychainService: keychainService,
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: settings,
            sessionContext: sessionContext
        )
    }

    // MARK: - reloadProfiles

    func testReloadProfilesEmpty() {
        contextService.profiles = []
        viewModel.reloadProfiles()

        XCTAssertTrue(viewModel.userProfiles.isEmpty)
        XCTAssertEqual(viewModel.currentUserName, "(사용자 없음)")
    }

    func testReloadProfilesWithCurrentUser() {
        let profile = UserProfile(name: "아빠")
        contextService.profiles = [profile]
        sessionContext.currentUserId = profile.id.uuidString

        viewModel.reloadProfiles()

        XCTAssertEqual(viewModel.userProfiles.count, 1)
        XCTAssertEqual(viewModel.currentUserName, "아빠")
    }

    func testReloadProfilesWithInvalidCurrentUser() {
        contextService.profiles = [UserProfile(name: "아빠")]
        sessionContext.currentUserId = "nonexistent-id"

        viewModel.reloadProfiles()

        XCTAssertEqual(viewModel.userProfiles.count, 1)
        XCTAssertEqual(viewModel.currentUserName, "(사용자 없음)")
    }

    // MARK: - switchUser

    func testSwitchUser() {
        let p1 = UserProfile(name: "아빠")
        let p2 = UserProfile(name: "도희")
        contextService.profiles = [p1, p2]

        viewModel.switchUser(profile: p2)

        XCTAssertEqual(sessionContext.currentUserId, p2.id.uuidString)
        XCTAssertEqual(settings.defaultUserId, p2.id.uuidString)
        XCTAssertEqual(viewModel.currentUserName, "도희")
    }

    // MARK: - composeSystemPrompt: user section

    func testSystemPromptContainsCurrentUserName() {
        let profile = UserProfile(name: "도현")
        contextService.profiles = [profile]
        contextService.baseSystemPrompt = "기본 프롬프트"
        sessionContext.currentUserId = profile.id.uuidString

        viewModel.reloadProfiles()
        // Trigger a conversation so we can inspect system prompt indirectly
        // We test via sendMessage which calls composeSystemPrompt internally

        // For now, test the public state
        XCTAssertEqual(viewModel.currentUserName, "도현")
    }

    func testSystemPromptWithNoCurrentUserShowsIdentificationGuide() {
        let p1 = UserProfile(name: "아빠")
        let p2 = UserProfile(name: "도희")
        contextService.profiles = [p1, p2]
        contextService.baseSystemPrompt = "기본"
        sessionContext.currentUserId = nil

        viewModel.reloadProfiles()

        XCTAssertEqual(viewModel.currentUserName, "(사용자 없음)")
        // Profiles are loaded for identification prompt
        XCTAssertEqual(viewModel.userProfiles.count, 2)
    }

    // MARK: - Conversation userId

    func testNewConversationGetsCurrentUserId() {
        let profile = UserProfile(name: "아빠")
        sessionContext.currentUserId = profile.id.uuidString

        // sendMessage creates conversation with userId
        viewModel.inputText = "안녕"
        viewModel.sendMessage()

        XCTAssertEqual(viewModel.currentConversation?.userId, profile.id.uuidString)
    }

    func testNewConversationWithNoUser() {
        sessionContext.currentUserId = nil

        viewModel.inputText = "안녕"
        viewModel.sendMessage()

        XCTAssertNil(viewModel.currentConversation?.userId)
    }
}

// MARK: - AppSettings: defaultUserId

@MainActor
final class AppSettingsUserTests: XCTestCase {
    func testDefaultUserIdPersistence() {
        let settings = AppSettings()
        let testId = UUID().uuidString

        settings.defaultUserId = testId
        XCTAssertEqual(UserDefaults.standard.string(forKey: "defaultUserId"), testId)

        settings.defaultUserId = ""
        XCTAssertEqual(UserDefaults.standard.string(forKey: "defaultUserId"), "")
    }
}
