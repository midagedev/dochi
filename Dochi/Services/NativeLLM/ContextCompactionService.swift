import Foundation

struct ContextCompactionRequest: Sendable {
    let provider: LLMProvider
    let model: String
    let workspaceMemory: String
    let agentMemory: String
    let personalMemory: String
    let messages: [NativeLLMMessage]
    let tokenBudget: Int
    let fixedPromptTokens: Int
    let autoCompactEnabled: Bool
    let conversationSummary: String?

    init(
        provider: LLMProvider = .openai,
        model: String = LLMProvider.openai.onboardingDefaultModel,
        workspaceMemory: String,
        agentMemory: String,
        personalMemory: String,
        messages: [NativeLLMMessage],
        tokenBudget: Int,
        fixedPromptTokens: Int,
        autoCompactEnabled: Bool,
        conversationSummary: String?
    ) {
        self.provider = provider
        self.model = model
        self.workspaceMemory = workspaceMemory
        self.agentMemory = agentMemory
        self.personalMemory = personalMemory
        self.messages = messages
        self.tokenBudget = tokenBudget
        self.fixedPromptTokens = fixedPromptTokens
        self.autoCompactEnabled = autoCompactEnabled
        self.conversationSummary = conversationSummary
    }
}

struct CompactedContextLayers: Sendable {
    let workspaceMemory: String
    let agentMemory: String
    let personalMemory: String
}

struct ContextCompactionMetrics: Sendable {
    let tokenBudget: Int
    let estimatedInputTokensBefore: Int
    let estimatedInputTokensAfter: Int
    let droppedMessageCount: Int
    let usedSummaryFallback: Bool
    let truncatedWorkspaceMemory: Bool
    let truncatedAgentMemory: Bool
    let truncatedPersonalMemory: Bool

    var didCompact: Bool {
        droppedMessageCount > 0 ||
            usedSummaryFallback ||
            truncatedWorkspaceMemory ||
            truncatedAgentMemory ||
            truncatedPersonalMemory ||
            estimatedInputTokensAfter < estimatedInputTokensBefore
    }
}

struct ContextCompactionResult: Sendable {
    let layers: CompactedContextLayers
    let messages: [NativeLLMMessage]
    let summarySnapshot: String?
    let metrics: ContextCompactionMetrics
}

struct ContextTokenizerProfile: Sendable, Equatable {
    let latinCharsPerToken: Double
    let cjkCharsPerToken: Double
    let digitCharsPerToken: Double
    let symbolCharsPerToken: Double
    let systemPromptOverhead: Int
    let perMessageOverhead: Int
    let perToolUseOverhead: Int
    let perToolResultOverhead: Int
    let perToolDefinitionOverhead: Int
}

protocol ContextTokenizerStrategy: Sendable {
    func profile(for provider: LLMProvider, model: String) -> ContextTokenizerProfile
}

