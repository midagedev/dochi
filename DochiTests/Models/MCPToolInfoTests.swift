import XCTest
@testable import Dochi

final class MCPToolInfoTests: XCTestCase {

    // MARK: - Basic Tests

    func testMCPToolInfoInit() {
        // When
        let tool = MCPToolInfo(
            id: "server:tool_1",
            name: "get_weather",
            description: "Get current weather for a city",
            inputSchema: ["type": "object", "properties": ["city": ["type": "string"]]]
        )

        // Then
        XCTAssertEqual(tool.id, "server:tool_1")
        XCTAssertEqual(tool.name, "get_weather")
        XCTAssertEqual(tool.description, "Get current weather for a city")
        XCTAssertNotNil(tool.inputSchema)
    }

    func testMCPToolInfoWithNilDescription() {
        // When
        let tool = MCPToolInfo(
            id: "tool_2",
            name: "simple_tool",
            description: nil,
            inputSchema: nil
        )

        // Then
        XCTAssertNil(tool.description)
        XCTAssertNil(tool.inputSchema)
    }

    // MARK: - asDictionary Tests

    func testAsDictionaryBasic() {
        // Given
        let tool = MCPToolInfo(
            id: "tool_1",
            name: "test_tool",
            description: "A test tool",
            inputSchema: ["type": "object", "properties": [:]]
        )

        // When
        let dict = tool.asDictionary

        // Then
        XCTAssertEqual(dict["type"] as? String, "function")

        let function = dict["function"] as? [String: Any]
        XCTAssertNotNil(function)
        XCTAssertEqual(function?["name"] as? String, "test_tool")
        XCTAssertEqual(function?["description"] as? String, "A test tool")
        XCTAssertNotNil(function?["parameters"])
    }

    func testAsDictionaryWithoutDescription() {
        // Given
        let tool = MCPToolInfo(
            id: "tool_2",
            name: "no_desc_tool",
            description: nil,
            inputSchema: ["type": "object"]
        )

        // When
        let dict = tool.asDictionary

        // Then
        let function = dict["function"] as? [String: Any]
        XCTAssertNotNil(function)
        XCTAssertEqual(function?["name"] as? String, "no_desc_tool")
        XCTAssertNil(function?["description"])
    }

    func testAsDictionaryWithoutInputSchema() {
        // Given
        let tool = MCPToolInfo(
            id: "tool_3",
            name: "no_schema_tool",
            description: "Tool without schema",
            inputSchema: nil
        )

        // When
        let dict = tool.asDictionary

        // Then
        let function = dict["function"] as? [String: Any]
        XCTAssertNotNil(function)
        XCTAssertNil(function?["parameters"])
    }

    func testAsDictionaryWithComplexInputSchema() {
        // Given
        let inputSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "query": ["type": "string", "description": "Search query"],
                "limit": ["type": "integer", "default": 10],
                "options": [
                    "type": "object",
                    "properties": [
                        "caseSensitive": ["type": "boolean"]
                    ]
                ]
            ],
            "required": ["query"]
        ]
        let tool = MCPToolInfo(
            id: "search_tool",
            name: "search",
            description: "Search for items",
            inputSchema: inputSchema
        )

        // When
        let dict = tool.asDictionary

        // Then
        let function = dict["function"] as? [String: Any]
        let params = function?["parameters"] as? [String: Any]
        XCTAssertNotNil(params)
        XCTAssertEqual(params?["type"] as? String, "object")

        let properties = params?["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["query"])
        XCTAssertNotNil(properties?["limit"])
        XCTAssertNotNil(properties?["options"])

        let required = params?["required"] as? [String]
        XCTAssertEqual(required, ["query"])
    }

    // MARK: - MCPToolResult Tests

    func testMCPToolResultInit() {
        // When
        let result = MCPToolResult(content: "Success", isError: false)

        // Then
        XCTAssertEqual(result.content, "Success")
        XCTAssertFalse(result.isError)
    }

    func testMCPToolResultWithError() {
        // When
        let result = MCPToolResult(content: "Failed to execute", isError: true)

        // Then
        XCTAssertEqual(result.content, "Failed to execute")
        XCTAssertTrue(result.isError)
    }

    // MARK: - MCPServerConfig Tests

    func testMCPServerConfigInit() {
        // When
        let config = MCPServerConfig(
            name: "Test Server",
            command: "http://localhost:8080",
            arguments: ["--verbose"],
            environment: ["API_KEY": "test"],
            isEnabled: true
        )

        // Then
        XCTAssertEqual(config.name, "Test Server")
        XCTAssertEqual(config.command, "http://localhost:8080")
        XCTAssertEqual(config.arguments, ["--verbose"])
        XCTAssertEqual(config.environment?["API_KEY"], "test")
        XCTAssertTrue(config.isEnabled)
    }

    func testMCPServerConfigDefaults() {
        // When
        let config = MCPServerConfig(
            name: "Simple Server",
            command: "http://localhost:3000"
        )

        // Then
        XCTAssertEqual(config.name, "Simple Server")
        XCTAssertEqual(config.command, "http://localhost:3000")
        XCTAssertTrue(config.arguments.isEmpty)
        XCTAssertNil(config.environment)
        XCTAssertTrue(config.isEnabled)
    }

    func testMCPServerConfigCodable() throws {
        // Given
        let original = MCPServerConfig(
            name: "Codable Test",
            command: "http://example.com/mcp",
            arguments: ["-p", "8080"],
            environment: ["DEBUG": "true"],
            isEnabled: false
        )

        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MCPServerConfig.self, from: data)

        // Then
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.command, original.command)
        XCTAssertEqual(decoded.arguments, original.arguments)
        XCTAssertEqual(decoded.environment, original.environment)
        XCTAssertEqual(decoded.isEnabled, original.isEnabled)
    }
}
