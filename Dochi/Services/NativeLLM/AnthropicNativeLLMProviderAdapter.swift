import Foundation

protocol NativeLLMHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse)
    func sendStreaming(_ request: URLRequest) async throws -> (lineStream: AsyncThrowingStream<String, Error>, response: HTTPURLResponse)
}

extension NativeLLMHTTPClient {
    func sendStreaming(_ request: URLRequest) async throws -> (lineStream: AsyncThrowingStream<String, Error>, response: HTTPURLResponse) {
        let (data, response) = try await send(request)
        let payload = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let lines = payload.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        return (
            lineStream: AsyncThrowingStream { continuation in
                for line in lines {
                    continuation.yield(line)
                }
                continuation.finish()
            },
            response: response
        )
    }
}

/// Byte-level async line iterator that preserves empty lines (unlike AsyncLineSequence/.lines which omits them).
/// Empty lines are critical for SSE parsing as they delimit events.
struct SSELineIterator: AsyncSequence {
    typealias Element = String
    let bytes: URLSession.AsyncBytes

    struct AsyncIterator: AsyncIteratorProtocol {
        var iterator: URLSession.AsyncBytes.AsyncIterator
        private var buffer: [UInt8] = []
        private var finished = false

        init(bytes: URLSession.AsyncBytes) {
            self.iterator = bytes.makeAsyncIterator()
        }

        mutating func next() async throws -> String? {
            if finished { return nil }
            while true {
                guard let byte = try await iterator.next() else {
                    finished = true
                    if buffer.isEmpty { return nil }
                    let line = String(decoding: buffer, as: UTF8.self)
                    buffer.removeAll()
                    return line
                }
                if byte == UInt8(ascii: "\n") {
                    if !buffer.isEmpty && buffer.last == UInt8(ascii: "\r") {
                        buffer.removeLast()
                    }
                    let line = String(decoding: buffer, as: UTF8.self)
                    buffer.removeAll(keepingCapacity: true)
                    return line
                }
                buffer.append(byte)
            }
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(bytes: bytes)
    }
}

struct URLSessionNativeLLMHTTPClient: NativeLLMHTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        let (data, rawResponse) = try await session.data(for: request)
        guard let response = rawResponse as? HTTPURLResponse else {
            throw NativeLLMError(
                code: .invalidResponse,
                message: "Invalid HTTP response from Anthropic",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }
        return (data, response)
    }