struct ProviderAwareContextTokenizerStrategy: ContextTokenizerStrategy {
    func profile(for provider: LLMProvider, model: String) -> ContextTokenizerProfile {
        let lowerModel = model.lowercased()

        switch provider {
        case .openai:
            if lowerModel.contains("o3") || lowerModel.contains("o1") {
                return ContextTokenizerProfile(
                    latinCharsPerToken: 4.1,
                    cjkCharsPerToken: 1.55,
                    digitCharsPerToken: 2.9,
                    symbolCharsPerToken: 2.4,
                    systemPromptOverhead: 16,
                    perMessageOverhead: 6,
                    perToolUseOverhead: 14,
                    perToolResultOverhead: 12,
                    perToolDefinitionOverhead: 26
                )
            }
            return ContextTokenizerProfile(
                latinCharsPerToken: 3.8,
                cjkCharsPerToken: 1.45,
                digitCharsPerToken: 2.8,
                symbolCharsPerToken: 2.2,
                systemPromptOverhead: 14,
                perMessageOverhead: 5,
                perToolUseOverhead: 13,
                perToolResultOverhead: 11,
                perToolDefinitionOverhead: 24
            )

        case .anthropic:
            return ContextTokenizerProfile(
                latinCharsPerToken: 4.0,
                cjkCharsPerToken: 1.50,
                digitCharsPerToken: 2.9,
                symbolCharsPerToken: 2.3,
                systemPromptOverhead: 18,
                perMessageOverhead: 6,
                perToolUseOverhead: 15,
                perToolResultOverhead: 12,
                perToolDefinitionOverhead: 28
            )

        case .zai:
            return ContextTokenizerProfile(
                latinCharsPerToken: 3.9,
                cjkCharsPerToken: 1.42,
                digitCharsPerToken: 2.8,
                symbolCharsPerToken: 2.2,
                systemPromptOverhead: 14,
                perMessageOverhead: 5,
                perToolUseOverhead: 13,
                perToolResultOverhead: 11,
                perToolDefinitionOverhead: 24
            )

        case .ollama:
            if lowerModel.contains("qwen") {
                return ContextTokenizerProfile(
                    latinCharsPerToken: 3.6,
                    cjkCharsPerToken: 1.32,
                    digitCharsPerToken: 2.6,
                    symbolCharsPerToken: 2.1,
                    systemPromptOverhead: 12,
                    perMessageOverhead: 5,
                    perToolUseOverhead: 12,
                    perToolResultOverhead: 10,
                    perToolDefinitionOverhead: 22
                )
            }
            return ContextTokenizerProfile(
                latinCharsPerToken: 3.7,
                cjkCharsPerToken: 1.38,
                digitCharsPerToken: 2.7,
                symbolCharsPerToken: 2.2,
                systemPromptOverhead: 12,
                perMessageOverhead: 5,
                perToolUseOverhead: 12,
                perToolResultOverhead: 10,
                perToolDefinitionOverhead: 22
            )

        case .lmStudio:
            return ContextTokenizerProfile(
                latinCharsPerToken: 3.7,
                cjkCharsPerToken: 1.40,
                digitCharsPerToken: 2.7,
                symbolCharsPerToken: 2.2,
                systemPromptOverhead: 12,
                perMessageOverhead: 5,
                perToolUseOverhead: 12,
                perToolResultOverhead: 10,
                perToolDefinitionOverhead: 22
            )
        }
    }
}

@MainActor
final class ContextCompactionService {
    private static let minimumWorkingBudgetTokens = 256
    private static let minimumRetainedMessages = 5
    private static let memoryBudgetRatio = 0.35
    private static let workspaceLayerRatio = 0.50
    private static let agentLayerRatio = 0.30
    private static let personalLayerRatio = 0.20
    private static let maxSummaryChars = 1_200
    private let tokenizerStrategy: any ContextTokenizerStrategy

    init(tokenizerStrategy: any ContextTokenizerStrategy = ProviderAwareContextTokenizerStrategy()) {
        self.tokenizerStrategy = tokenizerStrategy
    }

    func estimateTokens(for text: String) -> Int {
        estimateTokens(
            for: text,
            provider: .openai,
            model: LLMProvider.openai.onboardingDefaultModel
        )
    }

    func estimateTokens(
        for text: String,
        provider: LLMProvider,
        model: String
    ) -> Int {
        let profile = tokenizerStrategy.profile(for: provider, model: model)
        return estimateTextTokens(for: text, profile: profile)
    }

    func estimateSystemPromptTokens(
        for text: String,
        provider: LLMProvider,
        model: String
    ) -> Int {
        let profile = tokenizerStrategy.profile(for: provider, model: model)
        let textTokens = estimateTextTokens(for: text, profile: profile)
        return textTokens == 0 ? 0 : textTokens + profile.systemPromptOverhead
    }

    func estimateTokens(for messages: [NativeLLMMessage]) -> Int {
        estimateTokens(
            for: messages,
            provider: .openai,
            model: LLMProvider.openai.onboardingDefaultModel
        )
    }

    func estimateTokens(
        for messages: [NativeLLMMessage],
        provider: LLMProvider,
        model: String
    ) -> Int {
        let profile = tokenizerStrategy.profile(for: provider, model: model)
        return estimateTokens(for: messages, profile: profile)
    }

