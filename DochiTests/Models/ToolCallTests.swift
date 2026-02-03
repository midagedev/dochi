import XCTest
@testable import Dochi

final class ToolCallTests: XCTestCase {

    // MARK: - ToolCall Creation Tests

    func testToolCallInitWithArguments() {
        // Given
        let id = "call_123"
        let name = "get_weather"
        let arguments: [String: Any] = ["city": "Seoul", "units": "celsius"]

        // When
        let toolCall = ToolCall(id: id, name: name, arguments: arguments)

        // Then
        XCTAssertEqual(toolCall.id, id)
        XCTAssertEqual(toolCall.name, name)
        XCTAssertEqual(toolCall.arguments["city"] as? String, "Seoul")
        XCTAssertEqual(toolCall.arguments["units"] as? String, "celsius")
    }

    func testToolCallInitWithEmptyArguments() {
        // Given
        let id = "call_456"
        let name = "list_files"
        let arguments: [String: Any] = [:]

        // When
        let toolCall = ToolCall(id: id, name: name, arguments: arguments)

        // Then
        XCTAssertEqual(toolCall.id, id)
        XCTAssertEqual(toolCall.name, name)
        XCTAssertTrue(toolCall.arguments.isEmpty)
    }

    func testToolCallInitWithJSONString() {
        // Given
        let id = "call_789"
        let name = "search"
        let jsonString = #"{"query": "swift", "limit": 10}"#

        // When
        let toolCall = ToolCall(id: id, name: name, argumentsJSON: jsonString)

        // Then
        XCTAssertEqual(toolCall.id, id)
        XCTAssertEqual(toolCall.name, name)
        XCTAssertEqual(toolCall.arguments["query"] as? String, "swift")
        XCTAssertEqual(toolCall.arguments["limit"] as? Int, 10)
    }

    func testToolCallInitWithInvalidJSONString() {
        // Given
        let id = "call_invalid"
        let name = "test"
        let invalidJSON = "not valid json"

        // When
        let toolCall = ToolCall(id: id, name: name, argumentsJSON: invalidJSON)

        // Then
        XCTAssertEqual(toolCall.id, id)
        XCTAssertEqual(toolCall.name, name)
        XCTAssertTrue(toolCall.arguments.isEmpty)
    }

    func testToolCallInitWithEmptyJSONString() {
        // Given
        let id = "call_empty"
        let name = "no_args"
        let emptyJSON = "{}"

        // When
        let toolCall = ToolCall(id: id, name: name, argumentsJSON: emptyJSON)

        // Then
        XCTAssertEqual(toolCall.id, id)
        XCTAssertEqual(toolCall.name, name)
        XCTAssertTrue(toolCall.arguments.isEmpty)
    }

    func testToolCallWithNestedArguments() {
        // Given
        let id = "call_nested"
        let name = "complex_tool"
        let jsonString = #"{"options": {"nested": true, "values": [1, 2, 3]}}"#

        // When
        let toolCall = ToolCall(id: id, name: name, argumentsJSON: jsonString)

        // Then
        XCTAssertNotNil(toolCall.arguments["options"])
        if let options = toolCall.arguments["options"] as? [String: Any] {
            XCTAssertEqual(options["nested"] as? Bool, true)
            XCTAssertEqual(options["values"] as? [Int], [1, 2, 3])
        }
    }

    // MARK: - ToolResult Tests

    func testToolResultInit() {
        // Given
        let toolCallId = "call_123"
        let content = "Success result"
        let isError = false

        // When
        let result = ToolResult(toolCallId: toolCallId, content: content, isError: isError)

        // Then
        XCTAssertEqual(result.toolCallId, toolCallId)
        XCTAssertEqual(result.content, content)
        XCTAssertFalse(result.isError)
    }

    func testToolResultWithError() {
        // Given
        let toolCallId = "call_456"
        let content = "Tool execution failed"

        // When
        let result = ToolResult(toolCallId: toolCallId, content: content, isError: true)

        // Then
        XCTAssertEqual(result.toolCallId, toolCallId)
        XCTAssertEqual(result.content, content)
        XCTAssertTrue(result.isError)
    }

    func testToolResultDefaultIsError() {
        // When
        let result = ToolResult(toolCallId: "call", content: "content")

        // Then
        XCTAssertFalse(result.isError)
    }

    // MARK: - Identifiable Tests

    func testToolCallIsIdentifiable() {
        // Given
        let toolCall1 = ToolCall(id: "id1", name: "tool1", arguments: [:])
        let toolCall2 = ToolCall(id: "id2", name: "tool2", arguments: [:])

        // Then
        XCTAssertEqual(toolCall1.id, "id1")
        XCTAssertEqual(toolCall2.id, "id2")
        XCTAssertNotEqual(toolCall1.id, toolCall2.id)
    }
}
