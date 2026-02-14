import XCTest
@testable import Dochi

@MainActor
final class SlackServiceTests: XCTestCase {

    // MARK: - SlackUser Model

    func testSlackUserCodable() throws {
        let user = SlackUser(id: "U12345", name: "dochi-bot", isBot: true)
        let data = try JSONEncoder().encode(user)
        let decoded = try JSONDecoder().decode(SlackUser.self, from: data)
        XCTAssertEqual(decoded.id, "U12345")
        XCTAssertEqual(decoded.name, "dochi-bot")
        XCTAssertTrue(decoded.isBot)
    }

    func testSlackUserCodingKeys() throws {
        let json = """
        {"id":"U99","name":"bot","is_bot":false}
        """.data(using: .utf8)!
        let user = try JSONDecoder().decode(SlackUser.self, from: json)
        XCTAssertEqual(user.id, "U99")
        XCTAssertFalse(user.isBot)
    }

    // MARK: - SlackMessage Model

    func testSlackMessageCodable() throws {
        let msg = SlackMessage(
            channelId: "C123",
            userId: "U456",
            text: "안녕하세요",
            threadTs: "1234567890.123456",
            ts: "1234567890.654321",
            isMention: true
        )
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(SlackMessage.self, from: data)
        XCTAssertEqual(decoded.channelId, "C123")
        XCTAssertEqual(decoded.userId, "U456")
        XCTAssertEqual(decoded.text, "안녕하세요")
        XCTAssertEqual(decoded.threadTs, "1234567890.123456")
        XCTAssertTrue(decoded.isMention)
    }

    func testSlackMessageNilThread() throws {
        let msg = SlackMessage(
            channelId: "C123",
            userId: nil,
            text: "hello",
            threadTs: nil,
            ts: "123.456",
            isMention: false
        )
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(SlackMessage.self, from: data)
        XCTAssertNil(decoded.userId)
        XCTAssertNil(decoded.threadTs)
        XCTAssertFalse(decoded.isMention)
    }

    // MARK: - SlackChannel Model

    func testSlackChannelCodable() throws {
        let ch = SlackChannel(id: "C100", name: "general", isDM: false)
        let data = try JSONEncoder().encode(ch)
        let decoded = try JSONDecoder().decode(SlackChannel.self, from: data)
        XCTAssertEqual(decoded.id, "C100")
        XCTAssertEqual(decoded.name, "general")
        XCTAssertFalse(decoded.isDM)
    }

    func testSlackChannelDM() throws {
        let ch = SlackChannel(id: "D200", name: "dm-user", isDM: true)
        XCTAssertTrue(ch.isDM)
    }

    // MARK: - SlackChatMapping Model

    func testChatMappingInit() {
        let mapping = SlackChatMapping(channelId: "C123", label: "#general")
        XCTAssertEqual(mapping.id, "C123")
        XCTAssertEqual(mapping.channelId, "C123")
        XCTAssertEqual(mapping.label, "#general")
        XCTAssertTrue(mapping.enabled)
        XCTAssertNil(mapping.workspaceId)
    }

    func testChatMappingCodable() throws {
        let wsId = UUID()
        let mapping = SlackChatMapping(
            channelId: "C456",
            workspaceId: wsId,
            label: "@user",
            enabled: false
        )
        let data = try JSONEncoder().encode(mapping)
        let decoded = try JSONDecoder().decode(SlackChatMapping.self, from: data)
        XCTAssertEqual(decoded.channelId, "C456")
        XCTAssertEqual(decoded.workspaceId, wsId)
        XCTAssertEqual(decoded.label, "@user")
        XCTAssertFalse(decoded.enabled)
    }

    // MARK: - MockSlackService

    func testMockConnect() async throws {
        let slack = MockSlackService()
        XCTAssertFalse(slack.isConnected)
        try await slack.connect(botToken: "xoxb-test", appToken: "xapp-test")
        XCTAssertTrue(slack.isConnected)
        XCTAssertEqual(slack.connectCalls.count, 1)
        XCTAssertEqual(slack.connectCalls[0].botToken, "xoxb-test")
    }

    func testMockDisconnect() async throws {
        let slack = MockSlackService()
        try await slack.connect(botToken: "xoxb", appToken: "xapp")
        slack.disconnect()
        XCTAssertFalse(slack.isConnected)
    }

    func testMockSendMessage() async throws {
        let slack = MockSlackService()
        let ts = try await slack.sendMessage(channelId: "C123", text: "hello", threadTs: nil)
        XCTAssertEqual(ts, "1000")
        XCTAssertEqual(slack.sentMessages.count, 1)
        XCTAssertEqual(slack.sentMessages[0].text, "hello")
        XCTAssertNil(slack.sentMessages[0].threadTs)
    }

    func testMockSendMessageIncrementsTs() async throws {
        let slack = MockSlackService()
        let ts1 = try await slack.sendMessage(channelId: "C1", text: "a", threadTs: nil)
        let ts2 = try await slack.sendMessage(channelId: "C1", text: "b", threadTs: nil)
        XCTAssertNotEqual(ts1, ts2)
    }

    func testMockSendMessageWithThread() async throws {
        let slack = MockSlackService()
        _ = try await slack.sendMessage(channelId: "C1", text: "reply", threadTs: "999.000")
        XCTAssertEqual(slack.sentMessages[0].threadTs, "999.000")
    }

    func testMockUpdateMessage() async throws {
        let slack = MockSlackService()
        try await slack.updateMessage(channelId: "C1", ts: "100.000", text: "edited")
        XCTAssertEqual(slack.updatedMessages.count, 1)
        XCTAssertEqual(slack.updatedMessages[0].text, "edited")
    }

    func testMockAuthTest() async throws {
        let slack = MockSlackService()
        let user = try await slack.authTest(botToken: "xoxb-test")
        XCTAssertTrue(user.isBot)
        XCTAssertEqual(user.name, "test-bot")
    }

    func testMockConformsToProtocol() {
        let slack: SlackServiceProtocol = MockSlackService()
        XCTAssertFalse(slack.isConnected)
    }

    func testMockOnMessageCallback() async throws {
        let slack = MockSlackService()
        var received: SlackMessage?
        slack.onMessage = { msg in
            received = msg
        }

        let msg = SlackMessage(
            channelId: "C1",
            userId: "U1",
            text: "test",
            threadTs: nil,
            ts: "123.456",
            isMention: false
        )
        slack.onMessage?(msg)
        XCTAssertEqual(received?.text, "test")
    }

    // MARK: - Clean Mentions

    func testCleanMentionsRemovesBotMention() {
        let cleaned = SlackService.cleanMentions("<@U123BOT> 안녕하세요")
        XCTAssertEqual(cleaned, "안녕하세요")
    }

    func testCleanMentionsRemovesMultiple() {
        let cleaned = SlackService.cleanMentions("<@U111> <@U222> 코드 리뷰 부탁")
        XCTAssertEqual(cleaned, "코드 리뷰 부탁")
    }

    func testCleanMentionsNoMention() {
        let cleaned = SlackService.cleanMentions("그냥 텍스트")
        XCTAssertEqual(cleaned, "그냥 텍스트")
    }

    func testCleanMentionsEmpty() {
        let cleaned = SlackService.cleanMentions("")
        XCTAssertEqual(cleaned, "")
    }

    // MARK: - SlackError

    func testSlackErrorDescriptions() {
        XCTAssertNotNil(SlackError.notConnected.errorDescription)
        XCTAssertNotNil(SlackError.invalidResponse.errorDescription)
        XCTAssertTrue(SlackError.apiError("test").errorDescription!.contains("test"))
    }
}
