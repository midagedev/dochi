import XCTest
@testable import Dochi

@MainActor
final class FeedbackModelTests: XCTestCase {

    // MARK: - FeedbackRating

    func testFeedbackRatingCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let positive = FeedbackRating.positive
        let data = try encoder.encode(positive)
        let decoded = try decoder.decode(FeedbackRating.self, from: data)
        XCTAssertEqual(decoded, .positive)

        let negative = FeedbackRating.negative
        let data2 = try encoder.encode(negative)
        let decoded2 = try decoder.decode(FeedbackRating.self, from: data2)
        XCTAssertEqual(decoded2, .negative)
    }

    // MARK: - FeedbackCategory

    func testFeedbackCategoryAllCases() {
        XCTAssertEqual(FeedbackCategory.allCases.count, 7)
    }

    func testFeedbackCategoryDisplayNames() {
        XCTAssertEqual(FeedbackCategory.inaccurate.displayName, "부정확한 정보")
        XCTAssertEqual(FeedbackCategory.unhelpful.displayName, "도움이 안 됨")
        XCTAssertEqual(FeedbackCategory.tooLong.displayName, "너무 길어요")
        XCTAssertEqual(FeedbackCategory.tooShort.displayName, "너무 짧아요")
        XCTAssertEqual(FeedbackCategory.missedContext.displayName, "맥락을 놓침")
        XCTAssertEqual(FeedbackCategory.wrongTone.displayName, "어조가 맞지 않음")
        XCTAssertEqual(FeedbackCategory.other.displayName, "기타")
    }

    func testFeedbackCategoryCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for category in FeedbackCategory.allCases {
            let data = try encoder.encode(category)
            let decoded = try decoder.decode(FeedbackCategory.self, from: data)
            XCTAssertEqual(decoded, category)
        }
    }

    // MARK: - FeedbackEntry

    func testFeedbackEntryInit() {
        let msgId = UUID()
        let convId = UUID()
        let entry = FeedbackEntry(
            messageId: msgId,
            conversationId: convId,
            rating: .positive,
            agentName: "도치",
            provider: "openai",
            model: "gpt-4o"
        )
        XCTAssertEqual(entry.messageId, msgId)
        XCTAssertEqual(entry.conversationId, convId)
        XCTAssertEqual(entry.rating, .positive)
        XCTAssertNil(entry.category)
        XCTAssertNil(entry.comment)
        XCTAssertEqual(entry.agentName, "도치")
        XCTAssertEqual(entry.provider, "openai")
        XCTAssertEqual(entry.model, "gpt-4o")
    }

    func testFeedbackEntryWithCategoryAndComment() {
        let entry = FeedbackEntry(
            messageId: UUID(),
            conversationId: UUID(),
            rating: .negative,
            category: .tooLong,
            comment: "응답이 너무 깁니다",
            agentName: "도치",
            provider: "anthropic",
            model: "claude-3-5-sonnet"
        )
        XCTAssertEqual(entry.rating, .negative)
        XCTAssertEqual(entry.category, .tooLong)
        XCTAssertEqual(entry.comment, "응답이 너무 깁니다")
    }

    func testFeedbackEntryRoundTrip() throws {
        let entry = FeedbackEntry(
            messageId: UUID(),
            conversationId: UUID(),
            rating: .negative,
            category: .missedContext,
            comment: "테스트 코멘트",
            agentName: "도치",
            provider: "openai",
            model: "gpt-4o"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(FeedbackEntry.self, from: data)

        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.messageId, entry.messageId)
        XCTAssertEqual(decoded.rating, .negative)
        XCTAssertEqual(decoded.category, .missedContext)
        XCTAssertEqual(decoded.comment, "테스트 코멘트")
    }

    // MARK: - ModelSatisfaction

    func testModelSatisfactionRate() {
        let sat = ModelSatisfaction(model: "gpt-4o", provider: "openai", totalCount: 10, positiveCount: 7)
        XCTAssertEqual(sat.satisfactionRate, 0.7, accuracy: 0.001)
        XCTAssertFalse(sat.isWarning)
    }

    func testModelSatisfactionWarning() {
        let sat = ModelSatisfaction(model: "gpt-4o", provider: "openai", totalCount: 10, positiveCount: 5)
        XCTAssertEqual(sat.satisfactionRate, 0.5, accuracy: 0.001)
        XCTAssertTrue(sat.isWarning)
    }

    func testModelSatisfactionNoWarningWhenFewFeedbacks() {
        let sat = ModelSatisfaction(model: "gpt-4o", provider: "openai", totalCount: 5, positiveCount: 1)
        XCTAssertEqual(sat.satisfactionRate, 0.2, accuracy: 0.001)
        XCTAssertFalse(sat.isWarning) // < 10 feedbacks
    }

    func testModelSatisfactionZeroCount() {
        let sat = ModelSatisfaction(model: "gpt-4o", provider: "openai", totalCount: 0, positiveCount: 0)
        XCTAssertEqual(sat.satisfactionRate, 0.0)
        XCTAssertFalse(sat.isWarning)
    }

    // MARK: - AgentSatisfaction

    func testAgentSatisfactionRate() {
        let sat = AgentSatisfaction(agentName: "도치", totalCount: 20, positiveCount: 18)
        XCTAssertEqual(sat.satisfactionRate, 0.9, accuracy: 0.001)
    }

    func testAgentSatisfactionZeroCount() {
        let sat = AgentSatisfaction(agentName: "도치", totalCount: 0, positiveCount: 0)
        XCTAssertEqual(sat.satisfactionRate, 0.0)
    }

    // MARK: - CategoryCount

    func testCategoryCount() {
        let cc = CategoryCount(category: .tooLong, count: 5)
        XCTAssertEqual(cc.id, "tooLong")
        XCTAssertEqual(cc.count, 5)
    }

    // MARK: - Message feedbackRating backward compat

    func testMessageDecodesWithoutFeedbackRating() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "role": "assistant",
            "content": "안녕하세요",
            "timestamp": "2025-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(Message.self, from: Data(json.utf8))
        XCTAssertNil(message.feedbackRating)
    }

    func testMessageDecodesWithFeedbackRating() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "role": "assistant",
            "content": "안녕하세요",
            "timestamp": "2025-01-01T00:00:00Z",
            "feedbackRating": "positive"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(Message.self, from: Data(json.utf8))
        XCTAssertEqual(message.feedbackRating, .positive)
    }

    func testMessageFeedbackRatingRoundTrip() throws {
        var message = Message(role: .assistant, content: "테스트")
        message.feedbackRating = .negative

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(message)
        let decoded = try decoder.decode(Message.self, from: data)
        XCTAssertEqual(decoded.feedbackRating, .negative)
    }
}

