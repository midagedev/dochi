import Foundation

struct NativeAgentLoopGuardPolicy: Sendable {
    let maxIterations: Int
    let maxRepeatedSignatures: Int

    init(maxIterations: Int = 8, maxRepeatedSignatures: Int = 2) {
        self.maxIterations = max(1, maxIterations)
        self.maxRepeatedSignatures = max(1, maxRepeatedSignatures)
    }

    static let `default` = NativeAgentLoopGuardPolicy()
}

@MainActor
final class NativeAgentLoopService {
    private struct PendingToolUse: Sendable {
        let toolCallId: String
        let name: String
        let inputJSON: String
    }

    private struct ExecutedToolResult: Sendable {
        let toolCallId: String
        let content: String
        let isError: Bool
    }

    private let adapters: [LLMProvider: any NativeLLMProviderAdapter]
    private let toolService: (any BuiltInToolServiceProtocol)?
    private let guardPolicy: NativeAgentLoopGuardPolicy

    init(
        adapters: [any NativeLLMProviderAdapter],
        toolService: (any BuiltInToolServiceProtocol)? = nil,
        guardPolicy: NativeAgentLoopGuardPolicy = .default
    ) {
        var map: [LLMProvider: any NativeLLMProviderAdapter] = [:]
        for adapter in adapters {
            map[adapter.provider] = adapter
        }
        self.adapters = map
        self.toolService = toolService
        self.guardPolicy = guardPolicy
    }

    func run(request: NativeLLMRequest) -> AsyncThrowingStream<NativeLLMStreamEvent, Error> {
        guard let adapter = adapters[request.provider] else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NativeLLMError(
                    code: .unsupportedProvider,
                    message: "No native adapter registered for provider: \(request.provider.rawValue)",
                    statusCode: nil,
                    retryAfterSeconds: nil
                ))
            }
        }

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor [guardPolicy, toolService] in
                do {
                    var currentRequest = request
                    var iteration = 0
                    var lastToolSignature: String?
                    var repeatedSignatureCount = 0

                    while !Task.isCancelled {
                        iteration += 1
                        if iteration > guardPolicy.maxIterations {
                            throw NativeLLMError(
                                code: .loopGuardTriggered,
                                message: "Native loop exceeded max iterations (\(guardPolicy.maxIterations))",
                                statusCode: nil,
                                retryAfterSeconds: nil
                            )
                        }

                        var pendingToolUses: [PendingToolUse] = []
                        var executedToolResults: [ExecutedToolResult] = []
                        var accumulatedAssistantText = ""
                        var doneEvent: NativeLLMStreamEvent?

                        for try await event in adapter.stream(request: currentRequest) {
                            if Task.isCancelled {
                                throw CancellationError()
                            }

                            switch event.kind {
                            case .partial:
                                if let text = event.text {
                                    accumulatedAssistantText += text
                                }
                                continuation.yield(event)

                            case .toolUse:
                                guard let toolCallId = event.toolCallId,
                                      let toolName = event.toolName,
                                      let toolInputJSON = event.toolInputJSON else {
                                    throw NativeLLMError(
                                        code: .invalidResponse,
                                        message: "tool_use event is missing required fields",
                                        statusCode: nil,
                                        retryAfterSeconds: nil
                                    )
                                }
                                pendingToolUses.append(PendingToolUse(
                                    toolCallId: toolCallId,
                                    name: toolName,
                                    inputJSON: toolInputJSON
                                ))
                                continuation.yield(event)

                            case .toolResult:
                                continuation.yield(event)

                            case .done:
                                doneEvent = event
                                if let text = event.text, !text.isEmpty {
                                    accumulatedAssistantText = text
                                }

                            case .error:
                                continuation.yield(event)
                                if let error = event.error {
                                    throw error
                                }
                                throw NativeLLMError(
                                    code: .unknown,
                                    message: "Provider emitted error event without payload",
                                    statusCode: nil,
                                    retryAfterSeconds: nil
                                )
                            }
                        }

                        if pendingToolUses.isEmpty {
                            continuation.yield(doneEvent ?? .done(
                                text: accumulatedAssistantText.isEmpty ? nil : accumulatedAssistantText
                            ))
                            continuation.finish()
                            return
                        }

                        let signature = Self.makeToolSignature(for: pendingToolUses)
                        if signature == lastToolSignature {
                            repeatedSignatureCount += 1
                        } else {
                            lastToolSignature = signature
                            repeatedSignatureCount = 1
                        }

                        if repeatedSignatureCount > guardPolicy.maxRepeatedSignatures {
                            throw NativeLLMError(
                                code: .loopGuardTriggered,
                                message: "Native loop repeated identical tool signature \(repeatedSignatureCount) times",
                                statusCode: nil,
                                retryAfterSeconds: nil
                            )
                        }

                        guard let toolService else {
                            throw NativeLLMError(
                                code: .toolExecutionFailed,
                                message: "Tool service is not configured for native tool loop",
                                statusCode: nil,
                                retryAfterSeconds: nil
                            )
                        }

                        for pending in pendingToolUses {
                            let arguments: [String: Any]
                            do {
                                arguments = try Self.parseToolArguments(from: pending.inputJSON)
                            } catch let parseError as NativeLLMError {
                                let message = "Invalid tool input for '\(pending.name)': \(parseError.message)"
                                continuation.yield(.toolResult(
                                    toolCallId: pending.toolCallId,
                                    content: message,
                                    isError: true
                                ))
                                throw NativeLLMError(
                                    code: .toolExecutionFailed,
                                    message: message,
                                    statusCode: nil,
                                    retryAfterSeconds: nil
                                )
                            }

                            let result = await toolService.execute(name: pending.name, arguments: arguments)
                            continuation.yield(.toolResult(
                                toolCallId: pending.toolCallId,
                                content: result.content,
                                isError: result.isError
                            ))

                            executedToolResults.append(ExecutedToolResult(
                                toolCallId: pending.toolCallId,
                                content: result.content,
                                isError: result.isError
                            ))

                            if result.isError {
                                throw NativeLLMError(
                                    code: .toolExecutionFailed,
                                    message: "Tool '\(pending.name)' failed: \(result.content)",
                                    statusCode: nil,
                                    retryAfterSeconds: nil
                                )
                            }
                        }

                        currentRequest = Self.makeFollowUpRequest(
                            from: currentRequest,
                            assistantText: accumulatedAssistantText,
                            toolUses: pendingToolUses,
                            toolResults: executedToolResults
                        )
                    }

                    throw NativeLLMError(
                        code: .cancelled,
                        message: "Native loop cancelled",
                        statusCode: nil,
                        retryAfterSeconds: nil
                    )
                } catch is CancellationError {
                    continuation.finish(throwing: NativeLLMError(
                        code: .cancelled,
                        message: "Native loop cancelled",
                        statusCode: nil,
                        retryAfterSeconds: nil
                    ))
                } catch let error as NativeLLMError {
                    continuation.finish(throwing: error)
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

    func supports(provider: LLMProvider) -> Bool {
        adapters[provider] != nil
    }
}

