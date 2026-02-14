import XCTest
@testable import Dochi

final class SystemStatusTests: XCTestCase {
    // MARK: - MessageMetadata Computed Properties

    func testShortDisplayWithBothModelAndLatency() {
        let metadata = MessageMetadata(
            provider: "anthropic",
            model: "claude-3-opus",
            inputTokens: 800,
            outputTokens: 400,
            totalLatency: 3.7,
            wasFallback: false
        )
        XCTAssertEqual(metadata.shortDisplay, "claude-3-opus \u{00B7} 3.7\u{CD08}")
    }

    func testShortDisplayWithOnlyModel() {
        let metadata = MessageMetadata(
            provider: "openai",
            model: "gpt-4o-mini",
            inputTokens: nil,
            outputTokens: nil,
            totalLatency: nil,
            wasFallback: true
        )
        // When latency is nil, latencyDisplay is "N/A" which is filtered out
        XCTAssertEqual(metadata.shortDisplay, "gpt-4o-mini")
    }

    func testTotalTokensDisplayWithValues() {
        let metadata = MessageMetadata(
            provider: "openai",
            model: "gpt-4o",
            inputTokens: 1000,
            outputTokens: 500,
            totalLatency: 2.0,
            wasFallback: false
        )
        XCTAssertEqual(metadata.totalTokensDisplay, "1500")
    }

    func testTotalTokensDisplayWithZeroTokens() {
        let metadata = MessageMetadata(
            provider: "openai",
            model: "gpt-4o",
            inputTokens: 0,
            outputTokens: 0,
            totalLatency: 1.0,
            wasFallback: false
        )
        XCTAssertEqual(metadata.totalTokensDisplay, "N/A")
    }

    func testTotalTokensDisplayWithOneNil() {
        let metadata = MessageMetadata(
            provider: "openai",
            model: "gpt-4o",
            inputTokens: 200,
            outputTokens: nil,
            totalLatency: 1.0,
            wasFallback: false
        )
        XCTAssertEqual(metadata.totalTokensDisplay, "200")
    }

    func testLatencyDisplayFormatting() {
        let metadata = MessageMetadata(
            provider: "zai",
            model: "z1-mini",
            inputTokens: 50,
            outputTokens: 30,
            totalLatency: 0.456,
            wasFallback: false
        )
        XCTAssertEqual(metadata.latencyDisplay, "0.5\u{CD08}")
    }

    // MARK: - MessageMetadata Codable Roundtrip

