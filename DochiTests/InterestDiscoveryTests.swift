import XCTest
@testable import Dochi

// MARK: - InterestModels Tests

final class InterestModelsTests: XCTestCase {

    func testInterestEntryCodable() throws {
        let entry = InterestEntry(
            topic: "Swift 프로그래밍",
            status: .confirmed,
            confidence: 0.9,
            source: "manual",
            tags: ["개발", "iOS"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(InterestEntry.self, from: data)

        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.topic, "Swift 프로그래밍")
        XCTAssertEqual(decoded.status, .confirmed)
        XCTAssertEqual(decoded.confidence, 0.9)
        XCTAssertEqual(decoded.source, "manual")
        XCTAssertEqual(decoded.tags, ["개발", "iOS"])
    }

    func testInterestProfileCodable() throws {
        var profile = InterestProfile()
        profile.interests = [
            InterestEntry(topic: "Python", status: .confirmed, confidence: 1.0),
            InterestEntry(topic: "데이터 분석", status: .inferred, confidence: 0.6)
        ]
        profile.discoveryMode = .eager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profile)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(InterestProfile.self, from: data)

        XCTAssertEqual(decoded.interests.count, 2)
        XCTAssertEqual(decoded.interests[0].topic, "Python")
        XCTAssertEqual(decoded.interests[1].status, .inferred)
        XCTAssertEqual(decoded.discoveryMode, .eager)
    }

    func testInterestStatusRawValues() {
        XCTAssertEqual(InterestStatus.confirmed.rawValue, "confirmed")
        XCTAssertEqual(InterestStatus.inferred.rawValue, "inferred")
        XCTAssertEqual(InterestStatus.expired.rawValue, "expired")
    }

    func testDiscoveryModeDisplayNames() {
        XCTAssertEqual(DiscoveryMode.auto.displayName, "자동")
        XCTAssertEqual(DiscoveryMode.eager.displayName, "적극")
        XCTAssertEqual(DiscoveryMode.passive.displayName, "수동")
        XCTAssertEqual(DiscoveryMode.manual.displayName, "비활성")
    }

    func testDiscoveryAggressivenessDisplayNames() {
        XCTAssertEqual(DiscoveryAggressiveness.eager.displayName, "적극")
        XCTAssertEqual(DiscoveryAggressiveness.active.displayName, "보통")
        XCTAssertEqual(DiscoveryAggressiveness.passive.displayName, "수동")
    }

    func testInterestEntryDefaults() {
        let entry = InterestEntry(topic: "테스트")
        XCTAssertEqual(entry.status, .inferred)
        XCTAssertEqual(entry.confidence, 0.5)
        XCTAssertEqual(entry.source, "")
        XCTAssertTrue(entry.tags.isEmpty)
    }

    func testInterestProfileDefaults() {
        let profile = InterestProfile()
        XCTAssertTrue(profile.interests.isEmpty)
        XCTAssertNil(profile.lastDiscoveryDate)
        XCTAssertEqual(profile.discoveryMode, .auto)
    }
}

// MARK: - InterestDiscoveryService Tests

@MainActor
final class InterestDiscoveryServiceTests: XCTestCase {

    private var settings: AppSettings!
    private var service: InterestDiscoveryService!

    override func setUp() {
        super.setUp()
        settings = AppSettings()
        settings.interestDiscoveryEnabled = true
        settings.interestDiscoveryMode = DiscoveryMode.auto.rawValue
        settings.interestMinDetectionCount = 3
        settings.interestExpirationDays = 30
        settings.interestIncludeInPrompt = true
        service = InterestDiscoveryService(settings: settings)
    }

    // MARK: - Aggressiveness

    func testAggressivenessAutoMode_ZeroConfirmed() {
        XCTAssertEqual(service.currentAggressiveness, .eager,
                       "With 0 confirmed interests, aggressiveness should be eager")
    }

    func testAggressivenessAutoMode_FewConfirmed() {
        for i in 0..<3 {
            service.addInterest(InterestEntry(topic: "Topic \(i)", status: .confirmed, confidence: 1.0))
        }
        XCTAssertEqual(service.currentAggressiveness, .active,
                       "With 3 confirmed interests, aggressiveness should be active")
    }

    func testAggressivenessAutoMode_ManyConfirmed() {
        for i in 0..<6 {
            service.addInterest(InterestEntry(topic: "Topic \(i)", status: .confirmed, confidence: 1.0))
        }
        XCTAssertEqual(service.currentAggressiveness, .passive,
                       "With 6+ confirmed interests, aggressiveness should be passive")
    }

    func testAggressivenessEagerMode() {
        service.profile.discoveryMode = .eager
        XCTAssertEqual(service.currentAggressiveness, .eager)
    }