    func sendStreaming(_ request: URLRequest) async throws -> (lineStream: AsyncThrowingStream<String, Error>, response: HTTPURLResponse) {
        let (bytes, rawResponse) = try await session.bytes(for: request)
        guard let response = rawResponse as? HTTPURLResponse else {
            throw NativeLLMError(
                code: .invalidResponse,
                message: "Invalid HTTP response from Anthropic",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }

        let lineStream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    // Use SSELineIterator instead of bytes.lines because
                    // AsyncLineSequence omits empty lines, which are critical SSE event delimiters.
                    let sseLines = SSELineIterator(bytes: bytes)
                    for try await line in sseLines {
                        try Task.checkCancellation()
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        return (lineStream: lineStream, response: response)
    }
}

struct AnthropicNativeLLMProviderAdapter: NativeLLMProviderAdapter {
    let provider: LLMProvider = .anthropic

    private let httpClient: any NativeLLMHTTPClient

    init(httpClient: any NativeLLMHTTPClient = URLSessionNativeLLMHTTPClient()) {
        self.httpClient = httpClient
    }

    func stream(request: NativeLLMRequest) -> AsyncThrowingStream<NativeLLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try Self.makeURLRequest(from: request)
                    let (lineStream, response) = try await httpClient.sendStreaming(urlRequest)

                    guard (200...299).contains(response.statusCode) else {
                        let data = try await Self.collectStreamBodyData(lineStream)
                        let mappedError = Self.mapHTTPError(
                            statusCode: response.statusCode,
                            data: data,
                            headers: response.allHeaderFields
                        )
                        continuation.yield(.error(mappedError))
                        throw mappedError
                    }

                    var accumulator = Self.SSEEventAccumulator()
                    var toolBuffers: [Int: Self.ToolUseBuffer] = [:]
                    var emittedDone = false

                    for try await rawLine in lineStream {
                        try Task.checkCancellation()
                        if let event = accumulator.append(line: rawLine.replacingOccurrences(of: "\r", with: "")) {
                            let mapped = try Self.mapSSEEvent(event, toolBuffers: &toolBuffers)
                            for mappedEvent in mapped {
                                continuation.yield(mappedEvent)
                                if mappedEvent.kind == .done {
                                    emittedDone = true
                                }
                                if mappedEvent.kind == .error, let error = mappedEvent.error {
                                    throw error
                                }
                            }
                            if emittedDone {
                                break
                            }
                        }
                    }

                    if !emittedDone, let pending = accumulator.flush() {
                        let mapped = try Self.mapSSEEvent(pending, toolBuffers: &toolBuffers)
                        for mappedEvent in mapped {
                            continuation.yield(mappedEvent)
                            if mappedEvent.kind == .done {
                                emittedDone = true
                            }
                            if mappedEvent.kind == .error, let error = mappedEvent.error {
                                throw error
                            }
                        }
                    }

                    if !toolBuffers.isEmpty {
                        for index in toolBuffers.keys.sorted() {
                            if let tool = toolBuffers[index] {
                                continuation.yield(.toolUse(
                                    toolCallId: tool.toolCallId,
                                    toolName: tool.toolName,
                                    toolInputJSON: tool.inputJSON
                                ))
                            }
                        }
                    }

                    if !emittedDone {
                        continuation.yield(.done(text: nil))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: NativeLLMError(
                        code: .cancelled,
                        message: "Anthropic request cancelled",
                        statusCode: nil,
                        retryAfterSeconds: nil
                    ))
                } catch let error as NativeLLMError {
                    continuation.finish(throwing: error)
                } catch let error as URLError {
                    continuation.finish(throwing: Self.mapURLError(error))
                } catch {
                    continuation.finish(throwing: NativeLLMError(
                        code: .unknown,
                        message: error.localizedDescription,
                        statusCode: nil,
                        retryAfterSeconds: nil
                    ))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

struct OpenAINativeLLMProviderAdapter: NativeLLMProviderAdapter {
    let provider: LLMProvider = .openai

    private let httpClient: any NativeLLMHTTPClient

    init(httpClient: any NativeLLMHTTPClient = URLSessionNativeLLMHTTPClient()) {
        self.httpClient = httpClient
    }

    func stream(request: NativeLLMRequest) -> AsyncThrowingStream<NativeLLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try Self.makeURLRequest(from: request)
                    let (data, response) = try await httpClient.send(urlRequest)

                    guard (200...299).contains(response.statusCode) else {
                        let mappedError = Self.mapHTTPError(
                            statusCode: response.statusCode,
                            data: data,
                            headers: response.allHeaderFields
                        )
                        continuation.yield(.error(mappedError))
                        throw mappedError
                    }

                    let events = try Self.parseStreamEvents(from: data)
                    var emittedDone = false
                    for event in events {
                        continuation.yield(event)
                        if event.kind == .done {
                            emittedDone = true
                        }
                        if event.kind == .error, let error = event.error {
                            throw error
                        }
                    }

                    if !emittedDone {
                        continuation.yield(.done(text: nil))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: NativeLLMError(
                        code: .cancelled,
                        message: "OpenAI request cancelled",
                        statusCode: nil,
                        retryAfterSeconds: nil
                    ))
                } catch let error as NativeLLMError {
                    continuation.finish(throwing: error)
                } catch let error as URLError {
                    continuation.finish(throwing: Self.mapURLError(error))
                } catch {
                    continuation.finish(throwing: NativeLLMError(
                        code: .unknown,
                        message: error.localizedDescription,
                        statusCode: nil,
                        retryAfterSeconds: nil
                    ))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

struct ZAINativeLLMProviderAdapter: NativeLLMProviderAdapter {
    let provider: LLMProvider = .zai

    private let openAICompatibleAdapter: OpenAINativeLLMProviderAdapter

    init(httpClient: any NativeLLMHTTPClient = URLSessionNativeLLMHTTPClient()) {
        self.openAICompatibleAdapter = OpenAINativeLLMProviderAdapter(httpClient: httpClient)
    }

    func stream(request: NativeLLMRequest) -> AsyncThrowingStream<NativeLLMStreamEvent, Error> {
        guard request.provider == .zai else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NativeLLMError(
                    code: .unsupportedProvider,
                    message: "Z.AI adapter cannot handle provider: \(request.provider.rawValue)",
                    statusCode: nil,
                    retryAfterSeconds: nil
                ))
            }
        }

        let bridgedRequest = NativeLLMRequest(
            provider: .openai,
            model: request.model,
            apiKey: request.apiKey,
            systemPrompt: request.systemPrompt,
            messages: request.messages,
            tools: request.tools,
            maxTokens: request.maxTokens,
            temperature: request.temperature,
            endpointURL: request.endpointURL ?? LLMProvider.zai.apiURL,
            timeoutSeconds: request.timeoutSeconds,
            anthropicVersion: request.anthropicVersion
        )
        return openAICompatibleAdapter.stream(request: bridgedRequest)
    }
}

struct OllamaNativeLLMProviderAdapter: NativeLLMProviderAdapter {
    let provider: LLMProvider = .ollama

    private let openAICompatibleAdapter: OpenAINativeLLMProviderAdapter

    init(httpClient: any NativeLLMHTTPClient = URLSessionNativeLLMHTTPClient()) {
        self.openAICompatibleAdapter = OpenAINativeLLMProviderAdapter(httpClient: httpClient)
    }

