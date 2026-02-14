import Foundation
import os

/// Internal result carrying both the LLM response and usage data from the stream.
private struct StreamResult: Sendable {
    let response: LLMResponse
    let inputTokens: Int?
    let outputTokens: Int?
}

@MainActor
final class LLMService: LLMServiceProtocol {
    private var currentTask: Task<StreamResult, Error>?
    private let session: URLSession

    private(set) var lastMetrics: ExchangeMetrics?

    private let adapters: [LLMProvider: any LLMProviderAdapter] = [
        .openai: OpenAIAdapter(),
        .anthropic: AnthropicAdapter(),
        .zai: ZAIAdapter(),
        .ollama: OllamaAdapter(),
    ]

    /// Max retries for transient errors (5xx, timeout).
    private nonisolated(unsafe) static let maxRetries = 2
    /// Backoff durations per retry attempt.
    private nonisolated(unsafe) static let retryBackoffs: [Duration] = [.milliseconds(250), .milliseconds(750)]
    /// First-byte timeout.
    private nonisolated(unsafe) static let firstByteTimeout: Duration = .seconds(20)
    /// Full exchange soft limit.
    private nonisolated(unsafe) static let exchangeTimeout: Duration = .seconds(60)

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 70 // slightly above exchange timeout
        config.timeoutIntervalForResource = 70
        self.session = URLSession(configuration: config)
    }

    func send(
        messages: [Message],
        systemPrompt: String,
        model: String,
        provider: LLMProvider,
        apiKey: String,
        tools: [[String: Any]]?,
        onPartial: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> LLMResponse {
        guard !apiKey.isEmpty || !provider.requiresAPIKey else {
            throw LLMError.noAPIKey
        }

        guard let adapter = adapters[provider] else {
            throw LLMError.invalidResponse("Unknown provider: \(provider.rawValue)")
        }

        // Cancel any previous request
        currentTask?.cancel()

        let exchangeStart = ContinuousClock.now

        let task = Task<StreamResult, Error> {
            try await performWithRetry(
                messages: messages,
                systemPrompt: systemPrompt,
                model: model,
                apiKey: apiKey,
                tools: tools,
                adapter: adapter,
                onPartial: onPartial
            )
        }
        currentTask = task

        // Exchange timeout: cancel the task after the soft limit
        let timeoutTask = Task {
            try await Task.sleep(for: Self.exchangeTimeout)
            task.cancel()
        }

        do {
            let streamResult = try await task.value
            timeoutTask.cancel()
            currentTask = nil

            // Build metrics
            let elapsed = ContinuousClock.now - exchangeStart
            lastMetrics = ExchangeMetrics(
                provider: provider.rawValue,
                model: model,
                inputTokens: streamResult.inputTokens,
                outputTokens: streamResult.outputTokens,
                totalTokens: nil,
                firstByteLatency: nil,
                totalLatency: elapsed.seconds,
                timestamp: Date(),
                wasFallback: false
            )

            return streamResult.response
        } catch {
            timeoutTask.cancel()
            currentTask = nil

            // Record partial metrics even on failure (for diagnostics)
            let elapsed = ContinuousClock.now - exchangeStart
            lastMetrics = ExchangeMetrics(
                provider: provider.rawValue,
                model: model,
                inputTokens: nil,
                outputTokens: nil,
                totalTokens: nil,
                firstByteLatency: nil,
                totalLatency: elapsed.seconds,
                timestamp: Date(),
                wasFallback: false
            )

            // If the task was cancelled by the exchange timeout, report as timeout
            if Task.isCancelled {
                throw LLMError.timeout
            }
            throw error
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        Log.llm.info("LLM request cancelled")
    }

    // MARK: - Retry Logic

    /// Retry wrapper. Only retries transient (5xx, timeout) errors.
    /// Never retries if tool results are involved (non-idempotent).
    private nonisolated func performWithRetry(
        messages: [Message],
        systemPrompt: String,
        model: String,
        apiKey: String,
        tools: [[String: Any]]?,
        adapter: any LLMProviderAdapter,
        onPartial: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> StreamResult {
        let hasToolResults = messages.contains { $0.role == .tool }
        var lastError: Error = LLMError.emptyResponse

        let maxAttempts = hasToolResults ? 1 : (Self.maxRetries + 1)

        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()

            if attempt > 0 {
                let backoffIndex = min(attempt - 1, Self.retryBackoffs.count - 1)
                let backoff = Self.retryBackoffs[backoffIndex]
                Log.llm.info("Retrying LLM request (attempt \(attempt + 1)) after \(backoff)")
                try await Task.sleep(for: backoff)
            }

            do {
                return try await performStream(
                    messages: messages,
                    systemPrompt: systemPrompt,
                    model: model,
                    apiKey: apiKey,
                    tools: tools,
                    adapter: adapter,
                    onPartial: onPartial
                )
            } catch let error as LLMError {
                lastError = error
                switch error {
                case .serverError, .timeout, .networkError:
                    // Transient — retry if allowed
                    Log.llm.warning("Transient LLM error (attempt \(attempt + 1)): \(error.localizedDescription, privacy: .public)")
                    continue
                case .rateLimited(let retryAfter):
                    // Rate limited: respect Retry-After or default 5s, 1 retry only
                    if attempt == 0 {
                        let wait = retryAfter ?? 5.0
                        Log.llm.warning("Rate limited, waiting \(wait)s")
                        try await Task.sleep(for: .seconds(wait))
                        continue
                    }
                    throw error
                default:
                    // Non-transient: auth, model not found, etc.
                    throw error
                }
            } catch is CancellationError {
                throw LLMError.cancelled
            } catch {
                lastError = error
                if (error as NSError).domain == NSURLErrorDomain {
                    // URL errors might be transient
                    Log.llm.warning("Network error (attempt \(attempt + 1)): \(error.localizedDescription)")
                    continue
                }
                throw error
            }
        }

        throw lastError
    }

    // MARK: - Streaming

    private nonisolated func performStream(
        messages: [Message],
        systemPrompt: String,
        model: String,
        apiKey: String,
        tools: [[String: Any]]?,
        adapter: any LLMProviderAdapter,
        onPartial: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> StreamResult {
        let request = try adapter.buildRequest(
            messages: messages,
            systemPrompt: systemPrompt,
            model: model,
            tools: tools,
            apiKey: apiKey
        )

        Log.llm.debug("Sending \(adapter.provider.displayName) request to \(request.url?.absoluteString ?? "nil")")

        // Start the data task and race with first-byte timeout
        let (asyncBytes, response) = try await withFirstByteTimeout(request: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse("Not an HTTP response")
        }

        // Handle error status codes
        if !(200..<300).contains(httpResponse.statusCode) {
            // Read error body for debugging
            var errorBody = ""
            for try await line in asyncBytes.lines {
                errorBody += line
                if errorBody.count > 500 { break }
            }
            Log.llm.error("HTTP \(httpResponse.statusCode, privacy: .public) error body: \(errorBody, privacy: .public)")
        }
        try Self.checkHTTPStatus(httpResponse)

        // Parse SSE stream (use .lines for proper UTF-8 decoding)
        var accumulated = StreamAccumulator()

        for try await line in asyncBytes.lines {
            try Task.checkCancellation()

            if line.isEmpty { continue }

            if let event = adapter.parseSSELine(line, accumulated: &accumulated) {
                switch event {
                case .partial(let text):
                    await onPartial(text)
                case .toolCallDelta:
                    break // accumulated in the StreamAccumulator
                case .done:
                    return buildStreamResult(from: accumulated)
                case .error(let error):
                    throw error
                }
            }
        }

        // Stream ended without explicit [DONE] — return what we have
        let result = buildStreamResult(from: accumulated)
        if case .text(let t) = result.response, t.isEmpty {
            throw LLMError.emptyResponse
        }
        return result
    }

    /// Race URL data stream against first-byte timeout.
    private nonisolated func withFirstByteTimeout(
        request: URLRequest
    ) async throws -> (URLSession.AsyncBytes, URLResponse) {
        try await withThrowingTaskGroup(of: (URLSession.AsyncBytes, URLResponse).self) { group in
            group.addTask {
                try await self.session.bytes(for: request)
            }

            group.addTask {
                try await Task.sleep(for: Self.firstByteTimeout)
                throw LLMError.timeout
            }

            // First to complete wins
            guard let result = try await group.next() else {
                throw LLMError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Response Building

    private nonisolated func buildStreamResult(from accumulated: StreamAccumulator) -> StreamResult {
        let toolCalls = accumulated.completedToolCalls
        let response: LLMResponse = !toolCalls.isEmpty ? .toolCalls(toolCalls) : .text(accumulated.text)
        return StreamResult(
            response: response,
            inputTokens: accumulated.inputTokens,
            outputTokens: accumulated.outputTokens
        )
    }

    // MARK: - HTTP Error Handling

    private nonisolated static func checkHTTPStatus(_ response: HTTPURLResponse) throws {
        let code = response.statusCode
        guard !(200..<300).contains(code) else { return }

        switch code {
        case 401, 403:
            throw LLMError.authenticationFailed
        case 404:
            throw LLMError.modelNotFound("(HTTP 404)")
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            throw LLMError.rateLimited(retryAfter: retryAfter)
        case 500...599:
            throw LLMError.serverError(code, HTTPURLResponse.localizedString(forStatusCode: code))
        default:
            throw LLMError.invalidResponse("HTTP \(code)")
        }
    }
}

// MARK: - Duration Extension

private extension Swift.Duration {
    var seconds: TimeInterval {
        let (s, atto) = components
        return TimeInterval(s) + TimeInterval(atto) / 1_000_000_000_000_000_000
    }
}
