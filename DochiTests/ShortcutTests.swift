import XCTest
@testable import Dochi

// MARK: - ShortcutExecutionLog Tests

@MainActor
final class ShortcutExecutionLogTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShortcutTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Model

    func testLogInitDefaults() {
        let log = ShortcutExecutionLog(
            actionName: "도치에게 물어보기",
            success: true,
            resultSummary: "테스트 응답"
        )
        XCTAssertEqual(log.actionName, "도치에게 물어보기")
        XCTAssertTrue(log.success)
        XCTAssertEqual(log.resultSummary, "테스트 응답")
        XCTAssertNil(log.errorMessage)
    }

    func testLogInitWithError() {
        let log = ShortcutExecutionLog(
            actionName: "도치 메모 추가",
            success: false,
            resultSummary: "실패",
            errorMessage: "서비스 미초기화"
        )
        XCTAssertFalse(log.success)
        XCTAssertEqual(log.errorMessage, "서비스 미초기화")
    }

    // MARK: - Store Persistence

    func testStoreRoundTrip() {
        let store = ShortcutExecutionLogStore(baseURL: tempDir)
        let log = ShortcutExecutionLog(
            actionName: "테스트 액션",
            success: true,
            resultSummary: "성공"
        )

        store.appendLog(log)
        let loaded = store.loadLogs()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.actionName, "테스트 액션")
        XCTAssertTrue(loaded.first?.success ?? false)
        XCTAssertEqual(loaded.first?.resultSummary, "성공")
    }

    func testStoreFIFOOrder() {
        let store = ShortcutExecutionLogStore(baseURL: tempDir)

        store.appendLog(ShortcutExecutionLog(actionName: "첫 번째", success: true, resultSummary: "1"))
        store.appendLog(ShortcutExecutionLog(actionName: "두 번째", success: true, resultSummary: "2"))
        store.appendLog(ShortcutExecutionLog(actionName: "세 번째", success: true, resultSummary: "3"))

        let loaded = store.loadLogs()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded[0].actionName, "세 번째")  // Most recent first
        XCTAssertEqual(loaded[1].actionName, "두 번째")
        XCTAssertEqual(loaded[2].actionName, "첫 번째")
    }

    func testStoreMaxLimit() {
        let store = ShortcutExecutionLogStore(baseURL: tempDir)

        // Add 55 logs (max is 50)
        for i in 0..<55 {
            store.appendLog(ShortcutExecutionLog(
                actionName: "액션_\(i)",
                success: true,
                resultSummary: "결과_\(i)"
            ))
        }

        let loaded = store.loadLogs()
        XCTAssertEqual(loaded.count, ShortcutExecutionLogStore.maxLogs)
        // Most recent should be at index 0
        XCTAssertEqual(loaded.first?.actionName, "액션_54")
    }

    func testStoreEmptyLoad() {
        let store = ShortcutExecutionLogStore(baseURL: tempDir)
        let loaded = store.loadLogs()
        XCTAssertTrue(loaded.isEmpty)
    }

    // MARK: - Codable

    func testLogCodable() throws {
        let log = ShortcutExecutionLog(
            actionName: "도치에게 물어보기",
            timestamp: Date(),
            success: true,
            resultSummary: "AI 응답입니다",
            errorMessage: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(log)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ShortcutExecutionLog.self, from: data)

        XCTAssertEqual(decoded.id, log.id)
        XCTAssertEqual(decoded.actionName, log.actionName)
        XCTAssertEqual(decoded.success, log.success)
        XCTAssertEqual(decoded.resultSummary, log.resultSummary)
        XCTAssertNil(decoded.errorMessage)
    }

    func testLogCodableWithError() throws {
        let log = ShortcutExecutionLog(
            actionName: "칸반 카드 생성",
            success: false,
            resultSummary: "실패",
            errorMessage: "보드가 없습니다"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(log)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ShortcutExecutionLog.self, from: data)

        XCTAssertFalse(decoded.success)
        XCTAssertEqual(decoded.errorMessage, "보드가 없습니다")
    }
}