    func stream(request: NativeLLMRequest) -> AsyncThrowingStream<NativeLLMStreamEvent, Error> {
        guard request.provider == .ollama else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NativeLLMError(
                    code: .unsupportedProvider,
                    message: "Ollama adapter cannot handle provider: \(request.provider.rawValue)",
                    statusCode: nil,
                    retryAfterSeconds: nil
                ))
            }
        }

        let bridgedRequest = NativeLLMRequest(
            provider: .openai,
            model: request.model,
            apiKey: normalizedLocalAPIKey(request.apiKey, fallback: "ollama-local"),
            systemPrompt: request.systemPrompt,
            messages: request.messages,
            tools: request.tools,
            maxTokens: request.maxTokens,
            temperature: request.temperature,
            endpointURL: request.endpointURL ?? LLMProvider.ollama.apiURL,
            timeoutSeconds: request.timeoutSeconds,
            anthropicVersion: request.anthropicVersion
        )
        return openAICompatibleAdapter.stream(request: bridgedRequest)
    }
}

struct LMStudioNativeLLMProviderAdapter: NativeLLMProviderAdapter {
    let provider: LLMProvider = .lmStudio

    private let openAICompatibleAdapter: OpenAINativeLLMProviderAdapter

    init(httpClient: any NativeLLMHTTPClient = URLSessionNativeLLMHTTPClient()) {
        self.openAICompatibleAdapter = OpenAINativeLLMProviderAdapter(httpClient: httpClient)
    }

    func stream(request: NativeLLMRequest) -> AsyncThrowingStream<NativeLLMStreamEvent, Error> {
        guard request.provider == .lmStudio else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NativeLLMError(
                    code: .unsupportedProvider,
                    message: "LM Studio adapter cannot handle provider: \(request.provider.rawValue)",
                    statusCode: nil,
                    retryAfterSeconds: nil
                ))
            }
        }

        let bridgedRequest = NativeLLMRequest(
            provider: .openai,
            model: request.model,
            apiKey: normalizedLocalAPIKey(request.apiKey, fallback: "lmstudio-local"),
            systemPrompt: request.systemPrompt,
            messages: request.messages,
            tools: request.tools,
            maxTokens: request.maxTokens,
            temperature: request.temperature,
            endpointURL: request.endpointURL ?? LLMProvider.lmStudio.apiURL,
            timeoutSeconds: request.timeoutSeconds,
            anthropicVersion: request.anthropicVersion
        )
        return openAICompatibleAdapter.stream(request: bridgedRequest)
    }
}

private func normalizedLocalAPIKey(_ apiKey: String?, fallback: String) -> String {
    let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? fallback : trimmed
}

