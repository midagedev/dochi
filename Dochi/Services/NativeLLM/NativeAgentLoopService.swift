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

struct NativeAgentLoopHookContext: Sendable {
    let sessionId: String
    let workspaceId: String
    let agentId: String?
}

struct NativeAgentLoopToolRefreshContext: Sendable {
    let permissions: [String]
    let preferredToolGroups: [String]
    let intentHint: String?
    let supportsToolCalling: Bool
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

    private static let maxAuditEntries = 200

    private let adapters: [LLMProvider: any NativeLLMProviderAdapter]
    private let toolService: (any BuiltInToolServiceProtocol)?
    private let hookPipeline: HookPipeline
    private let runtimeMetrics: (any RuntimeMetricsProtocol)?
    private let guardPolicy: NativeAgentLoopGuardPolicy
    private var memoryPipeline: (any MemoryPipelineProtocol)?
    private(set) var auditLog: [ToolAuditEvent] = []

    init(
        adapters: [any NativeLLMProviderAdapter],
        toolService: (any BuiltInToolServiceProtocol)? = nil,
        hookPipeline: HookPipeline = HookPipeline(),
        runtimeMetrics: (any RuntimeMetricsProtocol)? = nil,
        memoryPipeline: (any MemoryPipelineProtocol)? = nil,
        guardPolicy: NativeAgentLoopGuardPolicy = .default
    ) {
        var map: [LLMProvider: any NativeLLMProviderAdapter] = [:]
        for adapter in adapters {
            map[adapter.provider] = adapter
        }
        self.adapters = map
        self.toolService = toolService
        self.hookPipeline = hookPipeline
        self.runtimeMetrics = runtimeMetrics
        self.memoryPipeline = memoryPipeline
        self.guardPolicy = guardPolicy
    }

    func setMemoryPipeline(_ memoryPipeline: (any MemoryPipelineProtocol)?) {
        self.memoryPipeline = memoryPipeline
    }

    func runStopHooks() {
        hookPipeline.runStopHooks(auditLog: auditLog)
    }

