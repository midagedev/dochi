import XCTest
@testable import Dochi

final class LocalLLMTests: XCTestCase {

    // MARK: - LLMProvider Extensions

    func testLMStudioProviderProperties() {
        let provider = LLMProvider.lmStudio

        XCTAssertEqual(provider.displayName, "LM Studio")
        XCTAssertEqual(provider.rawValue, "lmStudio")
        XCTAssertFalse(provider.requiresAPIKey)
        XCTAssertTrue(provider.isLocal)
        XCTAssertTrue(provider.models.isEmpty, "LM Studio models should be dynamic")
        XCTAssertTrue(provider.apiURL.absoluteString.contains("localhost:1234"))
    }

    func testOllamaIsLocal() {
        XCTAssertTrue(LLMProvider.ollama.isLocal)
        XCTAssertFalse(LLMProvider.ollama.requiresAPIKey)
    }

    func testCloudProvidersAreNotLocal() {
        XCTAssertFalse(LLMProvider.openai.isLocal)
        XCTAssertFalse(LLMProvider.anthropic.isLocal)
        XCTAssertFalse(LLMProvider.zai.isLocal)
    }

    func testCloudProvidersFilter() {
        let cloud = LLMProvider.cloudProviders
        XCTAssertTrue(cloud.contains(.openai))
        XCTAssertTrue(cloud.contains(.anthropic))
        XCTAssertTrue(cloud.contains(.zai))
        XCTAssertFalse(cloud.contains(.ollama))
        XCTAssertFalse(cloud.contains(.lmStudio))
    }

    func testLocalProvidersFilter() {
        let local = LLMProvider.localProviders
        XCTAssertTrue(local.contains(.ollama))
        XCTAssertTrue(local.contains(.lmStudio))
        XCTAssertFalse(local.contains(.openai))
        XCTAssertFalse(local.contains(.anthropic))
        XCTAssertFalse(local.contains(.zai))
    }

    func testLMStudioContextWindow() {
        let tokens = LLMProvider.lmStudio.contextWindowTokens(for: "any-model")
        XCTAssertEqual(tokens, 128_000)
    }

    func testProviderCaseIterableIncludesLMStudio() {
        XCTAssertTrue(LLMProvider.allCases.contains(.lmStudio))
        XCTAssertEqual(LLMProvider.allCases.count, 5)
    }

    func testProviderRawValueRoundtrip() {
        let provider = LLMProvider.lmStudio
        let encoded = provider.rawValue
        let decoded = LLMProvider(rawValue: encoded)
        XCTAssertEqual(decoded, provider)
    }

    // MARK: - LocalModelInfo

    func testLocalModelInfoFormattedSize() {
        let model = LocalModelInfo(
            name: "llama3:8b",
            size: 4_500_000_000,
            parameterSize: "8B",
            quantization: "Q4_K_M",
            family: "llama",
            supportsTools: true
        )

        XCTAssertEqual(model.id, "llama3:8b")
        XCTAssertFalse(model.formattedSize.isEmpty)
        XCTAssertTrue(model.formattedSize.contains("GB") || model.formattedSize.contains("4"))
    }

    func testLocalModelInfoCompactDescription() {
        let model = LocalModelInfo(
            name: "mistral:7b",
            size: 3_800_000_000,
            parameterSize: "7B",
            quantization: "Q4_K_M",
            family: "mistral",
            supportsTools: true
        )

        let desc = model.compactDescription
        XCTAssertTrue(desc.contains("7B"))
        XCTAssertTrue(desc.contains("Q4_K_M"))
    }

    func testLocalModelInfoCompactDescriptionEmpty() {
        let model = LocalModelInfo(
            name: "test",
            size: 0,
            parameterSize: nil,
            quantization: nil,
            family: nil,
            supportsTools: false
        )

        XCTAssertEqual(model.compactDescription, "")
    }