// MARK: - FeedbackStore Tests

@MainActor
final class FeedbackStoreTests: XCTestCase {

    private var tempDir: URL!
    private var tempFileURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempFileURL = tempDir.appendingPathComponent("feedback.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeEntry(
        messageId: UUID = UUID(),
        conversationId: UUID = UUID(),
        rating: FeedbackRating = .positive,
        category: FeedbackCategory? = nil,
        comment: String? = nil,
        agentName: String = "도치",
        provider: String = "openai",
        model: String = "gpt-4o"
    ) -> FeedbackEntry {
        FeedbackEntry(
            messageId: messageId,
            conversationId: conversationId,
            rating: rating,
            category: category,
            comment: comment,
            agentName: agentName,
            provider: provider,
            model: model
        )
    }

    // MARK: - Add/Remove

    func testAddEntry() {
        let store = FeedbackStore(fileURL: tempFileURL)
        let entry = makeEntry()
        store.add(entry)
        XCTAssertEqual(store.entries.count, 1)
    }

    func testAddReplacesSameMessageId() {
        let store = FeedbackStore(fileURL: tempFileURL)
        let msgId = UUID()
        store.add(makeEntry(messageId: msgId, rating: .positive))
        store.add(makeEntry(messageId: msgId, rating: .negative))
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.rating, .negative)
    }

    func testRemoveEntry() {
        let store = FeedbackStore(fileURL: tempFileURL)
        let msgId = UUID()
        store.add(makeEntry(messageId: msgId))
        store.remove(messageId: msgId)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testRemoveNonExistentEntry() {
        let store = FeedbackStore(fileURL: tempFileURL)
        store.remove(messageId: UUID())
        XCTAssertTrue(store.entries.isEmpty)
    }

    // MARK: - Rating Lookup

    func testRatingForExistingMessage() {
        let store = FeedbackStore(fileURL: tempFileURL)
        let msgId = UUID()
        store.add(makeEntry(messageId: msgId, rating: .positive))
        XCTAssertEqual(store.rating(for: msgId), .positive)
    }

    func testRatingForNonExistentMessage() {
        let store = FeedbackStore(fileURL: tempFileURL)
        XCTAssertNil(store.rating(for: UUID()))
    }

    // MARK: - FIFO

    func testFIFOMaxEntries() {
        let store = FeedbackStore(fileURL: tempFileURL)
        for _ in 0..<1005 {
            store.add(makeEntry())
        }
        XCTAssertEqual(store.entries.count, 1000)
    }

    // MARK: - Satisfaction Rate

    func testSatisfactionRateOverall() {
        let store = FeedbackStore(fileURL: tempFileURL)
        store.add(makeEntry(rating: .positive))
        store.add(makeEntry(rating: .positive))
        store.add(makeEntry(rating: .negative))
        XCTAssertEqual(store.satisfactionRate(model: nil, agent: nil), 2.0 / 3.0, accuracy: 0.01)
    }

    func testSatisfactionRateByModel() {
        let store = FeedbackStore(fileURL: tempFileURL)
        store.add(makeEntry(rating: .positive, model: "gpt-4o"))
        store.add(makeEntry(rating: .negative, model: "gpt-4o"))
        store.add(makeEntry(rating: .positive, model: "claude-3"))
        XCTAssertEqual(store.satisfactionRate(model: "gpt-4o", agent: nil), 0.5, accuracy: 0.01)
        XCTAssertEqual(store.satisfactionRate(model: "claude-3", agent: nil), 1.0, accuracy: 0.01)
    }

    func testSatisfactionRateByAgent() {
        let store = FeedbackStore(fileURL: tempFileURL)
        store.add(makeEntry(rating: .positive, agentName: "도치"))
        store.add(makeEntry(rating: .negative, agentName: "도치"))
        store.add(makeEntry(rating: .positive, agentName: "비서"))
        XCTAssertEqual(store.satisfactionRate(model: nil, agent: "도치"), 0.5, accuracy: 0.01)
        XCTAssertEqual(store.satisfactionRate(model: nil, agent: "비서"), 1.0, accuracy: 0.01)
    }

    func testSatisfactionRateEmpty() {
        let store = FeedbackStore(fileURL: tempFileURL)
        XCTAssertEqual(store.satisfactionRate(model: nil, agent: nil), 0.0)
    }

    // MARK: - Recent Negative

    func testRecentNegative() {
        let store = FeedbackStore(fileURL: tempFileURL)
        store.add(makeEntry(rating: .positive))
        store.add(makeEntry(rating: .negative))
        store.add(makeEntry(rating: .negative))
        let recent = store.recentNegative(limit: 10)
        XCTAssertEqual(recent.count, 2)
        XCTAssertTrue(recent.allSatisfy { $0.rating == .negative })
    }

    func testRecentNegativeLimit() {
        let store = FeedbackStore(fileURL: tempFileURL)
        for _ in 0..<20 {
            store.add(makeEntry(rating: .negative))
        }
        let recent = store.recentNegative(limit: 5)
        XCTAssertEqual(recent.count, 5)
    }

    // MARK: - Model Breakdown

    func testModelBreakdown() {
        let store = FeedbackStore(fileURL: tempFileURL)
        store.add(makeEntry(rating: .positive, model: "gpt-4o"))
        store.add(makeEntry(rating: .negative, model: "gpt-4o"))
        store.add(makeEntry(rating: .positive, model: "claude-3"))
        let breakdown = store.modelBreakdown()
        XCTAssertEqual(breakdown.count, 2)
        let gpt = breakdown.first(where: { $0.model == "gpt-4o" })
        XCTAssertEqual(gpt?.totalCount, 2)
        XCTAssertEqual(gpt?.positiveCount, 1)
    }

    // MARK: - Agent Breakdown

    func testAgentBreakdown() {
        let store = FeedbackStore(fileURL: tempFileURL)
        store.add(makeEntry(rating: .positive, agentName: "도치"))
        store.add(makeEntry(rating: .negative, agentName: "도치"))
        store.add(makeEntry(rating: .positive, agentName: "비서"))
        let breakdown = store.agentBreakdown()
        XCTAssertEqual(breakdown.count, 2)
    }

    // MARK: - Category Distribution

    func testCategoryDistribution() {
        let store = FeedbackStore(fileURL: tempFileURL)
        store.add(makeEntry(rating: .negative, category: .tooLong))
        store.add(makeEntry(rating: .negative, category: .tooLong))
        store.add(makeEntry(rating: .negative, category: .inaccurate))
        store.add(makeEntry(rating: .positive)) // should not appear
        let dist = store.categoryDistribution()
        XCTAssertEqual(dist.count, 2)
        let tooLong = dist.first(where: { $0.category == .tooLong })
        XCTAssertEqual(tooLong?.count, 2)
    }

    func testCategoryDistributionExcludesNilCategory() {
        let store = FeedbackStore(fileURL: tempFileURL)
        store.add(makeEntry(rating: .negative, category: nil))
        let dist = store.categoryDistribution()
        XCTAssertTrue(dist.isEmpty)
    }

    // MARK: - Persistence

    func testSaveAndLoad() {
        let store = FeedbackStore(fileURL: tempFileURL)
        let msgId = UUID()
        store.add(makeEntry(messageId: msgId, rating: .positive, category: .other, comment: "좋아요"))
        store.save() // Force immediate save

        let store2 = FeedbackStore(fileURL: tempFileURL)
        XCTAssertEqual(store2.entries.count, 1)
        XCTAssertEqual(store2.entries.first?.messageId, msgId)
        XCTAssertEqual(store2.entries.first?.rating, .positive)
        XCTAssertEqual(store2.entries.first?.category, .other)
        XCTAssertEqual(store2.entries.first?.comment, "좋아요")
    }

    func testLoadFromEmptyFile() {
        let store = FeedbackStore(fileURL: tempFileURL)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testLoadFromCorruptFile() throws {
        try "invalid json".write(to: tempFileURL, atomically: true, encoding: .utf8)
        let store = FeedbackStore(fileURL: tempFileURL)
        XCTAssertTrue(store.entries.isEmpty) // Should not crash
    }
}

// MARK: - MockFeedbackStore Tests

@MainActor
final class MockFeedbackStoreTests: XCTestCase {

    func testMockAdd() {
        let mock = MockFeedbackStore()
        let entry = FeedbackEntry(
            messageId: UUID(),
            conversationId: UUID(),
            rating: .positive,
            agentName: "도치",
            provider: "openai",
            model: "gpt-4o"
        )
        mock.add(entry)
        XCTAssertEqual(mock.addCallCount, 1)
        XCTAssertEqual(mock.entries.count, 1)
    }

    func testMockRemove() {
        let mock = MockFeedbackStore()
        let msgId = UUID()
        mock.add(FeedbackEntry(messageId: msgId, conversationId: UUID(), rating: .positive, agentName: "도치", provider: "openai", model: "gpt-4o"))
        mock.remove(messageId: msgId)
        XCTAssertEqual(mock.removeCallCount, 1)
        XCTAssertTrue(mock.entries.isEmpty)
    }

    func testMockRating() {
        let mock = MockFeedbackStore()
        let msgId = UUID()
        XCTAssertNil(mock.rating(for: msgId))
        mock.add(FeedbackEntry(messageId: msgId, conversationId: UUID(), rating: .negative, agentName: "도치", provider: "openai", model: "gpt-4o"))
        XCTAssertEqual(mock.rating(for: msgId), .negative)
    }

    func testMockSatisfactionRate() {
        let mock = MockFeedbackStore()
        mock.add(FeedbackEntry(messageId: UUID(), conversationId: UUID(), rating: .positive, agentName: "도치", provider: "openai", model: "gpt-4o"))
        mock.add(FeedbackEntry(messageId: UUID(), conversationId: UUID(), rating: .negative, agentName: "도치", provider: "openai", model: "gpt-4o"))
        XCTAssertEqual(mock.satisfactionRate(model: nil, agent: nil), 0.5, accuracy: 0.01)
    }
}

// MARK: - SettingsSection Tests

@MainActor
final class FeedbackSettingsSectionTests: XCTestCase {

    func testFeedbackSectionExists() {
        let section = SettingsSection.feedback
        XCTAssertEqual(section.rawValue, "feedback")
        XCTAssertEqual(section.title, "피드백 통계")
        XCTAssertEqual(section.icon, "chart.line.uptrend.xyaxis")
        XCTAssertEqual(section.group, .ai)
    }

    func testFeedbackSearchKeywords() {
        let section = SettingsSection.feedback
        XCTAssertTrue(section.matches(query: "피드백"))
        XCTAssertTrue(section.matches(query: "만족도"))
        XCTAssertTrue(section.matches(query: "feedback"))
        XCTAssertTrue(section.matches(query: "좋아요"))
        XCTAssertTrue(section.matches(query: "싫어요"))
        XCTAssertFalse(section.matches(query: "텔레그램"))
    }

    func testAIGroupContainsFeedback() {
        let aiSections = SettingsSectionGroup.ai.sections
        XCTAssertTrue(aiSections.contains(.feedback))
    }
}