    func estimateTokens(for message: NativeLLMMessage) -> Int {
        estimateTokens(
            for: message,
            provider: .openai,
            model: LLMProvider.openai.onboardingDefaultModel
        )
    }

    func estimateTokens(
        for message: NativeLLMMessage,
        provider: LLMProvider,
        model: String
    ) -> Int {
        let profile = tokenizerStrategy.profile(for: provider, model: model)
        return estimateTokens(for: message, profile: profile)
    }

    func estimateTokens(
        for tools: [NativeLLMToolDefinition],
        provider: LLMProvider,
        model: String
    ) -> Int {
        guard !tools.isEmpty else { return 0 }
        let profile = tokenizerStrategy.profile(for: provider, model: model)
        return tools.reduce(into: 0) { total, tool in
            let schemaJSONString = serializedJSON(jsonObject(from: tool.inputSchema))
            total += profile.perToolDefinitionOverhead
            total += estimateTextTokens(for: tool.name, profile: profile)
            total += estimateTextTokens(for: tool.description, profile: profile)
            total += estimateTextTokens(for: schemaJSONString, profile: profile)
        }
    }

    func estimateRequestInputTokens(
        systemPrompt: String?,
        messages: [NativeLLMMessage],
        tools: [NativeLLMToolDefinition],
        provider: LLMProvider,
        model: String
    ) -> Int {
        let promptTokens = estimateSystemPromptTokens(
            for: systemPrompt ?? "",
            provider: provider,
            model: model
        )
        let messageTokens = estimateTokens(
            for: messages,
            provider: provider,
            model: model
        )
        let toolTokens = estimateTokens(
            for: tools,
            provider: provider,
            model: model
        )
        return promptTokens + messageTokens + toolTokens
    }