    func testLocalModelInfoCodable() throws {
        let original = LocalModelInfo(
            name: "llama3:8b",
            size: 4_500_000_000,
            parameterSize: "8B",
            quantization: "Q4_K_M",
            family: "llama",
            supportsTools: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LocalModelInfo.self, from: data)

        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.size, original.size)
        XCTAssertEqual(decoded.parameterSize, original.parameterSize)
        XCTAssertEqual(decoded.quantization, original.quantization)
        XCTAssertEqual(decoded.family, original.family)
        XCTAssertEqual(decoded.supportsTools, original.supportsTools)
    }

    // MARK: - LocalServerStatus

    func testLocalServerStatusValues() {
        XCTAssertEqual(LocalServerStatus.unknown.rawValue, "unknown")
        XCTAssertEqual(LocalServerStatus.connected.rawValue, "connected")
        XCTAssertEqual(LocalServerStatus.disconnected.rawValue, "disconnected")
        XCTAssertEqual(LocalServerStatus.checking.rawValue, "checking")
    }

    // MARK: - LMStudioAdapter

    @MainActor
    func testLMStudioAdapterRequestNoAuth() throws {
        let adapter = LMStudioAdapter()
        let request = try adapter.buildRequest(
            messages: [],
            systemPrompt: "System",
            model: "test-model",
            tools: nil,
            apiKey: ""
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertTrue(request.url?.absoluteString.contains("localhost:1234") ?? false)
    }

    @MainActor
    func testLMStudioAdapterRequestWithOptionalAuth() throws {
        let adapter = LMStudioAdapter()
        let request = try adapter.buildRequest(
            messages: [],
            systemPrompt: "",
            model: "test-model",
            tools: nil,
            apiKey: "custom-key"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer custom-key")
    }

    @MainActor
    func testLMStudioAdapterRequestBody() throws {
        let adapter = LMStudioAdapter()
        let messages = [Message(role: .user, content: "Hello")]
        let request = try adapter.buildRequest(
            messages: messages,
            systemPrompt: "Be helpful",
            model: "local-model",
            tools: nil,
            apiKey: ""
        )

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "local-model")
        XCTAssertEqual(body["stream"] as? Bool, true)

        let apiMessages = body["messages"] as! [[String: Any]]
        XCTAssertEqual(apiMessages[0]["role"] as? String, "system")
        XCTAssertEqual(apiMessages[0]["content"] as? String, "Be helpful")
        XCTAssertEqual(apiMessages[1]["role"] as? String, "user")
        XCTAssertEqual(apiMessages[1]["content"] as? String, "Hello")
    }

    @MainActor
    func testLMStudioAdapterRequestWithTools() throws {
        let adapter = LMStudioAdapter()
        let tools: [[String: Any]] = [
            ["type": "function", "function": ["name": "test", "description": "A test tool"]]
        ]
        let request = try adapter.buildRequest(
            messages: [],
            systemPrompt: "",
            model: "test-model",
            tools: tools,
            apiKey: ""
        )

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertNotNil(body["tools"])
    }

    @MainActor
    func testLMStudioAdapterCustomBaseURL() throws {
        var adapter = LMStudioAdapter()
        adapter.baseURL = URL(string: "http://192.168.1.100:5000/v1/chat/completions")!

        let request = try adapter.buildRequest(
            messages: [],
            systemPrompt: "",
            model: "test",
            tools: nil,
            apiKey: ""
        )

        XCTAssertEqual(request.url?.absoluteString, "http://192.168.1.100:5000/v1/chat/completions")
    }

    func testLMStudioAdapterUsesOpenAIParsing() {
        let adapter = LMStudioAdapter()
        var acc = StreamAccumulator()

        let line = #"data: {"choices":[{"delta":{"content":"Hello"},"index":0}]}"#
        let event = adapter.parseSSELine(line, accumulated: &acc)

        if case .partial(let text) = event {
            XCTAssertEqual(text, "Hello")
        } else {
            XCTFail("Expected .partial, got \(String(describing: event))")
        }
    }

    func testLMStudioAdapterParseDone() {
        let adapter = LMStudioAdapter()
        var acc = StreamAccumulator()

        let event = adapter.parseSSELine("data: [DONE]", accumulated: &acc)
        if case .done = event {
            // success
        } else {
            XCTFail("Expected .done")
        }
    }

    func testLMStudioAdapterProvider() {
        let adapter = LMStudioAdapter()
        XCTAssertEqual(adapter.provider, .lmStudio)
    }

    // MARK: - Ollama Tool Support Detection

    func testOllamaToolDetectionByFamily() {
        XCTAssertTrue(OllamaModelFetcher.detectToolSupport(modelName: "some-model", family: "llama"))
        XCTAssertTrue(OllamaModelFetcher.detectToolSupport(modelName: "some-model", family: "mistral"))
        XCTAssertTrue(OllamaModelFetcher.detectToolSupport(modelName: "some-model", family: "qwen2"))
        XCTAssertTrue(OllamaModelFetcher.detectToolSupport(modelName: "some-model", family: "command-r"))
        XCTAssertFalse(OllamaModelFetcher.detectToolSupport(modelName: "some-model", family: "phi"))
    }

    func testOllamaToolDetectionByModelName() {
        XCTAssertTrue(OllamaModelFetcher.detectToolSupport(modelName: "llama3.1:8b", family: nil))
        XCTAssertTrue(OllamaModelFetcher.detectToolSupport(modelName: "mistral:7b", family: nil))
        XCTAssertTrue(OllamaModelFetcher.detectToolSupport(modelName: "qwen2.5:14b", family: nil))
        XCTAssertFalse(OllamaModelFetcher.detectToolSupport(modelName: "phi3:mini", family: nil))
        XCTAssertFalse(OllamaModelFetcher.detectToolSupport(modelName: "starcoder2", family: nil))
    }

    func testOllamaToolDetectionFamilyTakesPriority() {
        // Even if model name doesn't match, family should trigger support
        XCTAssertTrue(OllamaModelFetcher.detectToolSupport(modelName: "custom-model", family: "llama"))
    }

    // MARK: - ModelRouter Offline Fallback

    @MainActor
    func testModelRouterResolveOfflineFallback() {
        let settings = AppSettings()
        settings.offlineFallbackEnabled = true
        settings.offlineFallbackProvider = "ollama"
        settings.offlineFallbackModel = "llama3:8b"

        let mockKeychain = MockKeychainService()
        let router = ModelRouter(settings: settings, keychainService: mockKeychain)

        let resolved = router.resolveOfflineFallback()
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.provider, .ollama)
        XCTAssertEqual(resolved?.model, "llama3:8b")
        XCTAssertTrue(resolved?.isFallback ?? false)
    }

    @MainActor
    func testModelRouterResolveOfflineFallbackDisabled() {
        let settings = AppSettings()
        settings.offlineFallbackEnabled = false
        settings.offlineFallbackProvider = "ollama"
        settings.offlineFallbackModel = "llama3:8b"

        let mockKeychain = MockKeychainService()
        let router = ModelRouter(settings: settings, keychainService: mockKeychain)

        let resolved = router.resolveOfflineFallback()
        XCTAssertNil(resolved, "Should return nil when offline fallback is disabled")
    }

    @MainActor
    func testModelRouterResolveOfflineFallbackNoModel() {
        let settings = AppSettings()
        settings.offlineFallbackEnabled = true
        settings.offlineFallbackProvider = "ollama"
        settings.offlineFallbackModel = ""

        let mockKeychain = MockKeychainService()
        let router = ModelRouter(settings: settings, keychainService: mockKeychain)

        let resolved = router.resolveOfflineFallback()
        XCTAssertNil(resolved, "Should return nil when no fallback model is configured")
    }

    @MainActor
    func testModelRouterResolveOfflineFallbackCloudProvider() {
        let settings = AppSettings()
        settings.offlineFallbackEnabled = true
        settings.offlineFallbackProvider = "openai" // Not local
        settings.offlineFallbackModel = "gpt-4o"

        let mockKeychain = MockKeychainService()
        let router = ModelRouter(settings: settings, keychainService: mockKeychain)

        let resolved = router.resolveOfflineFallback()
        XCTAssertNil(resolved, "Should return nil when fallback provider is cloud (not local)")
    }

    @MainActor
    func testModelRouterResolveOfflineFallbackLMStudio() {
        let settings = AppSettings()
        settings.offlineFallbackEnabled = true
        settings.offlineFallbackProvider = "lmStudio"
        settings.offlineFallbackModel = "local-model"

        let mockKeychain = MockKeychainService()
        let router = ModelRouter(settings: settings, keychainService: mockKeychain)

        let resolved = router.resolveOfflineFallback()
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.provider, .lmStudio)
        XCTAssertEqual(resolved?.model, "local-model")
    }

    // MARK: - ModelRouter Network Error Detection

    func testIsNetworkErrorForLLMErrors() {
        XCTAssertTrue(ModelRouter.isNetworkError(LLMError.networkError("connection refused")))
        XCTAssertTrue(ModelRouter.isNetworkError(LLMError.timeout))
        XCTAssertFalse(ModelRouter.isNetworkError(LLMError.noAPIKey))
        XCTAssertFalse(ModelRouter.isNetworkError(LLMError.authenticationFailed))
        XCTAssertFalse(ModelRouter.isNetworkError(LLMError.cancelled))
    }

    func testIsNetworkErrorForURLErrors() {
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
        XCTAssertTrue(ModelRouter.isNetworkError(urlError))

        let otherError = NSError(domain: "com.test", code: 1, userInfo: nil)
        XCTAssertFalse(ModelRouter.isNetworkError(otherError))
    }

    // MARK: - LLMService Adapter Registration

    @MainActor
    func testLLMServiceHasLMStudioAdapter() async throws {
        let service = LLMService()

        // Verify by attempting to send with .lmStudio provider
        // This will fail because there's no actual server, but it should NOT throw "Unknown provider"
        do {
            _ = try await service.send(
                messages: [Message(role: .user, content: "test")],
                systemPrompt: "",
                model: "test-model",
                provider: .lmStudio,
                apiKey: "",
                tools: nil,
                onPartial: { _ in }
            )
            // If we somehow get here, that's unexpected but OK
        } catch let error as LLMError {
            // We expect a network error or timeout since no server is running,
            // but NOT an "Unknown provider" error
            if case .invalidResponse(let msg) = error {
                XCTAssertFalse(msg.contains("Unknown provider"), "LM Studio adapter should be registered")
            }
            // Any other LLMError is fine (network error, timeout, etc.)
        } catch {
            // Other errors (like network) are expected
        }
    }

    // MARK: - AppSettings

    @MainActor
    func testAppSettingsOfflineFallbackDefaults() {
        let settings = AppSettings()
        // Note: These may be affected by UserDefaults state from other tests,
        // but the defaults should be reasonable
        XCTAssertEqual(settings.lmStudioBaseURL.isEmpty, false)
        XCTAssertTrue(settings.lmStudioBaseURL.contains("localhost:1234"))
    }

    // MARK: - LLMService Custom Base URL (C-2)

    @MainActor
    func testLLMServiceUsesCustomOllamaBaseURL() async throws {
        let settings = AppSettings()
        let originalURL = settings.ollamaBaseURL
        defer { settings.ollamaBaseURL = originalURL } // Restore after test
        // Use localhost with unlikely port — connection refused is fast (no TCP timeout)
        settings.ollamaBaseURL = "http://127.0.0.1:19999"
        let service = LLMService(settings: settings)

        // Attempt a request to Ollama — it will fail (no server) but we can verify
        // the error is NOT "Unknown provider" (adapter resolves correctly)
        do {
            _ = try await service.send(
                messages: [Message(role: .user, content: "test")],
                systemPrompt: "",
                model: "test-model",
                provider: .ollama,
                apiKey: "",
                tools: nil,
                onPartial: { _ in }
            )
        } catch let error as LLMError {
            if case .invalidResponse(let msg) = error {
                XCTAssertFalse(msg.contains("Unknown provider"), "Ollama adapter should resolve with custom base URL")
            }
            // Network/timeout errors are expected since no server is running
        } catch {
            // Network errors are expected
        }
    }

    @MainActor
    func testLLMServiceUsesCustomLMStudioBaseURL() async throws {
        let settings = AppSettings()
        let originalURL = settings.lmStudioBaseURL
        defer { settings.lmStudioBaseURL = originalURL } // Restore after test
        // Use localhost with unlikely port — connection refused is fast (no TCP timeout)
        settings.lmStudioBaseURL = "http://127.0.0.1:19998"
        let service = LLMService(settings: settings)

        do {
            _ = try await service.send(
                messages: [Message(role: .user, content: "test")],
                systemPrompt: "",
                model: "test-model",
                provider: .lmStudio,
                apiKey: "",
                tools: nil,
                onPartial: { _ in }
            )
        } catch let error as LLMError {
            if case .invalidResponse(let msg) = error {
                XCTAssertFalse(msg.contains("Unknown provider"), "LM Studio adapter should resolve with custom base URL")
            }
        } catch {
            // Network errors are expected
        }
    }

    @MainActor
    func testLLMServiceWithoutSettingsUsesDefaultBaseURL() async throws {
        // When no settings are provided, adapters use the default base URL
        let service = LLMService()

        do {
            _ = try await service.send(
                messages: [Message(role: .user, content: "test")],
                systemPrompt: "",
                model: "test-model",
                provider: .ollama,
                apiKey: "",
                tools: nil,
                onPartial: { _ in }
            )
        } catch let error as LLMError {
            if case .invalidResponse(let msg) = error {
                XCTAssertFalse(msg.contains("Unknown provider"), "Ollama adapter should resolve without settings")
            }
        } catch {
            // Network errors are expected
        }
    }

    // MARK: - OllamaAdapter Custom Base URL

    @MainActor
    func testOllamaAdapterCustomBaseURL() throws {
        var adapter = OllamaAdapter()
        adapter.baseURL = URL(string: "http://192.168.1.100:11434/v1/chat/completions")!

        let request = try adapter.buildRequest(
            messages: [],
            systemPrompt: "",
            model: "test",
            tools: nil,
            apiKey: ""
        )

        XCTAssertEqual(request.url?.absoluteString, "http://192.168.1.100:11434/v1/chat/completions")
    }

    @MainActor
    func testOllamaAdapterDefaultBaseURL() throws {
        let adapter = OllamaAdapter()

        let request = try adapter.buildRequest(
            messages: [],
            systemPrompt: "",
            model: "test",
            tools: nil,
            apiKey: ""
        )

        // Should use default Ollama URL
        XCTAssertTrue(request.url?.absoluteString.contains("localhost:11434") ?? false)
    }
}
