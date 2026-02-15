import XCTest
@testable import Dochi

final class ToolExecutionTests: XCTestCase {

    // MARK: - ToolExecutionSummary.generateInputSummary

    func testGenerateInputSummaryBasic() {
        let args: [String: Any] = ["query": "hello world", "limit": 10]
        let summary = ToolExecutionSummary.generateInputSummary(from: args)
        // Should contain both key-value pairs
        XCTAssertTrue(summary.contains("query=hello world"))
        XCTAssertTrue(summary.contains("limit=10"))
    }

    func testGenerateInputSummaryEmpty() {
        let summary = ToolExecutionSummary.generateInputSummary(from: [:])
        XCTAssertEqual(summary, "")
    }

    func testGenerateInputSummaryMasksSensitiveKeys() {
        let args: [String: Any] = ["api_key": "sk-secret-123", "name": "test"]
        let summary = ToolExecutionSummary.generateInputSummary(from: args)
        XCTAssertTrue(summary.contains("api_key=****"))
        XCTAssertTrue(summary.contains("name=test"))
        XCTAssertFalse(summary.contains("sk-secret"))
    }

    func testGenerateInputSummaryMasksPasswordKey() {
        let args: [String: Any] = ["password": "mysecret"]
        let summary = ToolExecutionSummary.generateInputSummary(from: args)
        XCTAssertTrue(summary.contains("password=****"))
        XCTAssertFalse(summary.contains("mysecret"))
    }

    func testGenerateInputSummaryTruncatesLongValues() {
        let longValue = String(repeating: "a", count: 100)
        let args: [String: Any] = ["data": longValue]
        let summary = ToolExecutionSummary.generateInputSummary(from: args)
        // The string value should be truncated to 30 chars
        XCTAssertTrue(summary.contains("data=\(String(repeating: "a", count: 30))"))
    }

    func testGenerateInputSummaryTruncatesTo80Chars() {
        // Create many arguments to exceed 80 chars
        var args: [String: Any] = [:]
        for i in 0..<20 {
            args["key\(i)"] = "value_\(i)"
        }
        let summary = ToolExecutionSummary.generateInputSummary(from: args)
        XCTAssertLessThanOrEqual(summary.count, 80)
        XCTAssertTrue(summary.hasSuffix("..."))
    }

    func testGenerateInputSummaryArrayValue() {
        let args: [String: Any] = ["items": [1, 2, 3]]
        let summary = ToolExecutionSummary.generateInputSummary(from: args)
        XCTAssertTrue(summary.contains("items=[3items]"))
    }

    func testGenerateInputSummaryDictValue() {
        let args: [String: Any] = ["config": ["a": 1, "b": 2]]
        let summary = ToolExecutionSummary.generateInputSummary(from: args)
        XCTAssertTrue(summary.contains("config={2keys}"))
    }

    // MARK: - ToolExecutionSummary.generateResultSummary

    func testGenerateResultSummaryShort() {
        let result = ToolExecutionSummary.generateResultSummary(from: "All done!", isError: false)
        XCTAssertEqual(result, "All done!")
    }

    func testGenerateResultSummaryError() {
        let result = ToolExecutionSummary.generateResultSummary(from: "Failed", isError: true)
        XCTAssertEqual(result, "Error: Failed")
    }

    func testGenerateResultSummaryTruncatesLong() {
        let longContent = String(repeating: "x", count: 200)
        let result = ToolExecutionSummary.generateResultSummary(from: longContent, isError: false)
        XCTAssertEqual(result.count, 100) // 97 + "..."
        XCTAssertTrue(result.hasSuffix("..."))
    }

    func testGenerateResultSummaryTruncatesLongError() {
        let longContent = String(repeating: "x", count: 200)
        let result = ToolExecutionSummary.generateResultSummary(from: longContent, isError: true)
        XCTAssertTrue(result.hasPrefix("Error: "))
        XCTAssertTrue(result.hasSuffix("..."))
    }

    // MARK: - ToolExecutionRecord Codable