private extension NativeAgentLoopService {
    private static func makeToolSignature(for toolUses: [PendingToolUse]) -> String {
        toolUses
            .map { "\($0.name)|\($0.inputJSON)" }
            .joined(separator: "||")
    }

    private static func parseToolArguments(from rawInputJSON: String) throws -> [String: Any] {
        let trimmed = rawInputJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }

        guard let data = trimmed.data(using: .utf8) else {
            throw NativeLLMError(
                code: .invalidResponse,
                message: "tool input is not valid UTF-8",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw NativeLLMError(
                code: .invalidResponse,
                message: "tool input is not valid JSON object",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }

        guard let dictionary = object as? [String: Any] else {
            throw NativeLLMError(
                code: .invalidResponse,
                message: "tool input JSON must be an object",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }

        return dictionary
    }

    private static func makeFollowUpRequest(
        from request: NativeLLMRequest,
        assistantText: String,
        toolUses: [PendingToolUse],
        toolResults: [ExecutedToolResult]
    ) -> NativeLLMRequest {
        var messages = request.messages

        var assistantContents: [NativeLLMMessageContent] = []
        if !assistantText.isEmpty {
            assistantContents.append(.text(assistantText))
        }
        assistantContents.append(contentsOf: toolUses.map { tool in
            .toolUse(toolCallId: tool.toolCallId, name: tool.name, inputJSON: tool.inputJSON)
        })
        if !assistantContents.isEmpty {
            messages.append(NativeLLMMessage(role: .assistant, contents: assistantContents))
        }

        let toolResultContents: [NativeLLMMessageContent] = toolResults.map { result in
            .toolResult(
                toolCallId: result.toolCallId,
                content: result.content,
                isError: result.isError
            )
        }
        if !toolResultContents.isEmpty {
            messages.append(NativeLLMMessage(role: .user, contents: toolResultContents))
        }

        return NativeLLMRequest(
            provider: request.provider,
            model: request.model,
            apiKey: request.apiKey,
            systemPrompt: request.systemPrompt,
            messages: messages,
            tools: request.tools,
            maxTokens: request.maxTokens,
            temperature: request.temperature,
            endpointURL: request.endpointURL,
            timeoutSeconds: request.timeoutSeconds,
            anthropicVersion: request.anthropicVersion
        )
    }
}
