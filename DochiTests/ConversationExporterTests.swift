import XCTest
@testable import Dochi

final class ConversationExporterTests: XCTestCase {

    private let fixedDate = Date(timeIntervalSince1970: 1700000000) // 2023-11-14

    private func makeConversation(
        title: String = "테스트 대화",
        messages: [Message] = [],
        source: ConversationSource = .local
    ) -> Conversation {
        Conversation(
            title: title,
            messages: messages,
            createdAt: fixedDate,
            updatedAt: fixedDate,
            source: source
        )
    }

    // MARK: - Markdown Export

    func testMarkdownExportHeader() {
        let conv = makeConversation(title: "안녕하세요")
        let md = ConversationExporter.toMarkdown(conv)

        XCTAssertTrue(md.hasPrefix("# 안녕하세요"))
        XCTAssertTrue(md.contains("생성:"))
        XCTAssertTrue(md.contains("수정:"))
    }

    func testMarkdownExportTelegramSource() {
        let conv = makeConversation(source: .telegram)
        let md = ConversationExporter.toMarkdown(conv)

        XCTAssertTrue(md.contains("출처: Telegram"))
    }

    func testMarkdownExportLocalSourceNoLabel() {
        let conv = makeConversation(source: .local)
        let md = ConversationExporter.toMarkdown(conv)

        XCTAssertFalse(md.contains("출처:"))
    }

    func testMarkdownExportUserMessage() {
        let messages = [
            Message(role: .user, content: "안녕하세요", timestamp: fixedDate)
        ]
        let conv = makeConversation(messages: messages)
        let md = ConversationExporter.toMarkdown(conv)

        XCTAssertTrue(md.contains("### 사용자"))
        XCTAssertTrue(md.contains("안녕하세요"))
    }

    func testMarkdownExportAssistantMessage() {
        let messages = [
            Message(role: .assistant, content: "반갑습니다!", timestamp: fixedDate)
        ]
        let conv = makeConversation(messages: messages)
        let md = ConversationExporter.toMarkdown(conv)

        XCTAssertTrue(md.contains("### 어시스턴트"))
        XCTAssertTrue(md.contains("반갑습니다!"))
    }

    func testMarkdownExportToolCall() {
        let toolCall = CodableToolCall(id: "tc1", name: "search", argumentsJSON: #"{"query":"test"}"#)
        let messages = [
            Message(role: .assistant, content: "", timestamp: fixedDate, toolCalls: [toolCall])
        ]
        let conv = makeConversation(messages: messages)
        let md = ConversationExporter.toMarkdown(conv)

        XCTAssertTrue(md.contains("도구 호출"))
        XCTAssertTrue(md.contains("`search`"))
        XCTAssertTrue(md.contains("query"))
    }

    func testMarkdownExportToolResult() {
        let messages = [
            Message(role: .tool, content: "검색 결과입니다", timestamp: fixedDate, toolCallId: "tc1")
        ]
        let conv = makeConversation(messages: messages)
        let md = ConversationExporter.toMarkdown(conv)

        XCTAssertTrue(md.contains("### 도구"))
        XCTAssertTrue(md.contains("도구 결과"))
        XCTAssertTrue(md.contains("검색 결과입니다"))
    }

    func testMarkdownExportMultipleMessages() {
        let messages = [
            Message(role: .user, content: "질문", timestamp: fixedDate),
            Message(role: .assistant, content: "답변", timestamp: fixedDate),
            Message(role: .user, content: "추가 질문", timestamp: fixedDate),
        ]
        let conv = makeConversation(messages: messages)
        let md = ConversationExporter.toMarkdown(conv)

        // Count role headers
        let userCount = md.components(separatedBy: "### 사용자").count - 1
        let assistantCount = md.components(separatedBy: "### 어시스턴트").count - 1
        XCTAssertEqual(userCount, 2)
        XCTAssertEqual(assistantCount, 1)
    }

    func testMarkdownExportEmptyConversation() {
        let conv = makeConversation(messages: [])
        let md = ConversationExporter.toMarkdown(conv)

        XCTAssertTrue(md.contains("# 테스트 대화"))
        XCTAssertTrue(md.contains("---"))
    }

    // MARK: - JSON Export

    func testJSONExportRoundTrip() throws {
        let messages = [
            Message(role: .user, content: "안녕", timestamp: fixedDate),
            Message(role: .assistant, content: "반가워요", timestamp: fixedDate),
        ]
        let conv = makeConversation(messages: messages)

        let data = try ConversationExporter.toJSON(conv)
        XCTAssertFalse(data.isEmpty)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Conversation.self, from: data)

        XCTAssertEqual(decoded.id, conv.id)
        XCTAssertEqual(decoded.title, conv.title)
        XCTAssertEqual(decoded.messages.count, 2)
        XCTAssertEqual(decoded.messages[0].role, .user)
        XCTAssertEqual(decoded.messages[0].content, "안녕")
        XCTAssertEqual(decoded.messages[1].content, "반가워요")
    }

    func testJSONExportPrettyPrinted() throws {
        let conv = makeConversation(messages: [
            Message(role: .user, content: "test", timestamp: fixedDate)
        ])
        let data = try ConversationExporter.toJSON(conv)
        let str = String(data: data, encoding: .utf8)!

        // Pretty printed JSON should have newlines and indentation
        XCTAssertTrue(str.contains("\n"))
        XCTAssertTrue(str.contains("  "))
    }

    func testJSONExportWithToolCalls() throws {
        let toolCall = CodableToolCall(id: "tc1", name: "weather", argumentsJSON: #"{"city":"서울"}"#)
        let messages = [
            Message(role: .assistant, content: "", timestamp: fixedDate, toolCalls: [toolCall]),
            Message(role: .tool, content: "맑음", timestamp: fixedDate, toolCallId: "tc1"),
        ]
        let conv = makeConversation(messages: messages)

        let data = try ConversationExporter.toJSON(conv)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Conversation.self, from: data)

        XCTAssertEqual(decoded.messages[0].toolCalls?.count, 1)
        XCTAssertEqual(decoded.messages[0].toolCalls?[0].name, "weather")
        XCTAssertEqual(decoded.messages[1].toolCallId, "tc1")
    }

    // MARK: - Suggested File Name

    func testSuggestedFileNameMarkdown() {
        let conv = makeConversation(title: "오늘의 대화")
        let name = ConversationExporter.suggestedFileName(for: conv, format: .markdown)

        XCTAssertTrue(name.hasSuffix(".md"))
        XCTAssertTrue(name.contains("오늘의 대화"))
    }

    func testSuggestedFileNameJSON() {
        let conv = makeConversation(title: "테스트")
        let name = ConversationExporter.suggestedFileName(for: conv, format: .json)

        XCTAssertTrue(name.hasSuffix(".json"))
        XCTAssertTrue(name.contains("테스트"))
    }

    func testSuggestedFileNameSanitizesSlashes() {
        let conv = makeConversation(title: "폴더/파일:이름")
        let name = ConversationExporter.suggestedFileName(for: conv, format: .markdown)

        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
    }

    func testSuggestedFileNameTruncatesLongTitle() {
        let longTitle = String(repeating: "가", count: 100)
        let conv = makeConversation(title: longTitle)
        let name = ConversationExporter.suggestedFileName(for: conv, format: .markdown)

        // Date prefix (8) + _ (1) + title (max 40) + .md (3) = max 52
        XCTAssertLessThanOrEqual(name.count, 52)
    }
}
