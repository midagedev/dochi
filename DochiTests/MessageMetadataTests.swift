import XCTest
@testable import Dochi

final class MessageMetadataTests: XCTestCase {
    // MARK: - MessageMetadata Encoding/Decoding

    func testMessageMetadataEncodeDecode() throws {
        let metadata = MessageMetadata(
            provider: "openai",
            model: "gpt-4o",
            inputTokens: 500,
            outputTokens: 200,
            totalLatency: 2.5,
            wasFallback: false
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MessageMetadata.self, from: data)

        XCTAssertEqual(decoded.provider, "openai")
        XCTAssertEqual(decoded.model, "gpt-4o")
        XCTAssertEqual(decoded.inputTokens, 500)
        XCTAssertEqual(decoded.outputTokens, 200)
        XCTAssertEqual(decoded.totalLatency, 2.5)
        XCTAssertEqual(decoded.wasFallback, false)
    }

    func testMessageMetadataWithNilValues() throws {
        let metadata = MessageMetadata(
            provider: "anthropic",
            model: "claude-3-sonnet",
            inputTokens: nil,
            outputTokens: nil,
            totalLatency: nil,
            wasFallback: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)
        let decoded = try JSONDecoder().decode(MessageMetadata.self, from: data)

        XCTAssertEqual(decoded.provider, "anthropic")
        XCTAssertEqual(decoded.model, "claude-3-sonnet")
        XCTAssertNil(decoded.inputTokens)
        XCTAssertNil(decoded.outputTokens)
        XCTAssertNil(decoded.totalLatency)
        XCTAssertEqual(decoded.wasFallback, true)
    }

    // MARK: - Backward Compatibility

    func testMessageWithoutMetadataDecodesOK() throws {
        // Simulate a message JSON from before metadata was added
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "role": "assistant",
            "content": "Hello, world!",
            "timestamp": "2024-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(Message.self, from: json)

        XCTAssertEqual(message.role, .assistant)
        XCTAssertEqual(message.content, "Hello, world!")
        XCTAssertNil(message.metadata)
    }

    func testMessageWithMetadataDecodesOK() throws {
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "role": "assistant",
            "content": "Response text",
            "timestamp": "2024-01-01T00:00:00Z",
            "metadata": {
                "provider": "openai",
                "model": "gpt-4o",
                "inputTokens": 100,
                "outputTokens": 50,
                "totalLatency": 1.5,
                "wasFallback": false
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(Message.self, from: json)

        XCTAssertEqual(message.role, .assistant)
        XCTAssertNotNil(message.metadata)
        XCTAssertEqual(message.metadata?.model, "gpt-4o")
        XCTAssertEqual(message.metadata?.inputTokens, 100)
    }

    // MARK: - MessageMetadata Display Helpers

    func testTotalTokensDisplay() {
        let metadata = MessageMetadata(
            provider: "openai", model: "gpt-4o",
            inputTokens: 500, outputTokens: 200,
            totalLatency: 1.0, wasFallback: false
        )
        XCTAssertEqual(metadata.totalTokensDisplay, "700")
    }

    func testTotalTokensDisplayWithNilTokens() {
        let metadata = MessageMetadata(
            provider: "openai", model: "gpt-4o",
            inputTokens: nil, outputTokens: nil,
            totalLatency: 1.0, wasFallback: false
        )
        XCTAssertEqual(metadata.totalTokensDisplay, "N/A")
    }

    func testLatencyDisplay() {
        let metadata = MessageMetadata(
            provider: "openai", model: "gpt-4o",
            inputTokens: 100, outputTokens: 50,
            totalLatency: 2.345, wasFallback: false
        )
        XCTAssertEqual(metadata.latencyDisplay, "2.3초")
    }

    func testLatencyDisplayNil() {
        let metadata = MessageMetadata(
            provider: "openai", model: "gpt-4o",
            inputTokens: 100, outputTokens: 50,
            totalLatency: nil, wasFallback: false
        )
        XCTAssertEqual(metadata.latencyDisplay, "N/A")
    }

    func testShortDisplay() {
        let metadata = MessageMetadata(
            provider: "openai", model: "gpt-4o",
            inputTokens: 100, outputTokens: 50,
            totalLatency: 1.5, wasFallback: false
        )
        XCTAssertEqual(metadata.shortDisplay, "gpt-4o · 1.5초")
    }

    func testShortDisplayWithoutLatency() {
        let metadata = MessageMetadata(
            provider: "openai", model: "gpt-4o",
            inputTokens: 100, outputTokens: 50,
            totalLatency: nil, wasFallback: false
        )
        XCTAssertEqual(metadata.shortDisplay, "gpt-4o")
    }

    // MARK: - wasFallback Flag

    func testWasFallbackFlag() throws {
        let metadata = MessageMetadata(
            provider: "anthropic", model: "claude-3-haiku",
            inputTokens: 100, outputTokens: 50,
            totalLatency: 0.8, wasFallback: true
        )

        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(MessageMetadata.self, from: data)

        XCTAssertTrue(decoded.wasFallback)
    }

    // MARK: - Equatable

    func testEquatable() {
        let a = MessageMetadata(
            provider: "openai", model: "gpt-4o",
            inputTokens: 100, outputTokens: 50,
            totalLatency: 1.0, wasFallback: false
        )
        let b = MessageMetadata(
            provider: "openai", model: "gpt-4o",
            inputTokens: 100, outputTokens: 50,
            totalLatency: 1.0, wasFallback: false
        )
        XCTAssertEqual(a, b)
    }

    // MARK: - Message Roundtrip with Metadata

    func testMessageRoundtripWithMetadata() throws {
        let metadata = MessageMetadata(
            provider: "openai", model: "gpt-4o",
            inputTokens: 300, outputTokens: 150,
            totalLatency: 2.0, wasFallback: false
        )
        let message = Message(
            role: .assistant,
            content: "Test response",
            metadata: metadata
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Message.self, from: data)

        XCTAssertEqual(decoded.content, "Test response")
        XCTAssertEqual(decoded.metadata?.provider, "openai")
        XCTAssertEqual(decoded.metadata?.model, "gpt-4o")
        XCTAssertEqual(decoded.metadata?.inputTokens, 300)
        XCTAssertEqual(decoded.metadata?.outputTokens, 150)
        XCTAssertEqual(decoded.metadata?.totalLatency, 2.0)
        XCTAssertFalse(decoded.metadata!.wasFallback)
    }
}