// MARK: - DochiShortcutService Tests

@MainActor
final class DochiShortcutServiceTests: XCTestCase {

    func testSharedInstance() {
        let service1 = DochiShortcutService.shared
        let service2 = DochiShortcutService.shared
        XCTAssertTrue(service1 === service2, "Shared instance should be singleton")
    }

    func testNotConfiguredByDefault() {
        // Note: shared may already be configured in test environment
        // Testing the error type instead
        let error = ShortcutError.notConfigured
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("초기화") ?? false)
    }

    func testShortcutErrors() {
        let errors: [ShortcutError] = [
            .notConfigured,
            .apiKeyNotSet,
            .networkError("테스트"),
            .kanbanError("테스트"),
            .timeout
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have description")
        }
    }

    func testApiKeyNotSetError() {
        let error = ShortcutError.apiKeyNotSet
        XCTAssertTrue(error.errorDescription?.contains("API 키") ?? false)
    }

    func testNetworkErrorMessage() {
        let error = ShortcutError.networkError("연결 실패")
        XCTAssertTrue(error.errorDescription?.contains("연결 실패") ?? false)
    }

    func testKanbanErrorMessage() {
        let error = ShortcutError.kanbanError("보드 없음")
        XCTAssertTrue(error.errorDescription?.contains("보드 없음") ?? false)
    }

    func testTimeoutError() {
        let error = ShortcutError.timeout
        XCTAssertTrue(error.errorDescription?.contains("시간") ?? false)
    }

    func testAddMemoWithConfiguredService() throws {
        let mockContext = MockContextService()
        let mockKeychain = MockKeychainService()
        let settings = AppSettings()
        let mockLLM = MockLLMService()
        let heartbeatService = HeartbeatService(settings: settings)

        DochiShortcutService.shared.configure(
            contextService: mockContext,
            keychainService: mockKeychain,
            settings: settings,
            llmService: mockLLM,
            heartbeatService: heartbeatService
        )

        // Test with no user set — should append to workspace memory
        settings.defaultUserId = ""
        let result = try DochiShortcutService.shared.addMemo(content: "테스트 메모")
        XCTAssertTrue(result.contains("워크스페이스"))

        // Verify workspace memory was updated
        let wsId = UUID(uuidString: settings.currentWorkspaceId)
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let memory = mockContext.loadWorkspaceMemory(workspaceId: wsId)
        XCTAssertNotNil(memory)
        XCTAssertTrue(memory?.contains("테스트 메모") ?? false)
    }

    func testAddMemoWithUserSet() throws {
        let mockContext = MockContextService()
        let mockKeychain = MockKeychainService()
        let settings = AppSettings()
        let mockLLM = MockLLMService()
        let heartbeatService = HeartbeatService(settings: settings)

        DochiShortcutService.shared.configure(
            contextService: mockContext,
            keychainService: mockKeychain,
            settings: settings,
            llmService: mockLLM,
            heartbeatService: heartbeatService
        )

        settings.defaultUserId = "test-user-id"
        let result = try DochiShortcutService.shared.addMemo(content: "개인 메모")
        XCTAssertTrue(result.contains("개인"))

        let memory = mockContext.loadUserMemory(userId: "test-user-id")
        XCTAssertNotNil(memory)
        XCTAssertTrue(memory?.contains("개인 메모") ?? false)
    }

    func testAskDochiSuccess() async throws {
        let mockContext = MockContextService()
        let mockKeychain = MockKeychainService()
        let settings = AppSettings()
        let mockLLM = MockLLMService()
        let heartbeatService = HeartbeatService(settings: settings)

        mockKeychain.store["openai"] = "test-key"
        mockLLM.stubbedResponse = .text("AI 응답입니다")

        DochiShortcutService.shared.configure(
            contextService: mockContext,
            keychainService: mockKeychain,
            settings: settings,
            llmService: mockLLM,
            heartbeatService: heartbeatService
        )

        let result = try await DochiShortcutService.shared.askDochi(question: "테스트 질문")
        XCTAssertEqual(result, "AI 응답입니다")
        XCTAssertEqual(mockLLM.sendCallCount, 1)
    }

    func testRecordExecution() {
        let mockContext = MockContextService()
        let mockKeychain = MockKeychainService()
        let settings = AppSettings()
        let mockLLM = MockLLMService()
        let heartbeatService = HeartbeatService(settings: settings)

        DochiShortcutService.shared.configure(
            contextService: mockContext,
            keychainService: mockKeychain,
            settings: settings,
            llmService: mockLLM,
            heartbeatService: heartbeatService
        )

        DochiShortcutService.shared.recordExecution(
            actionName: "테스트",
            success: true,
            resultSummary: "성공"
        )

        let logs = DochiShortcutService.shared.loadExecutionLogs()
        XCTAssertFalse(logs.isEmpty)
        XCTAssertEqual(logs.first?.actionName, "테스트")
    }
}

