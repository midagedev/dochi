import Foundation
import XCTest
@testable import Dochi

final class AnthropicProviderContractTests: XCTestCase {
    func testTextScenario() async throws {
        try await ProviderContractHarness.runTextScenario(for: .anthropic)
    }

    func testToolScenario() async throws {
        try await ProviderContractHarness.runToolScenario(for: .anthropic)
    }

    func testErrorScenario() async throws {
        try await ProviderContractHarness.runErrorScenario(for: .anthropic)
    }

    func testCancelScenario() async throws {
        try await ProviderContractHarness.runCancelScenario(for: .anthropic)
    }
}

final class OpenAIProviderContractTests: XCTestCase {
    func testTextScenario() async throws {
        try await ProviderContractHarness.runTextScenario(for: .openai)
    }

    func testToolScenario() async throws {
        try await ProviderContractHarness.runToolScenario(for: .openai)
    }

    func testErrorScenario() async throws {
        try await ProviderContractHarness.runErrorScenario(for: .openai)
    }

    func testCancelScenario() async throws {
        try await ProviderContractHarness.runCancelScenario(for: .openai)
    }
}

final class ZAIProviderContractTests: XCTestCase {
    func testTextScenario() async throws {
        try await ProviderContractHarness.runTextScenario(for: .zai)
    }

    func testToolScenario() async throws {
        try await ProviderContractHarness.runToolScenario(for: .zai)
    }

    func testErrorScenario() async throws {
        try await ProviderContractHarness.runErrorScenario(for: .zai)
    }

    func testCancelScenario() async throws {
        try await ProviderContractHarness.runCancelScenario(for: .zai)
    }
}

final class OllamaProviderContractTests: XCTestCase {
    func testTextScenario() async throws {
        try await ProviderContractHarness.runTextScenario(for: .ollama)
    }

    func testToolScenario() async throws {
        try await ProviderContractHarness.runToolScenario(for: .ollama)
    }

    func testErrorScenario() async throws {
        try await ProviderContractHarness.runErrorScenario(for: .ollama)
    }

    func testCancelScenario() async throws {
        try await ProviderContractHarness.runCancelScenario(for: .ollama)
    }
}

final class LMStudioProviderContractTests: XCTestCase {
    func testTextScenario() async throws {
        try await ProviderContractHarness.runTextScenario(for: .lmStudio)
    }

    func testToolScenario() async throws {
        try await ProviderContractHarness.runToolScenario(for: .lmStudio)
    }

    func testErrorScenario() async throws {
        try await ProviderContractHarness.runErrorScenario(for: .lmStudio)
    }

    func testCancelScenario() async throws {
        try await ProviderContractHarness.runCancelScenario(for: .lmStudio)
    }
}

private enum ProviderContractHarness {
    private struct ProviderCase {
        let provider: LLMProvider
        let model: String
        let apiKey: String?
        let textFixture: String
        let toolFixture: String
        let errorFixture: String
        let errorStatusCode: Int
        let errorHeaders: [String: String]
        let expectedErrorCode: NativeLLMErrorCode
    }

    private static let partialText = "contract-text"
    private static let toolName = "calendar.create"
    private static let toolCallId = "call_1"

    static func runTextScenario(for provider: LLMProvider) async throws {
        let providerCase = try resolveCase(provider)
        let fixtureData = try fixture(named: providerCase.textFixture)
        let httpClient = ProviderContractMockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: fixtureData
        )

        let adapter = makeAdapter(for: providerCase.provider, httpClient: httpClient)
        let events = try await collectEvents(from: adapter.stream(request: makeRequest(from: providerCase)))