    func testToolExecutionRecordEncodeDecode() throws {
        let record = ToolExecutionRecord(
            toolName: "web_search",
            displayName: "웹 검색",
            inputSummary: "query=test",
            isError: false,
            durationSeconds: 1.5,
            resultSummary: "검색 완료"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(record)
        let decoded = try JSONDecoder().decode(ToolExecutionRecord.self, from: data)

        XCTAssertEqual(decoded.toolName, "web_search")
        XCTAssertEqual(decoded.displayName, "웹 검색")
        XCTAssertEqual(decoded.inputSummary, "query=test")
        XCTAssertFalse(decoded.isError)
        XCTAssertEqual(decoded.durationSeconds, 1.5)
        XCTAssertEqual(decoded.resultSummary, "검색 완료")
    }

    func testToolExecutionRecordWithNilValues() throws {
        let record = ToolExecutionRecord(
            toolName: "calculate",
            displayName: "계산",
            inputSummary: "expression=1+1",
            isError: false,
            durationSeconds: nil,
            resultSummary: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(record)
        let decoded = try JSONDecoder().decode(ToolExecutionRecord.self, from: data)

        XCTAssertEqual(decoded.toolName, "calculate")
        XCTAssertNil(decoded.durationSeconds)
        XCTAssertNil(decoded.resultSummary)
    }

    // MARK: - ToolExecution Model

    @MainActor
    func testToolExecutionCreation() {
        let execution = ToolExecution(
            toolName: "web_search",
            toolCallId: "call-1",
            displayName: "웹 검색",
            category: .safe,
            inputSummary: "query=test",
            loopIndex: 1
        )

        XCTAssertEqual(execution.toolName, "web_search")
        XCTAssertEqual(execution.toolCallId, "call-1")
        XCTAssertEqual(execution.displayName, "웹 검색")
        XCTAssertEqual(execution.category, .safe)
        XCTAssertEqual(execution.status, .running)
        XCTAssertNil(execution.completedAt)
        XCTAssertNil(execution.durationSeconds)
        XCTAssertEqual(execution.loopIndex, 1)
    }

    @MainActor
    func testToolExecutionComplete() {
        let execution = ToolExecution(
            toolName: "calculate",
            toolCallId: "call-2",
            displayName: "계산",
            inputSummary: "expression=2+2",
            loopIndex: 0
        )

        execution.complete(resultSummary: "결과: 4", resultFull: "4")

        XCTAssertEqual(execution.status, .success)
        XCTAssertNotNil(execution.completedAt)
        XCTAssertEqual(execution.resultSummary, "결과: 4")
        XCTAssertEqual(execution.resultFull, "4")
        XCTAssertNotNil(execution.durationSeconds)
    }

    @MainActor
    func testToolExecutionFail() {
        let execution = ToolExecution(
            toolName: "shell.execute",
            toolCallId: "call-3",
            displayName: "셸 명령 실행",
            category: .restricted,
            inputSummary: "command=rm -rf /",
            loopIndex: 0
        )

        execution.fail(errorSummary: "Permission denied", errorFull: "Error: Permission denied")

        XCTAssertEqual(execution.status, .error)
        XCTAssertNotNil(execution.completedAt)
        XCTAssertEqual(execution.resultSummary, "Permission denied")
        XCTAssertEqual(execution.resultFull, "Error: Permission denied")
    }

    @MainActor
    func testToolExecutionToRecord() {
        let execution = ToolExecution(
            toolName: "web_search",
            toolCallId: "call-1",
            displayName: "웹 검색",
            category: .safe,
            inputSummary: "query=test",
            loopIndex: 1
        )
        execution.complete(resultSummary: "Found 5 results", resultFull: "Full results here...")

        let record = execution.toRecord()

        XCTAssertEqual(record.toolName, "web_search")
        XCTAssertEqual(record.displayName, "웹 검색")
        XCTAssertEqual(record.inputSummary, "query=test")
        XCTAssertFalse(record.isError)
        XCTAssertNotNil(record.durationSeconds)
        XCTAssertEqual(record.resultSummary, "Found 5 results")
    }

    @MainActor
    func testToolExecutionErrorToRecord() {
        let execution = ToolExecution(
            toolName: "open_url",
            toolCallId: "call-4",
            displayName: "URL 열기",
            category: .sensitive,
            inputSummary: "url=https://example.com",
            loopIndex: 0
        )
        execution.fail(errorSummary: "네트워크 오류", errorFull: "Connection refused")

        let record = execution.toRecord()

        XCTAssertTrue(record.isError)
        XCTAssertEqual(record.resultSummary, "네트워크 오류")
    }

    // MARK: - Message with ToolExecutionRecords Backward Compatibility

    func testMessageWithoutToolExecutionRecordsDecodesOK() throws {
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "role": "assistant",
            "content": "Hello!",
            "timestamp": "2024-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(Message.self, from: json)

        XCTAssertEqual(message.role, .assistant)
        XCTAssertEqual(message.content, "Hello!")
        XCTAssertNil(message.toolExecutionRecords)
    }

    func testMessageWithToolExecutionRecordsDecodesOK() throws {
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "role": "assistant",
            "content": "Response text",
            "timestamp": "2024-01-01T00:00:00Z",
            "toolExecutionRecords": [
                {
                    "toolName": "web_search",
                    "displayName": "웹 검색",
                    "inputSummary": "query=test",
                    "isError": false,
                    "durationSeconds": 1.5,
                    "resultSummary": "검색 완료"
                }
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(Message.self, from: json)

        XCTAssertEqual(message.role, .assistant)
        XCTAssertNotNil(message.toolExecutionRecords)
        XCTAssertEqual(message.toolExecutionRecords?.count, 1)
        XCTAssertEqual(message.toolExecutionRecords?.first?.toolName, "web_search")
        XCTAssertEqual(message.toolExecutionRecords?.first?.durationSeconds, 1.5)
    }

    func testMessageRoundtripWithToolExecutionRecords() throws {
        let records = [
            ToolExecutionRecord(
                toolName: "calculate",
                displayName: "계산",
                inputSummary: "expression=2+2",
                isError: false,
                durationSeconds: 0.1,
                resultSummary: "4"
            ),
            ToolExecutionRecord(
                toolName: "save_memory",
                displayName: "메모리 저장",
                inputSummary: "content=test data",
                isError: false,
                durationSeconds: 0.3,
                resultSummary: "저장 완료"
            )
        ]

        let message = Message(
            role: .assistant,
            content: "Test response",
            toolExecutionRecords: records
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Message.self, from: data)

        XCTAssertEqual(decoded.toolExecutionRecords?.count, 2)
        XCTAssertEqual(decoded.toolExecutionRecords?[0].toolName, "calculate")
        XCTAssertEqual(decoded.toolExecutionRecords?[1].toolName, "save_memory")
        XCTAssertEqual(decoded.toolExecutionRecords?[0].durationSeconds, 0.1)
        XCTAssertFalse(decoded.toolExecutionRecords![0].isError)
    }

    // MARK: - Conversation with ToolExecutionRecords

    func testConversationRoundtripWithToolExecutionRecords() throws {
        let records = [
            ToolExecutionRecord(
                toolName: "web_search",
                displayName: "웹 검색",
                inputSummary: "query=swift",
                isError: false,
                durationSeconds: 2.0,
                resultSummary: "Found results"
            )
        ]

        let messages = [
            Message(role: .user, content: "검색해줘"),
            Message(role: .assistant, content: "검색 결과입니다.", toolExecutionRecords: records)
        ]

        let conversation = Conversation(
            title: "테스트",
            messages: messages
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(conversation)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Conversation.self, from: data)

        let assistantMsg = decoded.messages[1]
        XCTAssertEqual(assistantMsg.toolExecutionRecords?.count, 1)
        XCTAssertEqual(assistantMsg.toolExecutionRecords?.first?.toolName, "web_search")
    }

    // MARK: - ToolExecutionRecord Equatable

    func testToolExecutionRecordEquatable() {
        let a = ToolExecutionRecord(
            toolName: "test",
            displayName: "테스트",
            inputSummary: "key=val",
            isError: false,
            durationSeconds: 1.0,
            resultSummary: "ok"
        )
        let b = ToolExecutionRecord(
            toolName: "test",
            displayName: "테스트",
            inputSummary: "key=val",
            isError: false,
            durationSeconds: 1.0,
            resultSummary: "ok"
        )
        XCTAssertEqual(a, b)
    }
}
