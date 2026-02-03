import XCTest
@testable import Dochi

final class MessageTests: XCTestCase {

    // MARK: - Basic Message Tests

    func testMessageInitWithContent() {
        // When
        let message = Message(role: .user, content: "Hello")

        // Then
        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.content, "Hello")
        XCTAssertNil(message.toolCalls)
    }

    func testMessageInitWithToolCalls() {
        // Given
        let toolCall = ToolCall(id: "call_1", name: "test_tool", arguments: ["key": "value"])

        // When
        let message = Message(role: .assistant, content: "Using tool", toolCalls: [toolCall])

        // Then
        XCTAssertEqual(message.role, .assistant)
        XCTAssertEqual(message.content, "Using tool")
        XCTAssertEqual(message.toolCalls?.count, 1)
        XCTAssertEqual(message.toolCalls?.first?.name, "test_tool")
    }

    // MARK: - Codable Tests

    func testMessageEncodingWithoutToolCalls() throws {
        // Given
        let message = Message(role: .user, content: "Test message")

        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Then
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["role"] as? String, "user")
        XCTAssertEqual(json?["content"] as? String, "Test message")
    }

    func testMessageDecodingWithoutToolCalls() throws {
        // Given
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "role": "assistant",
            "content": "Hello there",
            "timestamp": "2024-01-01T00:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!

        // When
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(Message.self, from: data)

        // Then
        XCTAssertEqual(message.role, .assistant)
        XCTAssertEqual(message.content, "Hello there")
        XCTAssertNil(message.toolCalls)
    }

    func testMessageEncodingWithToolCalls() throws {
        // Given
        let toolCall = ToolCall(
            id: "call_123",
            name: "get_weather",
            arguments: ["city": "Seoul"]
        )
        let message = Message(role: .assistant, content: "", toolCalls: [toolCall])

        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Then
        XCTAssertNotNil(json)
        let toolCallsArray = json?["toolCalls"] as? [[String: Any]]
        XCTAssertEqual(toolCallsArray?.count, 1)
        XCTAssertEqual(toolCallsArray?.first?["id"] as? String, "call_123")
        XCTAssertEqual(toolCallsArray?.first?["name"] as? String, "get_weather")
    }

    func testMessageDecodingWithToolCalls() throws {
        // Given - argumentsJSON is a JSON string, not an object
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "role": "assistant",
            "content": "Let me check the weather",
            "timestamp": "2024-01-01T00:00:00Z",
            "toolCalls": [
                {
                    "id": "call_abc",
                    "name": "get_weather",
                    "argumentsJSON": "{\\"city\\": \\"Seoul\\", \\"units\\": \\"celsius\\"}"
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!

        // When
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(Message.self, from: data)

        // Then
        XCTAssertEqual(message.role, .assistant)
        XCTAssertEqual(message.content, "Let me check the weather")
        XCTAssertEqual(message.toolCalls?.count, 1)

        let toolCall = message.toolCalls?.first
        XCTAssertEqual(toolCall?.id, "call_abc")
        XCTAssertEqual(toolCall?.name, "get_weather")
        XCTAssertEqual(toolCall?.arguments["city"] as? String, "Seoul")
        XCTAssertEqual(toolCall?.arguments["units"] as? String, "celsius")
    }

    func testMessageRoundTripWithToolCalls() throws {
        // Given
        let toolCall1 = ToolCall(
            id: "call_1",
            name: "search",
            arguments: ["query": "test", "limit": 5]
        )
        let toolCall2 = ToolCall(
            id: "call_2",
            name: "fetch",
            arguments: ["url": "https://example.com"]
        )
        let original = Message(
            role: .assistant,
            content: "Processing your request",
            toolCalls: [toolCall1, toolCall2]
        )

        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Message.self, from: data)

        // Then
        XCTAssertEqual(decoded.role, original.role)
        XCTAssertEqual(decoded.content, original.content)
        XCTAssertEqual(decoded.toolCalls?.count, 2)

        XCTAssertEqual(decoded.toolCalls?[0].id, "call_1")
        XCTAssertEqual(decoded.toolCalls?[0].name, "search")
        XCTAssertEqual(decoded.toolCalls?[0].arguments["query"] as? String, "test")
        XCTAssertEqual(decoded.toolCalls?[0].arguments["limit"] as? Int, 5)

        XCTAssertEqual(decoded.toolCalls?[1].id, "call_2")
        XCTAssertEqual(decoded.toolCalls?[1].name, "fetch")
    }

    func testMessageDecodingWithEmptyToolCalls() throws {
        // Given
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "role": "assistant",
            "content": "No tools needed",
            "timestamp": "2024-01-01T00:00:00Z",
            "toolCalls": []
        }
        """
        let data = json.data(using: .utf8)!

        // When
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(Message.self, from: data)

        // Then
        XCTAssertEqual(message.toolCalls?.count, 0)
    }

    func testMessageDecodingWithNestedToolCallArguments() throws {
        // Given - argumentsJSON is a JSON string with nested structure
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "role": "assistant",
            "content": "",
            "timestamp": "2024-01-01T00:00:00Z",
            "toolCalls": [
                {
                    "id": "call_nested",
                    "name": "complex_tool",
                    "argumentsJSON": "{\\"options\\": {\\"nested\\": true, \\"values\\": [1, 2, 3]}, \\"enabled\\": true}"
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!

        // When
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(Message.self, from: data)

        // Then
        let toolCall = message.toolCalls?.first
        XCTAssertNotNil(toolCall)

        let options = toolCall?.arguments["options"] as? [String: Any]
        XCTAssertEqual(options?["nested"] as? Bool, true)
        XCTAssertEqual(options?["values"] as? [Int], [1, 2, 3])
        XCTAssertEqual(toolCall?.arguments["enabled"] as? Bool, true)
    }

    // MARK: - Role Tests

    func testAllRoles() {
        let userMsg = Message(role: .user, content: "User")
        let assistantMsg = Message(role: .assistant, content: "Assistant")
        let systemMsg = Message(role: .system, content: "System")

        XCTAssertEqual(userMsg.role, .user)
        XCTAssertEqual(assistantMsg.role, .assistant)
        XCTAssertEqual(systemMsg.role, .system)
    }
}
