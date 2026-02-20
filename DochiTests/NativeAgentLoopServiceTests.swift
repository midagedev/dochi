import XCTest
@testable import Dochi

final class NativeAgentLoopServiceTests: XCTestCase {
    func testNativeAgentLoopServiceRoutesToMatchingProviderAdapter() async throws {
        let anthropicAdapter = StubNativeLLMProviderAdapter(
            provider: .anthropic,
            events: [.partial("anthropic"), .done(text: "anthropic")]
        )
        let openAIAdapter = StubNativeLLMProviderAdapter(
            provider: .openai,
            events: [.partial("openai"), .done(text: "openai")]
        )

        let service = NativeAgentLoopService(adapters: [anthropicAdapter, openAIAdapter])

        let anthropicEvents = try await collectEvents(from: service.run(request: makeRequest(provider: .anthropic)))
        XCTAssertEqual(anthropicEvents.first?.text, "anthropic")

        let openAIEvents = try await collectEvents(from: service.run(request: makeRequest(provider: .openai)))
        XCTAssertEqual(openAIEvents.first?.text, "openai")
    }

    func testNativeAgentLoopServiceReturnsUnsupportedProviderError() async {
        let service = NativeAgentLoopService(adapters: [
            StubNativeLLMProviderAdapter(
                provider: .anthropic,
                events: [.done(text: nil)]
            ),
        ])

        do {
            _ = try await collectEvents(from: service.run(request: makeRequest(provider: .zai)))
            XCTFail("Expected NativeLLMError.unsupportedProvider")
        } catch let error as NativeLLMError {
            XCTAssertEqual(error.code, .unsupportedProvider)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

private extension NativeAgentLoopServiceTests {
    func makeRequest(provider: LLMProvider) -> NativeLLMRequest {
        NativeLLMRequest(
            provider: provider,
            model: "test-model",
            apiKey: "test-key",
            messages: [.init(role: .user, text: "hello")]
        )
    }

    func collectEvents(
        from stream: AsyncThrowingStream<NativeLLMStreamEvent, Error>
    ) async throws -> [NativeLLMStreamEvent] {
        var events: [NativeLLMStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }
}

private struct StubNativeLLMProviderAdapter: NativeLLMProviderAdapter {
    let provider: LLMProvider
    let events: [NativeLLMStreamEvent]

    func stream(request _: NativeLLMRequest) -> AsyncThrowingStream<NativeLLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}
