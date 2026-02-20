import Foundation

enum NativeLLMStreamEventKind: String, Codable, Sendable {
    case partial
    case toolUse = "tool_use"
    case toolResult = "tool_result"
    case done
    case error
}

struct NativeLLMStreamEvent: Sendable {
    let kind: NativeLLMStreamEventKind
    let text: String?
    let toolCallId: String?
    let toolName: String?
    let toolInputJSON: String?
    let toolResultText: String?
    let isToolResultError: Bool?
    let error: NativeLLMError?

    static func partial(_ delta: String) -> NativeLLMStreamEvent {
        NativeLLMStreamEvent(
            kind: .partial,
            text: delta,
            toolCallId: nil,
            toolName: nil,
            toolInputJSON: nil,
            toolResultText: nil,
            isToolResultError: nil,
            error: nil
        )
    }

    static func toolUse(toolCallId: String, toolName: String, toolInputJSON: String) -> NativeLLMStreamEvent {
        NativeLLMStreamEvent(
            kind: .toolUse,
            text: nil,
            toolCallId: toolCallId,
            toolName: toolName,
            toolInputJSON: toolInputJSON,
            toolResultText: nil,
            isToolResultError: nil,
            error: nil
        )
    }

    static func toolResult(toolCallId: String, content: String, isError: Bool) -> NativeLLMStreamEvent {
        NativeLLMStreamEvent(
            kind: .toolResult,
            text: nil,
            toolCallId: toolCallId,
            toolName: nil,
            toolInputJSON: nil,
            toolResultText: content,
            isToolResultError: isError,
            error: nil
        )
    }

    static func done(text: String?) -> NativeLLMStreamEvent {
        NativeLLMStreamEvent(
            kind: .done,
            text: text,
            toolCallId: nil,
            toolName: nil,
            toolInputJSON: nil,
            toolResultText: nil,
            isToolResultError: nil,
            error: nil
        )
    }

    static func error(_ error: NativeLLMError) -> NativeLLMStreamEvent {
        NativeLLMStreamEvent(
            kind: .error,
            text: nil,
            toolCallId: nil,
            toolName: nil,
            toolInputJSON: nil,
            toolResultText: nil,
            isToolResultError: nil,
            error: error
        )
    }
}

enum NativeLLMErrorCode: String, Codable, Sendable {
    case rateLimited = "rate_limited"
    case server = "server_error"
    case network = "network_error"
    case timeout = "timeout"
    case authentication = "authentication_error"
    case modelNotFound = "model_not_found"
    case invalidResponse = "invalid_response"
    case cancelled = "cancelled"
    case unsupportedProvider = "unsupported_provider"
    case loopGuardTriggered = "loop_guard_triggered"
    case toolExecutionFailed = "tool_execution_failed"
    case unknown = "unknown_error"
}

struct NativeLLMError: Error, LocalizedError, Codable, Sendable, Equatable {
    let code: NativeLLMErrorCode
    let message: String
    let statusCode: Int?
    let retryAfterSeconds: TimeInterval?

    var errorDescription: String? { message }
}

enum NativeLLMMessageRole: String, Codable, Sendable {
    case user
    case assistant
}

enum NativeLLMMessageContent: Sendable {
    case text(String)
    case toolUse(toolCallId: String, name: String, inputJSON: String)
    case toolResult(toolCallId: String, content: String, isError: Bool)
}

struct NativeLLMMessage: Sendable {
    let role: NativeLLMMessageRole
    let contents: [NativeLLMMessageContent]

    init(role: NativeLLMMessageRole, contents: [NativeLLMMessageContent]) {
        self.role = role
        self.contents = contents
    }

    init(role: NativeLLMMessageRole, text: String) {
        self.role = role
        self.contents = [.text(text)]
    }
}

struct NativeLLMToolDefinition: Sendable {
    let name: String
    let description: String
    let inputSchema: [String: AnyCodableValue]
}

struct NativeLLMRequest: Sendable {
    let provider: LLMProvider
    let model: String
    let apiKey: String?
    let systemPrompt: String?
    let messages: [NativeLLMMessage]
    let tools: [NativeLLMToolDefinition]
    let maxTokens: Int
    let temperature: Double?
    let endpointURL: URL?
    let timeoutSeconds: TimeInterval
    let anthropicVersion: String

    init(
        provider: LLMProvider,
        model: String,
        apiKey: String?,
        systemPrompt: String? = nil,
        messages: [NativeLLMMessage],
        tools: [NativeLLMToolDefinition] = [],
        maxTokens: Int = 4096,
        temperature: Double? = nil,
        endpointURL: URL? = nil,
        timeoutSeconds: TimeInterval = 60,
        anthropicVersion: String = "2023-06-01"
    ) {
        self.provider = provider
        self.model = model
        self.apiKey = apiKey
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.tools = tools
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.endpointURL = endpointURL
        self.timeoutSeconds = timeoutSeconds
        self.anthropicVersion = anthropicVersion
    }
}