        XCTAssertTrue(events.contains(where: { $0.kind == .partial && $0.text == partialText }))
        XCTAssertTrue(events.contains(where: { $0.kind == .done }))
    }

    static func runToolScenario(for provider: LLMProvider) async throws {
        let providerCase = try resolveCase(provider)
        let fixtureData = try fixture(named: providerCase.toolFixture)
        let httpClient = ProviderContractMockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: fixtureData
        )

        let adapter = makeAdapter(for: providerCase.provider, httpClient: httpClient)
        let events = try await collectEvents(from: adapter.stream(request: makeRequest(from: providerCase)))

        XCTAssertTrue(events.contains(where: { event in
            event.kind == .toolUse &&
                event.toolName == toolName &&
                event.toolCallId == toolCallId
        }))
        XCTAssertTrue(events.contains(where: { $0.kind == .done }))
    }

    static func runErrorScenario(for provider: LLMProvider) async throws {
        let providerCase = try resolveCase(provider)
        let fixtureData = try fixture(named: providerCase.errorFixture)
        let httpClient = ProviderContractMockNativeLLMHTTPClient(
            statusCode: providerCase.errorStatusCode,
            headers: providerCase.errorHeaders,
            body: fixtureData
        )

        let adapter = makeAdapter(for: providerCase.provider, httpClient: httpClient)

        do {
            _ = try await collectEvents(from: adapter.stream(request: makeRequest(from: providerCase)))
            XCTFail("Expected NativeLLMError")
        } catch let error as NativeLLMError {
            XCTAssertEqual(error.code, providerCase.expectedErrorCode)
            XCTAssertEqual(error.statusCode, providerCase.errorStatusCode)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    static func runCancelScenario(for provider: LLMProvider) async throws {
        let providerCase = try resolveCase(provider)
        let httpClient = ProviderContractMockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: Data(),
            stubbedError: CancellationError()
        )

        let adapter = makeAdapter(for: providerCase.provider, httpClient: httpClient)

        do {
            _ = try await collectEvents(from: adapter.stream(request: makeRequest(from: providerCase)))
            XCTFail("Expected NativeLLMError")
        } catch let error as NativeLLMError {
            XCTAssertEqual(error.code, .cancelled)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    private static func resolveCase(_ provider: LLMProvider) throws -> ProviderCase {
        switch provider {
        case .anthropic:
            return ProviderCase(
                provider: .anthropic,
                model: "claude-sonnet-4-5-20250514",
                apiKey: "anthropic-test-key",
                textFixture: "anthropic_text.sse",
                toolFixture: "anthropic_tool.sse",
                errorFixture: "rate_limit_error.json",
                errorStatusCode: 429,
                errorHeaders: ["Retry-After": "3"],
                expectedErrorCode: .rateLimited
            )
        case .openai:
            return ProviderCase(
                provider: .openai,
                model: "gpt-4o-mini",
                apiKey: "openai-test-key",
                textFixture: "openai_text.sse",
                toolFixture: "openai_tool.sse",
                errorFixture: "rate_limit_error.json",
                errorStatusCode: 429,
                errorHeaders: ["Retry-After": "3"],
                expectedErrorCode: .rateLimited
            )
        case .zai:
            return ProviderCase(
                provider: .zai,
                model: "glm-5",
                apiKey: "zai-test-key",
                textFixture: "openai_text.sse",
                toolFixture: "openai_tool.sse",
                errorFixture: "rate_limit_error.json",
                errorStatusCode: 429,
                errorHeaders: ["Retry-After": "3"],
                expectedErrorCode: .rateLimited
            )
        case .ollama:
            return ProviderCase(
                provider: .ollama,
                model: "llama3.2",
                apiKey: nil,
                textFixture: "openai_text.sse",
                toolFixture: "openai_tool.sse",
                errorFixture: "server_error.json",
                errorStatusCode: 503,
                errorHeaders: [:],
                expectedErrorCode: .server
            )
        case .lmStudio:
            return ProviderCase(
                provider: .lmStudio,
                model: "qwen2.5-7b-instruct",
                apiKey: nil,
                textFixture: "openai_text.sse",
                toolFixture: "openai_tool.sse",
                errorFixture: "server_error.json",
                errorStatusCode: 500,
                errorHeaders: [:],
                expectedErrorCode: .server
            )
        default:
            throw XCTSkip("Provider \(provider.rawValue) is not in contract matrix scope")
        }
    }

    private static func fixture(named name: String) throws -> Data {
        let fixturesDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ProviderContract", isDirectory: true)
        let fixtureURL = fixturesDirectory.appendingPathComponent(name)
        return try Data(contentsOf: fixtureURL)
    }

    private static func makeAdapter(
        for provider: LLMProvider,
        httpClient: any NativeLLMHTTPClient
    ) -> any NativeLLMProviderAdapter {
        switch provider {
        case .anthropic:
            return AnthropicNativeLLMProviderAdapter(httpClient: httpClient)
        case .openai:
            return OpenAINativeLLMProviderAdapter(httpClient: httpClient)
        case .zai:
            return ZAINativeLLMProviderAdapter(httpClient: httpClient)
        case .ollama:
            return OllamaNativeLLMProviderAdapter(httpClient: httpClient)
        case .lmStudio:
            return LMStudioNativeLLMProviderAdapter(httpClient: httpClient)
        default:
            fatalError("Unsupported provider in matrix: \(provider.rawValue)")
        }
    }

    private static func makeRequest(from providerCase: ProviderCase) -> NativeLLMRequest {
        NativeLLMRequest(
            provider: providerCase.provider,
            model: providerCase.model,
            apiKey: providerCase.apiKey,
            systemPrompt: "contract test",
            messages: [
                NativeLLMMessage(role: .user, text: "안녕")
            ]
        )
    }

    private static func collectEvents(
        from stream: AsyncThrowingStream<NativeLLMStreamEvent, Error>
    ) async throws -> [NativeLLMStreamEvent] {
        var events: [NativeLLMStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }
}

private actor ProviderContractMockNativeLLMHTTPClient: NativeLLMHTTPClient {
    private let statusCode: Int
    private let headers: [String: String]
    private let body: Data
    private let stubbedError: Error?

    init(
        statusCode: Int,
        headers: [String: String],
        body: Data,
        stubbedError: Error? = nil
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.stubbedError = stubbedError
    }

    func send(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        if let stubbedError {
            throw stubbedError
        }

        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
              ) else {
            throw NativeLLMError(
                code: .invalidResponse,
                message: "Failed to build HTTPURLResponse in provider contract test",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }
        return (body, response)
    }
}