private extension OpenAINativeLLMProviderAdapter {
    struct OpenAIRequestPayload: Encodable {
        let model: String
        let messages: [OpenAIMessage]
        let tools: [OpenAITool]?
        let stream: Bool
        let streamOptions: OpenAIStreamOptions?
        let maxTokens: Int
        let temperature: Double?

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case tools
            case stream
            case streamOptions = "stream_options"
            case maxTokens = "max_tokens"
            case temperature
        }
    }

    struct OpenAIStreamOptions: Encodable {
        let includeUsage: Bool

        enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }
    }

    enum OpenAIMessage: Encodable {
        case chat(role: String, content: String?, toolCalls: [OpenAIToolCall]?)
        case tool(toolCallId: String, content: String)

        enum CodingKeys: String, CodingKey {
            case role
            case content
            case toolCalls = "tool_calls"
            case toolCallId = "tool_call_id"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .chat(role, content, toolCalls):
                try container.encode(role, forKey: .role)
                if let content {
                    try container.encode(content, forKey: .content)
                } else {
                    try container.encodeNil(forKey: .content)
                }
                if let toolCalls, !toolCalls.isEmpty {
                    try container.encode(toolCalls, forKey: .toolCalls)
                }
            case let .tool(toolCallId, content):
                try container.encode("tool", forKey: .role)
                try container.encode(toolCallId, forKey: .toolCallId)
                try container.encode(content, forKey: .content)
            }
        }
    }

    struct OpenAIToolCall: Encodable {
        let id: String
        let type: String = "function"
        let function: OpenAIFunctionCall
    }

    struct OpenAIFunctionCall: Encodable {
        let name: String
        let arguments: String
    }

    struct OpenAITool: Encodable {
        let type: String = "function"
        let function: OpenAIFunctionDefinition
    }

    struct OpenAIFunctionDefinition: Encodable {
        let name: String
        let description: String
        let parameters: [String: AnyCodableValue]
    }

    struct OpenAISSEEvent {
        let data: String
    }

    struct OpenAISSEEventAccumulator {
        private(set) var dataLines: [String] = []

        mutating func append(line: String) -> OpenAISSEEvent? {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty {
                return flush()
            }

            if trimmedLine.hasPrefix(":") {
                return nil
            }

            if let value = trimmedLine.removing(prefix: "data:") {
                dataLines.append(value.trimmingCharacters(in: .whitespaces))
            }

            return nil
        }

        mutating func flush() -> OpenAISSEEvent? {
            guard !dataLines.isEmpty else { return nil }
            defer { dataLines.removeAll(keepingCapacity: true) }
            return OpenAISSEEvent(data: dataLines.joined(separator: "\n"))
        }
    }

    struct OpenAIChunkEnvelope: Decodable {
        let choices: [OpenAIChoice]?
        let usage: OpenAIUsage?
    }

    struct OpenAIUsage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }

    struct OpenAIChoice: Decodable {
        let delta: OpenAIDelta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct OpenAIDelta: Decodable {
        let content: String?
        let toolCalls: [OpenAIToolCallDelta]?

        enum CodingKeys: String, CodingKey {
            case content
            case toolCalls = "tool_calls"
        }
    }

    struct OpenAIToolCallDelta: Decodable {
        let index: Int?
        let id: String?
        let function: OpenAIFunctionDelta?
    }

    struct OpenAIFunctionDelta: Decodable {
        let name: String?
        let arguments: String?
    }

    struct OpenAIErrorEnvelope: Decodable {
        let error: OpenAIErrorBody
    }

    struct OpenAIErrorBody: Decodable {
        let message: String
        let type: String?
        let code: String?
    }

    struct ToolCallBuffer {
        var toolCallId: String?
        var toolName: String?
        var arguments: String
    }

    static func makeURLRequest(from request: NativeLLMRequest) throws -> URLRequest {
        guard request.provider == .openai else {
            throw NativeLLMError(
                code: .unsupportedProvider,
                message: "OpenAI adapter cannot handle provider: \(request.provider.rawValue)",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }

        guard let apiKey = request.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            throw NativeLLMError(
                code: .authentication,
                message: "OpenAI API key is required",
                statusCode: 401,
                retryAfterSeconds: nil
            )
        }

        guard request.maxTokens > 0 else {
            throw NativeLLMError(
                code: .invalidResponse,
                message: "maxTokens must be greater than 0",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }

        let endpoint = request.endpointURL ?? request.provider.apiURL
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = request.timeoutSeconds
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload = OpenAIRequestPayload(
            model: request.model,
            messages: convertMessages(from: request),
            tools: request.tools.isEmpty ? nil : request.tools.map { tool in
                OpenAITool(function: OpenAIFunctionDefinition(
                    name: tool.name,
                    description: tool.description,
                    parameters: tool.inputSchema
                ))
            },
            stream: true,
            streamOptions: OpenAIStreamOptions(includeUsage: true),
            maxTokens: request.maxTokens,
            temperature: request.temperature
        )

        urlRequest.httpBody = try JSONEncoder().encode(payload)
        return urlRequest
    }

    static func convertMessages(from request: NativeLLMRequest) -> [OpenAIMessage] {
        var converted: [OpenAIMessage] = []

        if let systemPrompt = request.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !systemPrompt.isEmpty {
            converted.append(.chat(role: "system", content: systemPrompt, toolCalls: nil))
        }

        for message in request.messages {
            var textParts: [String] = []
            var toolCalls: [OpenAIToolCall] = []
            var toolMessages: [OpenAIMessage] = []

            for content in message.contents {
                switch content {
                case .text(let text):
                    if !text.isEmpty {
                        textParts.append(text)
                    }
                case .toolUse(let toolCallId, let name, let inputJSON):
                    toolCalls.append(OpenAIToolCall(
                        id: toolCallId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? UUID().uuidString : toolCallId,
                        function: OpenAIFunctionCall(
                            name: name,
                            arguments: normalizeToolArgumentsJSON(inputJSON)
                        )
                    ))
                case .toolResult(let toolCallId, let content, _):
                    toolMessages.append(.tool(
                        toolCallId: toolCallId,
                        content: content
                    ))
                }
            }

            let text = textParts.joined(separator: "\n")
            if !text.isEmpty || !toolCalls.isEmpty {
                converted.append(.chat(
                    role: message.role.rawValue,
                    content: text.isEmpty ? nil : text,
                    toolCalls: toolCalls.isEmpty ? nil : toolCalls
                ))
            }

            converted.append(contentsOf: toolMessages)
        }

        return converted
    }

    static func parseStreamEvents(from data: Data) throws -> [NativeLLMStreamEvent] {
        guard let payload = String(data: data, encoding: .utf8) else {
            throw NativeLLMError(
                code: .invalidResponse,
                message: "OpenAI response body is not valid UTF-8",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }

        var accumulator = OpenAISSEEventAccumulator()
        var toolBuffers: [Int: ToolCallBuffer] = [:]
        var latestUsage: OpenAIUsage?
        var events: [NativeLLMStreamEvent] = []
        var hasDone = false

        let lines = payload.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        for line in lines {
            if let event = accumulator.append(line: line.replacingOccurrences(of: "\r", with: "")) {
                let mapped = try mapSSEPayload(
                    event.data,
                    toolBuffers: &toolBuffers,
                    latestUsage: &latestUsage
                )
                events.append(contentsOf: mapped)
                if mapped.contains(where: { $0.kind == .done }) {
                    hasDone = true
                }
            }
        }

        if let pending = accumulator.flush() {
            let mapped = try mapSSEPayload(
                pending.data,
                toolBuffers: &toolBuffers,
                latestUsage: &latestUsage
            )
            events.append(contentsOf: mapped)
            if mapped.contains(where: { $0.kind == .done }) {
                hasDone = true
            }
        }

        if !toolBuffers.isEmpty {
            for index in toolBuffers.keys.sorted() {
                if let buffer = toolBuffers[index] {
                    events.append(.toolUse(
                        toolCallId: buffer.toolCallId ?? UUID().uuidString,
                        toolName: (buffer.toolName?.isEmpty == false ? buffer.toolName! : "unknown_tool"),
                        toolInputJSON: normalizeToolArgumentsJSON(buffer.arguments)
                    ))
                }
            }
        }

        if !hasDone {
            events.append(.done(
                text: nil,
                inputTokens: latestUsage?.promptTokens,
                outputTokens: latestUsage?.completionTokens
            ))
        }

        return events
    }

    static func mapSSEPayload(
        _ data: String,
        toolBuffers: inout [Int: ToolCallBuffer],
        latestUsage: inout OpenAIUsage?
    ) throws -> [NativeLLMStreamEvent] {
        if data == "[DONE]" {
            return [.done(
                text: nil,
                inputTokens: latestUsage?.promptTokens,
                outputTokens: latestUsage?.completionTokens
            )]
        }

        if let streamError: OpenAIErrorEnvelope = try? decode(data) {
            return [.error(mapStreamError(
                type: streamError.error.type,
                code: streamError.error.code,
                message: streamError.error.message
            ))]
        }

        let chunk: OpenAIChunkEnvelope = try decode(data)
        var events: [NativeLLMStreamEvent] = []

        if let usage = chunk.usage {
            latestUsage = usage
        }

        for choice in chunk.choices ?? [] {
            if let delta = choice.delta {
                if let content = delta.content, !content.isEmpty {
                    events.append(.partial(content))
                }

                for toolCall in delta.toolCalls ?? [] {
                    let index = toolCall.index ?? 0
                    var buffer = toolBuffers[index] ?? ToolCallBuffer(
                        toolCallId: nil,
                        toolName: nil,
                        arguments: ""
                    )

                    if let id = toolCall.id, !id.isEmpty {
                        buffer.toolCallId = id
                    }

                    if let namePart = toolCall.function?.name, !namePart.isEmpty {
                        if let existingName = buffer.toolName, !existingName.isEmpty {
                            buffer.toolName = existingName + namePart
                        } else {
                            buffer.toolName = namePart
                        }
                    }

                    if let argumentPart = toolCall.function?.arguments, !argumentPart.isEmpty {
                        buffer.arguments += argumentPart
                    }

                    toolBuffers[index] = buffer
                }
            }

            if let finishReason = choice.finishReason {
                if finishReason == "tool_calls" {
                    for index in toolBuffers.keys.sorted() {
                        if let buffer = toolBuffers.removeValue(forKey: index) {
                            events.append(.toolUse(
                                toolCallId: buffer.toolCallId ?? UUID().uuidString,
                                toolName: (buffer.toolName?.isEmpty == false ? buffer.toolName! : "unknown_tool"),
                                toolInputJSON: normalizeToolArgumentsJSON(buffer.arguments)
                            ))
                        }
                    }
                } else if finishReason == "stop" || finishReason == "length" || finishReason == "content_filter" {
                    events.append(.done(
                        text: nil,
                        inputTokens: latestUsage?.promptTokens,
                        outputTokens: latestUsage?.completionTokens
                    ))
                }
            }
        }

        return events
    }

    static func decode<T: Decodable>(_ raw: String) throws -> T {
        guard let data = raw.data(using: .utf8) else {
            throw NativeLLMError(
                code: .invalidResponse,
                message: "Failed to decode OpenAI SSE JSON payload",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NativeLLMError(
                code: .invalidResponse,
                message: "Failed to parse OpenAI SSE payload: \(error.localizedDescription)",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }
    }

    static func normalizeToolArgumentsJSON(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return "{}"
        }
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return "{}"
        }
        return trimmed
    }

    static func mapHTTPError(
        statusCode: Int,
        data: Data,
        headers: [AnyHashable: Any]
    ) -> NativeLLMError {
        let message = extractErrorMessage(from: data) ?? "OpenAI API request failed"
        let retryAfter = parseRetryAfter(headers: headers)

        let code: NativeLLMErrorCode
        switch statusCode {
        case 401, 403:
            code = .authentication
        case 404:
            code = .modelNotFound
        case 429:
            code = .rateLimited
        case 500...599:
            code = .server
        default:
            code = .invalidResponse
        }

        return NativeLLMError(
            code: code,
            message: message,
            statusCode: statusCode,
            retryAfterSeconds: retryAfter
        )
    }

    static func mapURLError(_ error: URLError) -> NativeLLMError {
        let code: NativeLLMErrorCode
        switch error.code {
        case .timedOut:
            code = .timeout
        case .cancelled:
            code = .cancelled
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            code = .network
        default:
            code = .unknown
        }

        return NativeLLMError(
            code: code,
            message: error.localizedDescription,
            statusCode: nil,
            retryAfterSeconds: nil
        )
    }

    static func mapStreamError(type: String?, code: String?, message: String) -> NativeLLMError {
        let normalizedType = (type ?? "").lowercased()
        let normalizedCode = (code ?? "").lowercased()
        let loweredMessage = message.lowercased()

        let mapped: NativeLLMErrorCode
        if normalizedType.contains("rate_limit") || normalizedCode.contains("rate_limit") {
            mapped = .rateLimited
        } else if normalizedType.contains("auth") || normalizedCode.contains("auth") || normalizedCode == "invalid_api_key" {
            mapped = .authentication
        } else if normalizedCode.contains("model_not_found") || (loweredMessage.contains("model") && loweredMessage.contains("not found")) {
            mapped = .modelNotFound
        } else if normalizedType.contains("server") || normalizedType.contains("api_error") {
            mapped = .server
        } else {
            mapped = .unknown
        }

        return NativeLLMError(
            code: mapped,
            message: message,
            statusCode: nil,
            retryAfterSeconds: nil
        )
    }

    static func parseRetryAfter(headers: [AnyHashable: Any]) -> TimeInterval? {
        for (key, value) in headers {
            if String(describing: key).caseInsensitiveCompare("Retry-After") == .orderedSame {
                if let seconds = TimeInterval(String(describing: value)) {
                    return seconds
                }
            }
        }
        return nil
    }

    static func extractErrorMessage(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errorObject = object["error"] as? [String: Any],
               let message = errorObject["message"] as? String,
               !message.isEmpty {
                return message
            }
            if let message = object["message"] as? String, !message.isEmpty {
                return message
            }
        }

        if let plain = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !plain.isEmpty {
            return plain
        }
        return nil
    }
}

private extension AnthropicNativeLLMProviderAdapter {
    struct AnthropicRequestPayload: Encodable {
        let model: String
        let maxTokens: Int
        let stream: Bool
        let system: String?
        let temperature: Double?
        let messages: [AnthropicMessage]
        let tools: [AnthropicTool]?

        enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case stream
            case system
            case temperature
            case messages
            case tools
        }
    }

    struct AnthropicMessage: Encodable {
        let role: String
        let content: [AnthropicContentBlock]
    }

    enum AnthropicContentBlock: Encodable {
        case text(String)
        case toolUse(id: String, name: String, input: AnyCodableValue)
        case toolResult(toolUseId: String, content: String, isError: Bool)

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case id
            case name
            case input
            case toolUseId = "tool_use_id"
            case content
            case isError = "is_error"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .toolUse(let id, let name, let input):
                try container.encode("tool_use", forKey: .type)
                try container.encode(id, forKey: .id)
                try container.encode(name, forKey: .name)
                try container.encode(input, forKey: .input)
            case .toolResult(let toolUseId, let content, let isError):
                try container.encode("tool_result", forKey: .type)
                try container.encode(toolUseId, forKey: .toolUseId)
                try container.encode(content, forKey: .content)
                try container.encode(isError, forKey: .isError)
            }
        }
    }

    struct AnthropicTool: Encodable {
        let name: String
        let description: String
        let inputSchema: [String: AnyCodableValue]

        enum CodingKeys: String, CodingKey {
            case name
            case description
            case inputSchema = "input_schema"
        }
    }

    struct SSEEvent {
        let name: String
        let data: String
    }

    struct SSEEventAccumulator {
        private(set) var eventName: String = "message"
        private(set) var dataLines: [String] = []

        mutating func append(line: String) -> SSEEvent? {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty {
                return flush()
            }

            if trimmedLine.hasPrefix(":") {
                return nil
            }

            if let value = trimmedLine.removing(prefix: "event:") {
                eventName = value.trimmingCharacters(in: .whitespaces)
                return nil
            }

            if let value = trimmedLine.removing(prefix: "data:") {
                dataLines.append(value.trimmingCharacters(in: .whitespaces))
                return nil
            }

            return nil
        }

        mutating func flush() -> SSEEvent? {
            guard !dataLines.isEmpty else {
                eventName = "message"
                return nil
            }
            defer {
                eventName = "message"
                dataLines.removeAll(keepingCapacity: true)
            }
            return SSEEvent(name: eventName, data: dataLines.joined(separator: "\n"))
        }
    }

    struct ToolUseBuffer {
        let toolCallId: String
        let toolName: String
        var inputJSON: String
    }

    struct ContentBlockStartEnvelope: Decodable {
        let index: Int
        let contentBlock: ContentBlock

        enum CodingKeys: String, CodingKey {
            case index
            case contentBlock = "content_block"
        }
    }

    struct ContentBlock: Decodable {
        let type: String
        let id: String?
        let name: String?
        let input: AnyCodableValue?
    }

    struct ContentBlockDeltaEnvelope: Decodable {
        let index: Int
        let delta: Delta
    }

    struct Delta: Decodable {
        let type: String
        let text: String?
        let partialJSON: String?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case partialJSON = "partial_json"
        }
    }

    struct ContentBlockStopEnvelope: Decodable {
        let index: Int
    }

    struct StreamErrorEnvelope: Decodable {
        let error: StreamErrorBody
    }

    struct StreamErrorBody: Decodable {
        let type: String?
        let message: String
    }

    static func makeURLRequest(from request: NativeLLMRequest) throws -> URLRequest {
        guard request.provider == .anthropic else {
            throw NativeLLMError(
                code: .unsupportedProvider,
                message: "Anthropic adapter cannot handle provider: \(request.provider.rawValue)",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }

        guard let apiKey = request.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            throw NativeLLMError(
                code: .authentication,
                message: "Anthropic API key is required",
                statusCode: 401,
                retryAfterSeconds: nil
            )
        }

        guard request.maxTokens > 0 else {
            throw NativeLLMError(
                code: .invalidResponse,
                message: "maxTokens must be greater than 0",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }

        let endpoint = request.endpointURL ?? request.provider.apiURL
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = request.timeoutSeconds
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(request.anthropicVersion, forHTTPHeaderField: "anthropic-version")

        let payload = AnthropicRequestPayload(
            model: request.model,
            maxTokens: request.maxTokens,
            stream: true,
            system: request.systemPrompt,
            temperature: request.temperature,
            messages: request.messages.map(Self.convertMessage),
            tools: request.tools.isEmpty ? nil : request.tools.map { tool in
                AnthropicTool(name: tool.name, description: tool.description, inputSchema: tool.inputSchema)
            }
        )
        urlRequest.httpBody = try JSONEncoder().encode(payload)
        return urlRequest
    }

    static func convertMessage(_ message: NativeLLMMessage) -> AnthropicMessage {
        let blocks = message.contents.map { content -> AnthropicContentBlock in
            switch content {
            case .text(let text):
                return .text(text)
            case .toolUse(let toolCallId, let name, let inputJSON):
                return .toolUse(
                    id: toolCallId,
                    name: name,
                    input: parseToolUseInputJSON(inputJSON)
                )
            case .toolResult(let toolCallId, let content, let isError):
                return .toolResult(toolUseId: toolCallId, content: content, isError: isError)
            }
        }
        return AnthropicMessage(
            role: message.role.rawValue,
            content: blocks.isEmpty ? [.text("")] : blocks
        )
    }

    static func parseStreamEvents(from data: Data) throws -> [NativeLLMStreamEvent] {
        guard let payload = String(data: data, encoding: .utf8) else {
            throw NativeLLMError(
                code: .invalidResponse,
                message: "Anthropic response body is not valid UTF-8",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }

        var accumulator = SSEEventAccumulator()
        var toolBuffers: [Int: ToolUseBuffer] = [:]
        var events: [NativeLLMStreamEvent] = []
        var hasDone = false

        let lines = payload.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        for line in lines {
            if let sseEvent = accumulator.append(line: line.replacingOccurrences(of: "\r", with: "")) {
                let mapped = try mapSSEEvent(sseEvent, toolBuffers: &toolBuffers)
                events.append(contentsOf: mapped)
                if mapped.contains(where: { $0.kind == .done }) {
                    hasDone = true
                }
            }
        }

        if let pending = accumulator.flush() {
            let mapped = try mapSSEEvent(pending, toolBuffers: &toolBuffers)
            events.append(contentsOf: mapped)
            if mapped.contains(where: { $0.kind == .done }) {
                hasDone = true
            }
        }

        if !toolBuffers.isEmpty {
            for index in toolBuffers.keys.sorted() {
                if let buffer = toolBuffers[index] {
                    events.append(.toolUse(
                        toolCallId: buffer.toolCallId,
                        toolName: buffer.toolName,
                        toolInputJSON: buffer.inputJSON
                    ))
                }
            }
        }

        if !hasDone {
            events.append(.done(text: nil))
        }

        return events
    }

    static func mapSSEEvent(
        _ event: SSEEvent,
        toolBuffers: inout [Int: ToolUseBuffer]
    ) throws -> [NativeLLMStreamEvent] {
        if event.data == "[DONE]" {
            return [.done(text: nil)]
        }

        switch event.name {
        case "content_block_start":
            let envelope: ContentBlockStartEnvelope = try decode(event.data)
            guard envelope.contentBlock.type == "tool_use" else { return [] }

            let toolCallId = envelope.contentBlock.id ?? UUID().uuidString
            let toolName = envelope.contentBlock.name ?? "unknown_tool"
            let initialInput = jsonString(from: envelope.contentBlock.input) ?? ""
            toolBuffers[envelope.index] = ToolUseBuffer(
                toolCallId: toolCallId,
                toolName: toolName,
                inputJSON: initialInput
            )
            return []

        case "content_block_delta":
            let envelope: ContentBlockDeltaEnvelope = try decode(event.data)
            switch envelope.delta.type {
            case "text_delta":
                guard let text = envelope.delta.text, !text.isEmpty else { return [] }
                return [.partial(text)]

            case "input_json_delta":
                guard var buffer = toolBuffers[envelope.index] else { return [] }
                if let partialJSON = envelope.delta.partialJSON {
                    buffer.inputJSON += partialJSON
                    toolBuffers[envelope.index] = buffer
                }
                return []

            default:
                return []
            }

        case "content_block_stop":
            let envelope: ContentBlockStopEnvelope = try decode(event.data)
            guard let tool = toolBuffers.removeValue(forKey: envelope.index) else { return [] }
            return [.toolUse(
                toolCallId: tool.toolCallId,
                toolName: tool.toolName,
                toolInputJSON: tool.inputJSON
            )]

        case "message_stop":
            var events: [NativeLLMStreamEvent] = []
            if !toolBuffers.isEmpty {
                for index in toolBuffers.keys.sorted() {
                    if let tool = toolBuffers.removeValue(forKey: index) {
                        events.append(.toolUse(
                            toolCallId: tool.toolCallId,
                            toolName: tool.toolName,
                            toolInputJSON: tool.inputJSON
                        ))
                    }
                }
            }
            events.append(.done(text: nil))
            return events

        case "error":
            let envelope: StreamErrorEnvelope = try decode(event.data)
            let mappedError = mapStreamError(
                type: envelope.error.type,
                message: envelope.error.message
            )
            return [.error(mappedError)]

        default:
            return []
        }
    }

    static func decode<T: Decodable>(_ raw: String) throws -> T {
        guard let data = raw.data(using: .utf8) else {
            throw NativeLLMError(
                code: .invalidResponse,
                message: "Failed to decode SSE JSON payload",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NativeLLMError(
                code: .invalidResponse,
                message: "Failed to parse Anthropic SSE payload: \(error.localizedDescription)",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }
    }

    static func jsonString(from value: AnyCodableValue?) -> String? {
        guard let value else { return nil }
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func parseToolUseInputJSON(_ raw: String) -> AnyCodableValue {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return .object([:])
        }
        if let value = try? JSONDecoder().decode(AnyCodableValue.self, from: data) {
            return value
        }
        return .object([:])
    }

    static func collectStreamBodyData(
        _ lineStream: AsyncThrowingStream<String, Error>
    ) async throws -> Data {
        var lines: [String] = []
        for try await line in lineStream {
            lines.append(line)
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    static func mapHTTPError(
        statusCode: Int,
        data: Data,
        headers: [AnyHashable: Any]
    ) -> NativeLLMError {
        let message = extractErrorMessage(from: data) ?? "Anthropic API request failed"
        let retryAfter = parseRetryAfter(headers: headers)

        let code: NativeLLMErrorCode
        switch statusCode {
        case 401, 403:
            code = .authentication
        case 404:
            code = .modelNotFound
        case 429:
            code = .rateLimited
        case 500...599:
            code = .server
        default:
            code = .invalidResponse
        }

        return NativeLLMError(
            code: code,
            message: message,
            statusCode: statusCode,
            retryAfterSeconds: retryAfter
        )
    }

    static func mapURLError(_ error: URLError) -> NativeLLMError {
        let code: NativeLLMErrorCode
        switch error.code {
        case .timedOut:
            code = .timeout
        case .cancelled:
            code = .cancelled
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            code = .network
        default:
            code = .unknown
        }

        return NativeLLMError(
            code: code,
            message: error.localizedDescription,
            statusCode: nil,
            retryAfterSeconds: nil
        )
    }

    static func mapStreamError(type: String?, message: String) -> NativeLLMError {
        let normalizedType = (type ?? "").lowercased()
        let loweredMessage = message.lowercased()

        let code: NativeLLMErrorCode
        if normalizedType == "rate_limit_error" {
            code = .rateLimited
        } else if normalizedType == "authentication_error" || normalizedType == "permission_error" {
            code = .authentication
        } else if normalizedType == "overloaded_error" || normalizedType == "api_error" {
            code = .server
        } else if loweredMessage.contains("model") && loweredMessage.contains("not found") {
            code = .modelNotFound
        } else {
            code = .unknown
        }

        return NativeLLMError(
            code: code,
            message: message,
            statusCode: nil,
            retryAfterSeconds: nil
        )
    }

    static func parseRetryAfter(headers: [AnyHashable: Any]) -> TimeInterval? {
        for (key, value) in headers {
            if String(describing: key).caseInsensitiveCompare("Retry-After") == .orderedSame {
                if let seconds = TimeInterval(String(describing: value)) {
                    return seconds
                }
            }
        }
        return nil
    }

    static func extractErrorMessage(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errorObject = object["error"] as? [String: Any],
               let message = errorObject["message"] as? String,
               !message.isEmpty {
                return message
            }
            if let message = object["message"] as? String, !message.isEmpty {
                return message
            }
        }

        if let plain = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !plain.isEmpty {
            return plain
        }
        return nil
    }
}

private extension String {
    func removing(prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