    func compact(request: ContextCompactionRequest) -> ContextCompactionResult {
        let profile = tokenizerStrategy.profile(for: request.provider, model: request.model)
        let workingBudget = max(
            request.tokenBudget - max(request.fixedPromptTokens, 0),
            Self.minimumWorkingBudgetTokens
        )

        let originalLayerTokens = estimateTextTokens(for: request.workspaceMemory, profile: profile) +
            estimateTextTokens(for: request.agentMemory, profile: profile) +
            estimateTextTokens(for: request.personalMemory, profile: profile)
        let originalMessageTokens = estimateTokens(for: request.messages, profile: profile)
        let originalTotal = originalLayerTokens + originalMessageTokens

        var workspaceMemory = request.workspaceMemory
        var agentMemory = request.agentMemory
        var personalMemory = request.personalMemory
        var truncatedWorkspace = false
        var truncatedAgent = false
        var truncatedPersonal = false

        var compactedMessages = request.messages
        var droppedMessages: [NativeLLMMessage] = []
        let shouldCompact = request.autoCompactEnabled || originalTotal > workingBudget
        if shouldCompact {
            while totalTokens(
                workspaceMemory: workspaceMemory,
                agentMemory: agentMemory,
                personalMemory: personalMemory,
                messages: compactedMessages,
                profile: profile
            ) > workingBudget, compactedMessages.count > Self.minimumRetainedMessages {
                droppedMessages.append(compactedMessages.removeFirst())
            }

            let availableLayerBudget = max(
                workingBudget - estimateTokens(for: compactedMessages, profile: profile),
                Self.minimumWorkingBudgetTokens / 2
            )
            let currentLayerTokens = estimateTextTokens(for: workspaceMemory, profile: profile) +
                estimateTextTokens(for: agentMemory, profile: profile) +
                estimateTextTokens(for: personalMemory, profile: profile)

            if currentLayerTokens > availableLayerBudget {
                let memoryBudget = max(
                    Int(Double(availableLayerBudget) * Self.memoryBudgetRatio),
                    Self.minimumWorkingBudgetTokens / 2
                )
                let workspaceBudget = max(Int(Double(memoryBudget) * Self.workspaceLayerRatio), 32)
                let agentBudget = max(Int(Double(memoryBudget) * Self.agentLayerRatio), 32)
                let personalBudget = max(Int(Double(memoryBudget) * Self.personalLayerRatio), 32)

                let workspaceResult = trimText(
                    workspaceMemory,
                    tokenBudget: workspaceBudget,
                    note: "[워크스페이스 메모리 축약됨]",
                    profile: profile
                )
                workspaceMemory = workspaceResult.text
                truncatedWorkspace = workspaceResult.truncated

                let agentResult = trimText(
                    agentMemory,
                    tokenBudget: agentBudget,
                    note: "[에이전트 메모리 축약됨]",
                    profile: profile
                )
                agentMemory = agentResult.text
                truncatedAgent = agentResult.truncated

                let personalResult = trimText(
                    personalMemory,
                    tokenBudget: personalBudget,
                    note: "[개인 메모리 축약됨]",
                    profile: profile
                )
                personalMemory = personalResult.text
                truncatedPersonal = personalResult.truncated
            }
        }

        let compactedLayerTokens = estimateTextTokens(for: workspaceMemory, profile: profile) +
            estimateTextTokens(for: agentMemory, profile: profile) +
            estimateTextTokens(for: personalMemory, profile: profile)

        var summarySnapshot: String?
        var usedSummaryFallback = false
        if shouldCompact, !droppedMessages.isEmpty {
            summarySnapshot = makeSummarySnapshot(
                droppedMessages: droppedMessages,
                conversationSummary: request.conversationSummary
            )
            usedSummaryFallback = summarySnapshot != nil
        }

        let messageBudget = max(workingBudget - compactedLayerTokens, 48)
        if estimateTokens(for: compactedMessages, profile: profile) > messageBudget {
            compactedMessages = compactFailSafeMessages(
                currentMessages: compactedMessages,
                messageBudget: messageBudget,
                profile: profile
            )
            if summarySnapshot == nil {
                summarySnapshot = makeSummarySnapshot(
                    droppedMessages: droppedMessages,
                    conversationSummary: request.conversationSummary
                )
            }
            usedSummaryFallback = summarySnapshot != nil
        }

        let finalTotal = compactedLayerTokens + estimateTokens(for: compactedMessages, profile: profile)
        let metrics = ContextCompactionMetrics(
            tokenBudget: workingBudget,
            estimatedInputTokensBefore: originalTotal,
            estimatedInputTokensAfter: finalTotal,
            droppedMessageCount: droppedMessages.count,
            usedSummaryFallback: usedSummaryFallback,
            truncatedWorkspaceMemory: truncatedWorkspace,
            truncatedAgentMemory: truncatedAgent,
            truncatedPersonalMemory: truncatedPersonal
        )

        if metrics.didCompact {
            Log.runtime.info(
                "Context compaction applied (before: \(metrics.estimatedInputTokensBefore), after: \(metrics.estimatedInputTokensAfter), dropped: \(metrics.droppedMessageCount), fallback: \(metrics.usedSummaryFallback))"
            )
        }

        return ContextCompactionResult(
            layers: CompactedContextLayers(
                workspaceMemory: workspaceMemory,
                agentMemory: agentMemory,
                personalMemory: personalMemory
            ),
            messages: compactedMessages,
            summarySnapshot: summarySnapshot,
            metrics: metrics
        )
    }

    private func estimateTextTokens(for text: String, profile: ContextTokenizerProfile) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        var latinCount = 0
        var cjkCount = 0
        var digitCount = 0
        var symbolCount = 0

        for scalar in trimmed.unicodeScalars {
            if scalar.properties.isWhitespace {
                continue
            } else if scalar.properties.numericType != nil {
                digitCount += 1
            } else if isCJK(scalar) {
                cjkCount += 1
            } else if isLatinLike(scalar) {
                latinCount += 1
            } else {
                symbolCount += 1
            }
        }