    func testAggressivenessPassiveMode() {
        service.profile.discoveryMode = .passive
        XCTAssertEqual(service.currentAggressiveness, .passive)
    }

    func testAggressivenessManualMode() {
        service.profile.discoveryMode = .manual
        XCTAssertEqual(service.currentAggressiveness, .passive)
    }

    // MARK: - CRUD

    func testAddInterest() {
        let entry = InterestEntry(topic: "Swift", status: .confirmed, confidence: 1.0)
        service.addInterest(entry)
        XCTAssertEqual(service.profile.interests.count, 1)
        XCTAssertEqual(service.profile.interests.first?.topic, "Swift")
    }

    func testAddDuplicateInterest_UpdatesExisting() {
        let entry1 = InterestEntry(topic: "Swift", status: .inferred, confidence: 0.5)
        let entry2 = InterestEntry(topic: "swift", status: .inferred, confidence: 0.8)
        service.addInterest(entry1)
        service.addInterest(entry2)

        XCTAssertEqual(service.profile.interests.count, 1,
                       "Duplicate topic should update existing, not add new")
        XCTAssertEqual(service.profile.interests.first?.confidence, 0.8,
                       "Higher confidence should be kept")
    }

    func testUpdateInterest() {
        let entry = InterestEntry(topic: "Python", status: .confirmed, confidence: 1.0, tags: ["개발"])
        service.addInterest(entry)

        service.updateInterest(id: entry.id, topic: "Python 3", tags: ["개발", "데이터"])

        XCTAssertEqual(service.profile.interests.first?.topic, "Python 3")
        XCTAssertEqual(service.profile.interests.first?.tags, ["개발", "데이터"])
    }

    func testConfirmInterest() {
        let entry = InterestEntry(topic: "ML", status: .inferred, confidence: 0.6)
        service.addInterest(entry)

        service.confirmInterest(id: entry.id)

        XCTAssertEqual(service.profile.interests.first?.status, .confirmed)
        XCTAssertEqual(service.profile.interests.first?.confidence, 1.0)
    }

    func testRestoreInterest() {
        let entry = InterestEntry(topic: "ML", status: .expired, confidence: 0.5)
        service.addInterest(entry)

        service.restoreInterest(id: entry.id)

        XCTAssertEqual(service.profile.interests.first?.status, .confirmed)
        XCTAssertEqual(service.profile.interests.first?.confidence, 1.0)
    }

    func testRemoveInterest() {
        let entry = InterestEntry(topic: "ML")
        service.addInterest(entry)

        service.removeInterest(id: entry.id)

        XCTAssertTrue(service.profile.interests.isEmpty)
    }

    // MARK: - Persistence

    func testSaveAndLoadProfile() {
        let userId = "test-user-\(UUID().uuidString)"
        let entry = InterestEntry(topic: "테스트 관심사", status: .confirmed, confidence: 1.0, tags: ["테스트"])
        service.addInterest(entry)

        service.saveProfile(userId: userId)

        // Create a new service and load
        let service2 = InterestDiscoveryService(settings: settings)
        service2.loadProfile(userId: userId)

        XCTAssertEqual(service2.profile.interests.count, 1)
        XCTAssertEqual(service2.profile.interests.first?.topic, "테스트 관심사")
        XCTAssertEqual(service2.profile.interests.first?.status, .confirmed)
        XCTAssertEqual(service2.profile.interests.first?.tags, ["테스트"])

        // Cleanup
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let fileURL = appSupport.appendingPathComponent("Dochi").appendingPathComponent("interests").appendingPathComponent("\(userId).json")
        try? FileManager.default.removeItem(at: fileURL)
    }

    func testLoadNonexistentProfile() {
        service.loadProfile(userId: "nonexistent-\(UUID().uuidString)")
        XCTAssertTrue(service.profile.interests.isEmpty)
    }

    // MARK: - System Prompt

    func testBuildSystemPromptAddition_WithConfirmedInterests() {
        service.addInterest(InterestEntry(topic: "Swift", status: .confirmed, confidence: 1.0))
        service.addInterest(InterestEntry(topic: "데이터 분석", status: .inferred, confidence: 0.7))

        let addition = service.buildDiscoverySystemPromptAddition()
        XCTAssertNotNil(addition)
        XCTAssertTrue(addition!.contains("Swift"))
        XCTAssertTrue(addition!.contains("데이터 분석"))
        XCTAssertTrue(addition!.contains("확인됨"))
        XCTAssertTrue(addition!.contains("추정"))
    }

    func testBuildSystemPromptAddition_Disabled() {
        settings.interestDiscoveryEnabled = false
        let addition = service.buildDiscoverySystemPromptAddition()
        XCTAssertNil(addition)
    }