    func run(
        request: NativeLLMRequest,
        hookContext: NativeAgentLoopHookContext? = nil,
        toolRefreshContext: NativeAgentLoopToolRefreshContext? = nil
    ) -> AsyncThrowingStream<NativeLLMStreamEvent, Error> {
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
            let task = Task { @MainActor [self, guardPolicy, toolService] in
                let resolvedHookContext = Self.normalizedHookContext(hookContext)
                if let memoryPipeline, !resolvedHookContext.workspaceId.isEmpty {
                    hookPipeline.attachMemoryPipeline(memoryPipeline, workspaceId: resolvedHookContext.workspaceId)
                }

                defer {
                    hookPipeline.runSessionCloseHooks(
                        sessionId: resolvedHookContext.sessionId,
                        auditLog: auditLog
                    )
                }

                do {
                    var currentRequest = request
                    var iteration = 0
                    var lastToolSignature: String?
                    var repeatedSignatureCount = 0
                    let runStartedAt = Date()
                    var didRecordFirstPartial = false

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
                                    if !didRecordFirstPartial, !text.isEmpty {
                                        didRecordFirstPartial = true
                                        let firstPartialLatencyMs = Date().timeIntervalSince(runStartedAt) * 1000
                                        runtimeMetrics?.recordHistogram(
                                            name: MetricName.firstPartialLatencyMs,
                                            labels: Self.metricLabels(
                                                provider: currentRequest.provider.rawValue,
                                                sessionId: resolvedHookContext.sessionId
                                            ),
                                            value: firstPartialLatencyMs
                                        )
                                    }
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
                            let startTime = Date()
                            let riskLevel = riskLevel(for: pending.name)
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
                                recordAudit(
                                    toolCallId: pending.toolCallId,
                                    sessionId: resolvedHookContext.sessionId,
                                    agentId: resolvedHookContext.agentId,
                                    toolName: pending.name,
                                    argumentsHash: "",
                                    riskLevel: riskLevel,
                                    decision: .policyBlocked,
                                    hookName: nil,
                                    startTime: startTime,
                                    resultCode: BridgeErrorCode.toolExecutionFailed.rawValue
                                )
                                throw NativeLLMError(
                                    code: .toolExecutionFailed,
                                    message: message,
                                    statusCode: nil,
                                    retryAfterSeconds: nil
                                )
                            }

                            let codableArguments = Self.makeCodableArguments(from: arguments)
                            let argsHash = HookPipeline.argumentsHash(codableArguments)
                            let toolHookContext = ToolHookContext(
                                toolCallId: pending.toolCallId,
                                sessionId: resolvedHookContext.sessionId,
                                agentId: resolvedHookContext.agentId,
                                toolName: pending.name,
                                arguments: codableArguments,
                                riskLevel: riskLevel
                            )

                            let preResult = hookPipeline.runPreHooks(context: toolHookContext)
                            let effectiveArguments: [String: Any]
                            switch preResult.decision {
                            case .block(let reason):
                                let blockedMessage = "도구 '\(pending.name)' 실행이 정책에 의해 차단되었습니다: \(reason)"
                                continuation.yield(.toolResult(
                                    toolCallId: pending.toolCallId,
                                    content: blockedMessage,
                                    isError: true
                                ))
                                recordAudit(
                                    toolCallId: pending.toolCallId,
                                    sessionId: resolvedHookContext.sessionId,
                                    agentId: resolvedHookContext.agentId,
                                    toolName: pending.name,
                                    argumentsHash: argsHash,
                                    riskLevel: riskLevel,
                                    decision: .hookBlocked,
                                    hookName: preResult.hookName,
                                    startTime: startTime,
                                    resultCode: BridgeErrorCode.toolPermissionDenied.rawValue
                                )
                                throw NativeLLMError(
                                    code: .toolExecutionFailed,
                                    message: blockedMessage,
                                    statusCode: nil,
                                    retryAfterSeconds: nil
                                )

                            case .mask(let maskedArguments):
                                effectiveArguments = maskedArguments.toNativeDict()

                            case .allow:
                                effectiveArguments = arguments
                            }

                            let result = await toolService.execute(name: pending.name, arguments: effectiveArguments)
                            continuation.yield(.toolResult(
                                toolCallId: pending.toolCallId,
                                content: result.content,
                                isError: result.isError
                            ))

                            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
                            runtimeMetrics?.recordHistogram(
                                name: MetricName.toolLatencyMs,
                                labels: Self.metricLabels(
                                    provider: currentRequest.provider.rawValue,
                                    sessionId: resolvedHookContext.sessionId,
                                    toolName: pending.name
                                ),
                                value: Double(latencyMs)
                            )
                            _ = hookPipeline.runPostHooks(
                                context: toolHookContext,
                                result: result,
                                latencyMs: latencyMs
                            )

                            let decision: ToolAuditDecision = riskLevel == ToolCategory.safe.rawValue ? .allowed : .approved
                            recordAudit(
                                toolCallId: pending.toolCallId,
                                sessionId: resolvedHookContext.sessionId,
                                agentId: resolvedHookContext.agentId,
                                toolName: pending.name,
                                argumentsHash: argsHash,
                                riskLevel: riskLevel,
                                decision: result.isError ? .policyBlocked : decision,
                                hookName: nil,
                                startTime: startTime,
                                resultCode: result.isError ? BridgeErrorCode.toolExecutionFailed.rawValue : nil
                            )

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

                        let refreshedTools = Self.resolveFollowUpTools(
                            currentRequest: currentRequest,
                            toolRefreshContext: toolRefreshContext,
                            toolService: toolService
                        )
                        currentRequest = Self.makeFollowUpRequest(
                            from: currentRequest,
                            assistantText: accumulatedAssistantText,
                            toolUses: pendingToolUses,
                            toolResults: executedToolResults,
                            tools: refreshedTools
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
    private static func normalizedHookContext(_ context: NativeAgentLoopHookContext?) -> NativeAgentLoopHookContext {
        guard let context else {
            return NativeAgentLoopHookContext(
                sessionId: UUID().uuidString,
                workspaceId: "",
                agentId: nil
            )
        }

        let sessionId = context.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspaceId = context.workspaceId.trimmingCharacters(in: .whitespacesAndNewlines)
        return NativeAgentLoopHookContext(
            sessionId: sessionId.isEmpty ? UUID().uuidString : sessionId,
            workspaceId: workspaceId,
            agentId: context.agentId
        )
    }

    private static func metricLabels(
        provider: String,
        sessionId: String,
        toolName: String? = nil
    ) -> [String: String] {
        var labels: [String: String] = [
            "provider": provider,
            "session": sessionId
        ]
        if let toolName, !toolName.isEmpty {
            labels["tool"] = toolName
        }
        return labels
    }

    private static func makeToolSignature(for toolUses: [PendingToolUse]) -> String {
        toolUses
            .map { "\($0.name)|\($0.inputJSON)" }
            .joined(separator: "||")
    }

    private static func makeCodableArguments(from arguments: [String: Any]) -> [String: AnyCodableValue] {
        arguments.reduce(into: [String: AnyCodableValue]()) { result, entry in
            result[entry.key] = makeCodableValue(entry.value)
        }
    }

    private static func makeCodableValue(_ value: Any) -> AnyCodableValue {
        switch value {
        case let string as String:
            return .string(string)

        case let bool as Bool:
            return .bool(bool)

        case let int as Int:
            return .int(int)

        case let int8 as Int8:
            return makeSafeIntegerCodable(int8)

        case let int16 as Int16:
            return makeSafeIntegerCodable(int16)

        case let int32 as Int32:
            return makeSafeIntegerCodable(int32)

        case let int64 as Int64:
            return makeSafeIntegerCodable(int64)

        case let uint as UInt:
            return makeSafeIntegerCodable(uint)

        case let uint8 as UInt8:
            return makeSafeIntegerCodable(uint8)

        case let uint16 as UInt16:
            return makeSafeIntegerCodable(uint16)

        case let uint32 as UInt32:
            return makeSafeIntegerCodable(uint32)

        case let uint64 as UInt64:
            return makeSafeIntegerCodable(uint64)

        case let double as Double:
            return .double(double)

        case let float as Float:
            return .double(Double(float))

        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            let doubleValue = number.doubleValue
            if floor(doubleValue) == doubleValue,
               let exactInt = Int(exactly: number.int64Value),
               Double(exactInt) == doubleValue {
                return .int(exactInt)
            }
            return .double(doubleValue)

        case let dictionary as [String: Any]:
            return .object(makeCodableArguments(from: dictionary))

        case let array as [Any]:
            return .array(array.map(makeCodableValue))

        case _ as NSNull:
            return .null

        default:
            return .string(String(describing: value))
        }
    }

    private static func makeSafeIntegerCodable<T: BinaryInteger>(_ value: T) -> AnyCodableValue {
        if let exact = Int(exactly: value) {
            return .int(exact)
        }
        return .double(Double(value))
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

    func riskLevel(for toolName: String) -> String {
        toolService?.toolInfo(named: toolName)?.category.rawValue ?? ToolCategory.safe.rawValue
    }

    func recordAudit(
        toolCallId: String,
        sessionId: String,
        agentId: String?,
        toolName: String,
        argumentsHash: String,
        riskLevel: String,
        decision: ToolAuditDecision,
        hookName: String?,
        startTime: Date,
        resultCode: Int?
    ) {
        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
        let event = ToolAuditEvent(
            toolCallId: toolCallId,
            sessionId: sessionId,
            agentId: agentId,
            toolName: toolName,
            argumentsHash: argumentsHash,
            riskLevel: riskLevel,
            decision: decision,
            hookName: hookName,
            latencyMs: latencyMs,
            resultCode: resultCode,
            timestamp: Date()
        )

        auditLog.append(event)
        if auditLog.count > Self.maxAuditEntries {
            auditLog.removeFirst(auditLog.count - Self.maxAuditEntries)
        }
        Log.runtime.info("Native audit: \(toolName) → \(decision.rawValue) (\(latencyMs)ms)")
    }

    private static func makeFollowUpRequest(
        from request: NativeLLMRequest,
        assistantText: String,
        toolUses: [PendingToolUse],
        toolResults: [ExecutedToolResult],
        tools: [NativeLLMToolDefinition]
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
            tools: tools,
            maxTokens: request.maxTokens,
            temperature: request.temperature,
            endpointURL: request.endpointURL,
            timeoutSeconds: request.timeoutSeconds,
            anthropicVersion: request.anthropicVersion
        )
    }

    private static func resolveFollowUpTools(
        currentRequest: NativeLLMRequest,
        toolRefreshContext: NativeAgentLoopToolRefreshContext?,
        toolService: (any BuiltInToolServiceProtocol)?
    ) -> [NativeLLMToolDefinition] {
        guard let toolRefreshContext else {
            return currentRequest.tools
        }

        guard toolRefreshContext.supportsToolCalling else {
            return []
        }

        guard let toolService else {
            return currentRequest.tools
        }

        let schemas = toolService.availableToolSchemas(
            for: toolRefreshContext.permissions,
            preferredToolGroups: toolRefreshContext.preferredToolGroups,
            intentHint: toolRefreshContext.intentHint
        )
        return makeNativeToolDefinitions(from: schemas)
    }

    private static func makeNativeToolDefinitions(
        from schemas: [[String: Any]]
    ) -> [NativeLLMToolDefinition] {
        schemas.compactMap { schema in
            guard let function = schema["function"] as? [String: Any],
                  let name = function["name"] as? String,
                  let description = function["description"] as? String,
                  let rawInputSchema = function["parameters"] as? [String: Any] else {
                return nil
            }

            let inputSchema = rawInputSchema.compactMapValues { makeCodableValue($0) }
            return NativeLLMToolDefinition(
                name: name,
                description: description,
                inputSchema: inputSchema
            )
        }
    }
}