        let estimated = (Double(latinCount) / profile.latinCharsPerToken) +
            (Double(cjkCount) / profile.cjkCharsPerToken) +
            (Double(digitCount) / profile.digitCharsPerToken) +
            (Double(symbolCount) / profile.symbolCharsPerToken)
        return max(Int(ceil(estimated)), 1)
    }

    private func estimateTokens(for messages: [NativeLLMMessage], profile: ContextTokenizerProfile) -> Int {
        messages.reduce(into: 0) { total, message in
            total += estimateTokens(for: message, profile: profile)
        }
    }

    private func estimateTokens(for message: NativeLLMMessage, profile: ContextTokenizerProfile) -> Int {
        var total = profile.perMessageOverhead
        for content in message.contents {
            switch content {
            case .text(let text):
                total += estimateTextTokens(for: text, profile: profile)
            case .toolUse(let toolCallId, let name, let inputJSON):
                total += profile.perToolUseOverhead
                total += estimateTextTokens(for: toolCallId, profile: profile)
                total += estimateTextTokens(for: name, profile: profile)
                total += estimateTextTokens(for: inputJSON, profile: profile)
            case .toolResult(let toolCallId, let content, _):
                total += profile.perToolResultOverhead
                total += estimateTextTokens(for: toolCallId, profile: profile)
                total += estimateTextTokens(for: content, profile: profile)
            }
        }
        return total
    }

    private func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x11FF, // Hangul Jamo
             0x2E80...0x2EFF, // CJK Radicals Supplement
             0x2F00...0x2FDF, // Kangxi Radicals
             0x3040...0x30FF, // Hiragana + Katakana
             0x3130...0x318F, // Hangul Compatibility Jamo
             0x31C0...0x31EF, // CJK Strokes
             0x3400...0x4DBF, // CJK Unified Ideographs Extension A
             0x4E00...0x9FFF, // CJK Unified Ideographs
             0xAC00...0xD7AF, // Hangul Syllables
             0xF900...0xFAFF, // CJK Compatibility Ideographs
             0xFF66...0xFF9D: // Halfwidth Katakana
            return true
        default:
            return false
        }
    }

    private func isLatinLike(_ scalar: Unicode.Scalar) -> Bool {
        (0x0041...0x005A).contains(scalar.value) || // A-Z
            (0x0061...0x007A).contains(scalar.value) || // a-z
            (0x00C0...0x024F).contains(scalar.value) // Latin extended
    }

    private func serializedJSON(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }

    private func jsonObject(from object: [String: AnyCodableValue]) -> [String: Any] {
        object.mapValues(jsonValue)
    }

    private func jsonValue(_ value: AnyCodableValue) -> Any {
        switch value {
        case .string(let string):
            return string
        case .int(let int):
            return int
        case .double(let double):
            return double
        case .bool(let bool):
            return bool
        case .null:
            return NSNull()
        case .array(let values):
            return values.map(jsonValue)
        case .object(let object):
            return object.mapValues(jsonValue)
        }
    }
}

private extension ContextCompactionService {
    func totalTokens(
        workspaceMemory: String,
        agentMemory: String,
        personalMemory: String,
        messages: [NativeLLMMessage],
        profile: ContextTokenizerProfile
    ) -> Int {
        estimateTextTokens(for: workspaceMemory, profile: profile) +
            estimateTextTokens(for: agentMemory, profile: profile) +
            estimateTextTokens(for: personalMemory, profile: profile) +
            estimateTokens(for: messages, profile: profile)
    }

    func trimText(
        _ text: String,
        tokenBudget: Int,
        note: String,
        profile: ContextTokenizerProfile
    ) -> (text: String, truncated: Bool) {
        guard !text.isEmpty else { return ("", false) }
        let maxChars = max(
            Int(Double(max(tokenBudget, 0)) * max(profile.latinCharsPerToken, 1.5)),
            0
        )
        guard text.count > maxChars, maxChars > note.count + 16 else {
            return (text, false)
        }

        let trimmedBody = String(text.prefix(maxChars - note.count - 2))
        return ("\(trimmedBody)\n\(note)", true)
    }