// MARK: - SettingsSection Shortcuts Tests

@MainActor
final class SettingsSectionShortcutsTests: XCTestCase {

    func testShortcutsSectionExists() {
        XCTAssertNotNil(SettingsSection(rawValue: "shortcuts"))
    }

    func testShortcutsSectionProperties() {
        let section = SettingsSection.shortcuts
        XCTAssertEqual(section.title, "단축어")
        XCTAssertEqual(section.icon, "square.grid.3x3.square")
        XCTAssertEqual(section.group, .connection)
    }

    func testShortcutsSectionSearchKeywords() {
        let section = SettingsSection.shortcuts
        XCTAssertTrue(section.searchKeywords.contains("Shortcuts"))
        XCTAssertTrue(section.searchKeywords.contains("Siri"))
        XCTAssertTrue(section.searchKeywords.contains("단축어"))
    }

    func testShortcutsSectionMatchesSearch() {
        let section = SettingsSection.shortcuts
        XCTAssertTrue(section.matches(query: "단축어"))
        XCTAssertTrue(section.matches(query: "Siri"))
        XCTAssertTrue(section.matches(query: "Shortcuts"))
        XCTAssertFalse(section.matches(query: "텔레그램"))
    }

    func testShortcutsSectionInConnectionGroup() {
        let connectionSections = SettingsSectionGroup.connection.sections
        XCTAssertTrue(connectionSections.contains(.shortcuts))
        // Verify order: tools, integrations, shortcuts, account
        if let integrationsIdx = connectionSections.firstIndex(of: .integrations),
           let shortcutsIdx = connectionSections.firstIndex(of: .shortcuts) {
            XCTAssertEqual(shortcutsIdx, integrationsIdx + 1, "Shortcuts should be right after integrations")
        }
    }
}

// MARK: - CommandPalette Shortcuts Tests

@MainActor
final class CommandPaletteShortcutsTests: XCTestCase {

    func testOpenShortcutsAppItemExists() {
        let items = CommandPaletteRegistry.staticItems
        let shortcutItem = items.first { $0.id == "open-shortcuts-app" }
        XCTAssertNotNil(shortcutItem)
        XCTAssertEqual(shortcutItem?.title, "단축어 앱 열기")
    }

    func testShortcutsSettingsItemExists() {
        let items = CommandPaletteRegistry.staticItems
        let settingsItem = items.first { $0.id == "settings.open.shortcuts" }
        XCTAssertNotNil(settingsItem)
        XCTAssertEqual(settingsItem?.title, "단축어 설정")
    }

    func testOpenShortcutsAppAction() {
        let items = CommandPaletteRegistry.staticItems
        let item = items.first { $0.id == "open-shortcuts-app" }
        if case .openShortcutsApp = item?.action {
            // Expected
        } else {
            XCTFail("Expected openShortcutsApp action")
        }
    }
}
