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

    // MARK: - ExportFormat Properties

    func testExportFormatDisplayName() {
        XCTAssertEqual(ExportFormat.markdown.displayName, "Markdown")
        XCTAssertEqual(ExportFormat.json.displayName, "JSON")
        XCTAssertEqual(ExportFormat.pdf.displayName, "PDF")
        XCTAssertEqual(ExportFormat.plainText.displayName, "텍스트")
    }

    func testExportFormatFileExtension() {
        XCTAssertEqual(ExportFormat.markdown.fileExtension, "md")
        XCTAssertEqual(ExportFormat.json.fileExtension, "json")
        XCTAssertEqual(ExportFormat.pdf.fileExtension, "pdf")
        XCTAssertEqual(ExportFormat.plainText.fileExtension, "txt")
    }

    func testExportFormatIcon() {
        XCTAssertEqual(ExportFormat.markdown.icon, "doc.text")
        XCTAssertEqual(ExportFormat.json.icon, "doc.badge.gearshape")
        XCTAssertEqual(ExportFormat.pdf.icon, "doc.richtext")
        XCTAssertEqual(ExportFormat.plainText.icon, "doc.plaintext")
    }

    func testExportFormatAllCases() {
        XCTAssertEqual(ExportFormat.allCases.count, 4)
    }

    // MARK: - Suggested File Name (New Formats)

    func testSuggestedFileNamePDF() {
        let conv = makeConversation(title: "PDF 대화")
        let name = ConversationExporter.suggestedFileName(for: conv, format: .pdf)

        XCTAssertTrue(name.hasSuffix(".pdf"))
        XCTAssertTrue(name.contains("PDF 대화"))
    }

    func testSuggestedFileNamePlainText() {
        let conv = makeConversation(title: "텍스트 대화")
        let name = ConversationExporter.suggestedFileName(for: conv, format: .plainText)

        XCTAssertTrue(name.hasSuffix(".txt"))
        XCTAssertTrue(name.contains("텍스트 대화"))
    }

    // MARK: - ExportOptions

    func testExportOptionsDefault() {
        let opts = ExportOptions.default
        XCTAssertFalse(opts.includeSystemMessages)
        XCTAssertTrue(opts.includeToolMessages)
        XCTAssertFalse(opts.includeMetadata)
    }

    // MARK: - Plain Text Export

    func testPlainTextExportHeader() {
        let conv = makeConversation(title: "테스트 대화")
        let text = ConversationExporter.toPlainText(conv)

        XCTAssertTrue(text.hasPrefix("테스트 대화"))
        XCTAssertTrue(text.contains("생성:"))
        XCTAssertTrue(text.contains("수정:"))
    }

    func testPlainTextExportMessages() {
        let messages = [
            Message(role: .user, content: "안녕", timestamp: fixedDate),
            Message(role: .assistant, content: "반가워요", timestamp: fixedDate),
        ]
        let conv = makeConversation(messages: messages)
        let text = ConversationExporter.toPlainText(conv)

        XCTAssertTrue(text.contains("[사용자]"))
        XCTAssertTrue(text.contains("안녕"))
        XCTAssertTrue(text.contains("[어시스턴트]"))
        XCTAssertTrue(text.contains("반가워요"))
    }

    func testPlainTextExportTelegramSource() {
        let conv = makeConversation(source: .telegram)
        let text = ConversationExporter.toPlainText(conv)

        XCTAssertTrue(text.contains("출처: Telegram"))
    }

    func testPlainTextExportLocalNoSource() {
        let conv = makeConversation(source: .local)
        let text = ConversationExporter.toPlainText(conv)

        XCTAssertFalse(text.contains("출처:"))
    }

    // MARK: - Export Options Filtering

    func testMarkdownExcludesSystemMessagesByDefault() {
        let messages = [
            Message(role: .system, content: "시스템 프롬프트", timestamp: fixedDate),
            Message(role: .user, content: "안녕", timestamp: fixedDate),
        ]
        let conv = makeConversation(messages: messages)
        let md = ConversationExporter.toMarkdown(conv, options: .default)

        XCTAssertFalse(md.contains("시스템 프롬프트"))
        XCTAssertTrue(md.contains("안녕"))
    }

    func testMarkdownIncludesSystemMessagesWhenEnabled() {
        let messages = [
            Message(role: .system, content: "시스템 프롬프트", timestamp: fixedDate),
            Message(role: .user, content: "안녕", timestamp: fixedDate),
        ]
        let conv = makeConversation(messages: messages)
        var opts = ExportOptions()
        opts.includeSystemMessages = true
        let md = ConversationExporter.toMarkdown(conv, options: opts)

        XCTAssertTrue(md.contains("시스템 프롬프트"))
        XCTAssertTrue(md.contains("안녕"))
    }

    func testMarkdownIncludesToolMessagesByDefault() {
        let messages = [
            Message(role: .tool, content: "도구 결과 내용", timestamp: fixedDate, toolCallId: "tc1"),
        ]
        let conv = makeConversation(messages: messages)
        let md = ConversationExporter.toMarkdown(conv, options: .default)

        XCTAssertTrue(md.contains("도구 결과 내용"))
    }

    func testMarkdownExcludesToolMessagesWhenDisabled() {
        let messages = [
            Message(role: .tool, content: "도구 결과 내용", timestamp: fixedDate, toolCallId: "tc1"),
            Message(role: .user, content: "안녕", timestamp: fixedDate),
        ]
        let conv = makeConversation(messages: messages)
        var opts = ExportOptions()
        opts.includeToolMessages = false
        let md = ConversationExporter.toMarkdown(conv, options: opts)

        XCTAssertFalse(md.contains("도구 결과 내용"))
        XCTAssertTrue(md.contains("안녕"))
    }

    func testMarkdownIncludesMetadataWhenEnabled() {
        let metadata = MessageMetadata(
            provider: "openai",
            model: "gpt-4",
            inputTokens: 100,
            outputTokens: 50,
            totalLatency: 1.5,
            wasFallback: false
        )
        let messages = [
            Message(role: .assistant, content: "답변", timestamp: fixedDate, metadata: metadata),
        ]
        let conv = makeConversation(messages: messages)
        var opts = ExportOptions()
        opts.includeMetadata = true
        let md = ConversationExporter.toMarkdown(conv, options: opts)

        XCTAssertTrue(md.contains("gpt-4"))
    }

    func testMarkdownExcludesMetadataByDefault() {
        let metadata = MessageMetadata(
            provider: "openai",
            model: "gpt-4",
            inputTokens: 100,
            outputTokens: 50,
            totalLatency: 1.5,
            wasFallback: false
        )
        let messages = [
            Message(role: .assistant, content: "답변", timestamp: fixedDate, metadata: metadata),
        ]
        let conv = makeConversation(messages: messages)
        let md = ConversationExporter.toMarkdown(conv, options: .default)

        XCTAssertFalse(md.contains("gpt-4"))
    }

    // MARK: - JSON Export with Options

    func testJSONExportFiltersByOptions() throws {
        let messages = [
            Message(role: .system, content: "시스템", timestamp: fixedDate),
            Message(role: .user, content: "안녕", timestamp: fixedDate),
            Message(role: .assistant, content: "반가워요", timestamp: fixedDate),
        ]
        let conv = makeConversation(messages: messages)
        let data = try ConversationExporter.toJSON(conv, options: .default)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Conversation.self, from: data)

        // System messages excluded by default
        XCTAssertEqual(decoded.messages.count, 2)
        XCTAssertEqual(decoded.messages[0].role, .user)
    }

    // MARK: - Plain Text Export with Options

    func testPlainTextExcludesSystemByDefault() {
        let messages = [
            Message(role: .system, content: "시스템 프롬프트", timestamp: fixedDate),
            Message(role: .user, content: "안녕", timestamp: fixedDate),
        ]
        let conv = makeConversation(messages: messages)
        let text = ConversationExporter.toPlainText(conv, options: .default)

        XCTAssertFalse(text.contains("시스템 프롬프트"))
        XCTAssertTrue(text.contains("안녕"))
    }

    func testPlainTextWithToolCalls() {
        let toolCall = CodableToolCall(id: "tc1", name: "search", argumentsJSON: #"{"q":"test"}"#)
        let messages = [
            Message(role: .assistant, content: "검색합니다", timestamp: fixedDate, toolCalls: [toolCall]),
        ]
        let conv = makeConversation(messages: messages)
        let text = ConversationExporter.toPlainText(conv, options: .default)

        XCTAssertTrue(text.contains("[도구 호출: search]"))
    }

    // MARK: - Export to String

    func testExportToStringMarkdown() {
        let messages = [
            Message(role: .user, content: "안녕", timestamp: fixedDate),
        ]
        let conv = makeConversation(messages: messages)
        let str = ConversationExporter.exportToString(conv, format: .markdown)

        XCTAssertNotNil(str)
        XCTAssertTrue(str!.contains("# 테스트 대화"))
    }

    func testExportToStringJSON() {
        let conv = makeConversation(messages: [
            Message(role: .user, content: "test", timestamp: fixedDate),
        ])
        let str = ConversationExporter.exportToString(conv, format: .json)

        XCTAssertNotNil(str)
        XCTAssertTrue(str!.contains("test"))
    }

    func testExportToStringPlainText() {
        let conv = makeConversation(messages: [
            Message(role: .user, content: "안녕", timestamp: fixedDate),
        ])
        let str = ConversationExporter.exportToString(conv, format: .plainText)

        XCTAssertNotNil(str)
        XCTAssertTrue(str!.contains("[사용자]"))
    }

    func testExportToStringPDFReturnsNil() {
        let conv = makeConversation()
        let str = ConversationExporter.exportToString(conv, format: .pdf)

        XCTAssertNil(str)
    }

    // MARK: - Export to Data

    func testExportToDataMarkdown() {
        let conv = makeConversation(messages: [
            Message(role: .user, content: "test", timestamp: fixedDate),
        ])
        let data = ConversationExporter.exportToData(conv, format: .markdown)

        XCTAssertNotNil(data)
        let str = String(data: data!, encoding: .utf8)!
        XCTAssertTrue(str.contains("# 테스트 대화"))
    }

    func testExportToDataJSON() {
        let conv = makeConversation(messages: [
            Message(role: .user, content: "test", timestamp: fixedDate),
        ])
        let data = ConversationExporter.exportToData(conv, format: .json)

        XCTAssertNotNil(data)
    }

    func testExportToDataPlainText() {
        let conv = makeConversation(messages: [
            Message(role: .user, content: "test", timestamp: fixedDate),
        ])
        let data = ConversationExporter.exportToData(conv, format: .plainText)

        XCTAssertNotNil(data)
    }

    func testExportToDataPDF() {
        let conv = makeConversation(messages: [
            Message(role: .user, content: "PDF 테스트 내용", timestamp: fixedDate),
        ])
        let data = ConversationExporter.exportToData(conv, format: .pdf)

        XCTAssertNotNil(data)
        // PDF data starts with %PDF
        if let data = data, data.count >= 4 {
            let pdfHeader = String(data: data.prefix(4), encoding: .ascii)
            XCTAssertEqual(pdfHeader, "%PDF")
        }
    }

    // MARK: - Merge Export

    func testMergeToMarkdown() {
        let conv1 = makeConversation(title: "대화 1", messages: [
            Message(role: .user, content: "첫 번째", timestamp: fixedDate),
        ])
        let conv2 = makeConversation(title: "대화 2", messages: [
            Message(role: .user, content: "두 번째", timestamp: fixedDate),
        ])

        let merged = ConversationExporter.mergeToMarkdown([conv1, conv2])

        XCTAssertTrue(merged.contains("대화 모음 (2개)"))
        XCTAssertTrue(merged.contains("## 1. 대화 1"))
        XCTAssertTrue(merged.contains("## 2. 대화 2"))
        XCTAssertTrue(merged.contains("첫 번째"))
        XCTAssertTrue(merged.contains("두 번째"))
    }

    func testMergeToMarkdownEmpty() {
        let merged = ConversationExporter.mergeToMarkdown([])

        XCTAssertTrue(merged.contains("대화 모음 (0개)"))
    }

    // MARK: - Backward Compatibility

    func testToMarkdownBackwardCompatibility() {
        // Calling without options should use defaults and produce same results as before
        let messages = [
            Message(role: .user, content: "안녕", timestamp: fixedDate),
            Message(role: .assistant, content: "반가워요", timestamp: fixedDate),
        ]
        let conv = makeConversation(messages: messages)

        let mdNoOptions = ConversationExporter.toMarkdown(conv)
        let mdDefaultOptions = ConversationExporter.toMarkdown(conv, options: .default)

        XCTAssertEqual(mdNoOptions, mdDefaultOptions)
    }

    func testToJSONBackwardCompatibility() throws {
        let messages = [
            Message(role: .user, content: "test", timestamp: fixedDate),
        ]
        let conv = makeConversation(messages: messages)

        let dataNoOptions = try ConversationExporter.toJSON(conv)
        let dataDefaultOptions = try ConversationExporter.toJSON(conv, options: .default)

        // Both should produce valid JSON with same content
        XCTAssertEqual(dataNoOptions.count, dataDefaultOptions.count)
    }
}