    func compactFailSafeMessages(
        currentMessages: [NativeLLMMessage],
        messageBudget: Int,
        profile: ContextTokenizerProfile
    ) -> [NativeLLMMessage] {
        guard !currentMessages.isEmpty else {
            return []
        }

        let preferredCount = min(Self.minimumRetainedMessages, currentMessages.count)
        var failSafeMessages = Array(currentMessages.suffix(preferredCount))

        if estimateTokens(for: failSafeMessages, profile: profile) <= messageBudget {
            return failSafeMessages
        }

        let perMessageBudget = max(messageBudget / max(failSafeMessages.count, 1), 16)
        failSafeMessages = failSafeMessages.map {
            trimmedMessage($0, tokenBudget: perMessageBudget, profile: profile)
        }

        if estimateTokens(for: failSafeMessages, profile: profile) <= messageBudget {
            return failSafeMessages
        }

        while estimateTokens(for: failSafeMessages, profile: profile) > messageBudget, failSafeMessages.count > 1 {
            failSafeMessages.removeFirst()
        }

        if estimateTokens(for: failSafeMessages, profile: profile) <= messageBudget {
            return failSafeMessages
        }

        guard let lastMessage = failSafeMessages.last else { return [] }
        return [trimmedMessage(lastMessage, tokenBudget: messageBudget, profile: profile)]
    }

    func trimmedMessage(
        _ message: NativeLLMMessage,
        tokenBudget: Int,
        profile: ContextTokenizerProfile
    ) -> NativeLLMMessage {
        let maxChars = max(
            Int(Double(max(tokenBudget, 0)) * max(profile.latinCharsPerToken, 1.5)),
            48
        )
        var remaining = maxChars
        var trimmedContents: [NativeLLMMessageContent] = []

        for content in message.contents {
            guard remaining > 0 else { break }
            let contentText = textFromContent(content)
            guard !contentText.isEmpty else { continue }
            let allowed = min(contentText.count, remaining)
            let clipped = String(contentText.suffix(allowed))
            remaining -= clipped.count
            trimmedContents.append(contentWithTrimmedText(content, clippedText: clipped))
        }

        if trimmedContents.isEmpty {
            return NativeLLMMessage(
                role: message.role,
                text: String(textFromMessage(message).suffix(maxChars))
            )
        }
        return NativeLLMMessage(role: message.role, contents: trimmedContents)
    }

    func makeSummarySnapshot(
        droppedMessages: [NativeLLMMessage],
        conversationSummary: String?
    ) -> String? {
        if let summary = conversationSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            let clipped = String(summary.prefix(Self.maxSummaryChars))
            return "이전 대화 요약 스냅샷:\n\(clipped)"
        }

        guard !droppedMessages.isEmpty else { return nil }

        let snippets = droppedMessages.suffix(4).map { message in
            let role: String = {
                switch message.role {
                case .user: return "사용자"
                case .assistant: return "어시스턴트"
                }
            }()
            let text = textFromMessage(message)
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let clipped = String(text.prefix(180))
            return "- \(role): \(clipped)"
        }

        guard !snippets.isEmpty else { return nil }
        let body = snippets.joined(separator: "\n")
        let summary = "이전 대화 요약 스냅샷:\n\(body)"
        return String(summary.prefix(Self.maxSummaryChars))
    }

    func textFromMessage(_ message: NativeLLMMessage) -> String {
        message.contents.map(textFromContent).joined(separator: "\n")
    }

    func textFromContent(_ content: NativeLLMMessageContent) -> String {
        switch content {
        case .text(let text):
            return text
        case .toolUse(let toolCallId, let name, let inputJSON):
            return "[tool_use \(name)#\(toolCallId)] \(inputJSON)"
        case .toolResult(_, let content, _):
            return content
        }
    }

    func contentWithTrimmedText(
        _ original: NativeLLMMessageContent,
        clippedText: String
    ) -> NativeLLMMessageContent {
        switch original {
        case .text:
            return .text(clippedText)
        case .toolUse(let toolCallId, let name, _):
            return .toolUse(toolCallId: toolCallId, name: name, inputJSON: clippedText)
        case .toolResult(let toolCallId, _, let isError):
            return .toolResult(toolCallId: toolCallId, content: clippedText, isError: isError)
        }
    }
}