    func testBuildSystemPromptAddition_PromptDisabled() {
        settings.interestIncludeInPrompt = false
        service.addInterest(InterestEntry(topic: "Swift", status: .confirmed))
        let addition = service.buildDiscoverySystemPromptAddition()
        XCTAssertNil(addition)
    }

    func testBuildSystemPromptAddition_Empty_PassiveMode() {
        // With passive mode and no interests, nothing to add
        service.profile.discoveryMode = .passive

        let addition = service.buildDiscoverySystemPromptAddition()
        XCTAssertNil(addition, "Empty interests in passive mode should return nil")
    }

    func testBuildSystemPromptAddition_IncludesDiscoveryInstructions() {
        // With 0 interests in auto mode, should include eager discovery instructions
        let addition = service.buildDiscoverySystemPromptAddition()
        XCTAssertNotNil(addition, "Eager mode with no interests should include discovery instructions")
        XCTAssertTrue(addition!.contains("관심사 발굴"))
    }

    // MARK: - Expiration

    func testCheckExpirations() {
        settings.interestExpirationDays = 7

        let oldDate = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        var entry = InterestEntry(topic: "Old interest", status: .confirmed, confidence: 1.0)
        entry.lastSeen = oldDate
        service.addInterest(entry)

        var recentEntry = InterestEntry(topic: "Recent interest", status: .confirmed, confidence: 1.0)
        recentEntry.lastSeen = Date()
        service.addInterest(recentEntry)

        service.checkExpirations()

        let oldResult = service.profile.interests.first { $0.topic == "Old interest" }
        let recentResult = service.profile.interests.first { $0.topic == "Recent interest" }

        XCTAssertEqual(oldResult?.status, .expired, "Old interest should be expired")
        XCTAssertEqual(recentResult?.status, .confirmed, "Recent interest should still be confirmed")
    }

    // MARK: - Message Analysis

    func testAnalyzeMessage_DisabledSkips() {
        settings.interestDiscoveryEnabled = false
        let convId = UUID()
        // Call multiple times - should not crash or add interests
        for _ in 0..<5 {
            service.analyzeMessage("관심있는 주제를 배워보고 싶어", conversationId: convId)
        }
        XCTAssertTrue(service.profile.interests.isEmpty,
                       "Should not analyze when disabled")
    }

    func testAnalyzeMessage_ManualModeSkips() {
        settings.interestDiscoveryMode = DiscoveryMode.manual.rawValue
        service.profile.discoveryMode = .manual
        let convId = UUID()
        for _ in 0..<5 {
            service.analyzeMessage("관심있는 Python 배워볼까", conversationId: convId)
        }
        XCTAssertTrue(service.profile.interests.isEmpty,
                       "Should not analyze in manual mode")
    }

    // MARK: - Memory Sync

    func testSyncToMemory() {
        let mockContext = MockContextService()
        service.addInterest(InterestEntry(topic: "Swift", status: .confirmed, confidence: 1.0))
        service.addInterest(InterestEntry(topic: "ML", status: .inferred, confidence: 0.7))

        service.syncToMemory(contextService: mockContext, userId: "test-user")

        let savedMemory = mockContext.userMemory["test-user"] ?? ""
        XCTAssertTrue(savedMemory.contains("관심사"))
        XCTAssertTrue(savedMemory.contains("Swift"))
        XCTAssertTrue(savedMemory.contains("ML"))
    }

    func testSyncToMemory_EmptyProfile() {
        let mockContext = MockContextService()
        service.syncToMemory(contextService: mockContext, userId: "test-user")

        XCTAssertNil(mockContext.userMemory["test-user"],
                     "Should not sync empty profile")
    }
}

// MARK: - Settings Section Interest Tests

final class InterestSettingsSectionTests: XCTestCase {

    func testInterestSectionExists() {
        let section = SettingsSection.interest
        XCTAssertEqual(section.rawValue, "interest")
        XCTAssertEqual(section.title, "관심사")
        XCTAssertEqual(section.icon, "sparkle.magnifyingglass")
        XCTAssertEqual(section.group, .people)
    }

    func testInterestSectionSearch() {
        XCTAssertTrue(SettingsSection.interest.matches(query: "관심사"))
        XCTAssertTrue(SettingsSection.interest.matches(query: "interest"))
        XCTAssertTrue(SettingsSection.interest.matches(query: "발굴"))
        XCTAssertTrue(SettingsSection.interest.matches(query: "discovery"))
    }

    func testPeopleGroupIncludesInterest() {
        let sections = SettingsSectionGroup.people.sections
        XCTAssertTrue(sections.contains(.interest))
        XCTAssertEqual(sections.count, 3, "People group should have family, agent, interest")
    }
}