    func testMetadataCodableRoundtrip() throws {
        let original = MessageMetadata(
            provider: "anthropic",
            model: "claude-3-sonnet",
            inputTokens: 250,
            outputTokens: 120,
            totalLatency: 1.8,
            wasFallback: true
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MessageMetadata.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testMetadataCodableRoundtripWithNils() throws {
        let original = MessageMetadata(
            provider: "openai",
            model: "gpt-4o",
            inputTokens: nil,
            outputTokens: nil,
            totalLatency: nil,
            wasFallback: false
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MessageMetadata.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    // MARK: - Message with Metadata Codable Roundtrip

    func testMessageWithMetadataRoundtrip() throws {
        let metadata = MessageMetadata(
            provider: "openai",
            model: "gpt-4o",
            inputTokens: 400,
            outputTokens: 200,
            totalLatency: 2.5,
            wasFallback: false
        )
        let original = Message(
            role: .assistant,
            content: "Test assistant response with metadata",
            metadata: metadata
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Message.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.role, .assistant)
        XCTAssertEqual(decoded.content, "Test assistant response with metadata")
        XCTAssertNotNil(decoded.metadata)
        XCTAssertEqual(decoded.metadata, metadata)
    }

    // MARK: - Backwards Compatibility (Message without metadata)

    func testMessageWithoutMetadataFieldDecodes() throws {
        let json = """
        {
            "id": "AABBCCDD-1234-5678-9012-AABBCCDDEEFF",
            "role": "user",
            "content": "Hello from the past",
            "timestamp": "2023-06-15T10:30:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(Message.self, from: json)

        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.content, "Hello from the past")
        XCTAssertNil(message.metadata)
        XCTAssertNil(message.toolCalls)
        XCTAssertNil(message.toolCallId)
        XCTAssertNil(message.imageURLs)
    }

    func testMessageWithAllFieldsDecodes() throws {
        let json = """
        {
            "id": "AABBCCDD-1234-5678-9012-AABBCCDDEEFF",
            "role": "assistant",
            "content": "Here is the response",
            "timestamp": "2024-03-01T12:00:00Z",
            "metadata": {
                "provider": "anthropic",
                "model": "claude-3-haiku",
                "inputTokens": 50,
                "outputTokens": 25,
                "totalLatency": 0.9,
                "wasFallback": true
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(Message.self, from: json)

        XCTAssertEqual(message.role, .assistant)
        XCTAssertNotNil(message.metadata)
        XCTAssertEqual(message.metadata?.provider, "anthropic")
        XCTAssertEqual(message.metadata?.model, "claude-3-haiku")
        XCTAssertTrue(message.metadata!.wasFallback)
    }

    // MARK: - MessageMetadata Equatable

    func testMetadataNotEqualWhenDifferent() {
        let a = MessageMetadata(
            provider: "openai",
            model: "gpt-4o",
            inputTokens: 100,
            outputTokens: 50,
            totalLatency: 1.0,
            wasFallback: false
        )
        let b = MessageMetadata(
            provider: "openai",
            model: "gpt-4o",
            inputTokens: 100,
            outputTokens: 50,
            totalLatency: 1.0,
            wasFallback: true
        )
        XCTAssertNotEqual(a, b)
    }

    func testMetadataEqualWhenSame() {
        let a = MessageMetadata(
            provider: "openai",
            model: "gpt-4o",
            inputTokens: nil,
            outputTokens: nil,
            totalLatency: nil,
            wasFallback: false
        )
        let b = MessageMetadata(
            provider: "openai",
            model: "gpt-4o",
            inputTokens: nil,
            outputTokens: nil,
            totalLatency: nil,
            wasFallback: false
        )
        XCTAssertEqual(a, b)
    }

    // MARK: - SessionMetricsSummary

    @MainActor
    func testSessionMetricsSummaryEmpty() {
        let collector = MetricsCollector()
        let summary = collector.sessionSummary

        XCTAssertEqual(summary.totalExchanges, 0)
        XCTAssertEqual(summary.totalInputTokens, 0)
        XCTAssertEqual(summary.totalOutputTokens, 0)
        XCTAssertEqual(summary.averageLatency, 0)
        XCTAssertEqual(summary.fallbackCount, 0)
    }

    @MainActor
    func testSessionMetricsSummaryWithRecords() {
        let collector = MetricsCollector()

        let m1 = ExchangeMetrics(
            provider: "openai", model: "gpt-4o",
            inputTokens: 100, outputTokens: 50, totalTokens: 150,
            firstByteLatency: 0.3, totalLatency: 1.0,
            timestamp: Date(), wasFallback: false
        )
        let m2 = ExchangeMetrics(
            provider: "anthropic", model: "claude-3-sonnet",
            inputTokens: 200, outputTokens: 100, totalTokens: 300,
            firstByteLatency: 0.5, totalLatency: 2.0,
            timestamp: Date(), wasFallback: true
        )

        collector.record(m1)
        collector.record(m2)

        let summary = collector.sessionSummary
        XCTAssertEqual(summary.totalExchanges, 2)
        XCTAssertEqual(summary.totalInputTokens, 300)
        XCTAssertEqual(summary.totalOutputTokens, 150)
        XCTAssertEqual(summary.averageLatency, 1.5, accuracy: 0.01)
        XCTAssertEqual(summary.fallbackCount, 1)
    }

    // MARK: - AuthState Cases

    func testAuthStateIsSignedIn() {
        let signedIn = AuthState.signedIn(userId: UUID(), email: "test@example.com")
        XCTAssertTrue(signedIn.isSignedIn)

        let signedOut = AuthState.signedOut
        XCTAssertFalse(signedOut.isSignedIn)

        let signingIn = AuthState.signingIn
        XCTAssertFalse(signingIn.isSignedIn)
    }

    func testAuthStateUserId() {
        let id = UUID()
        let signedIn = AuthState.signedIn(userId: id, email: nil)
        XCTAssertEqual(signedIn.userId, id)

        let signedOut = AuthState.signedOut
        XCTAssertNil(signedOut.userId)
    }
}
