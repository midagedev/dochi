import Foundation

struct ContextCompactionRequest: Sendable {
    let workspaceMemory: String
    let agentMemory: String
    let personalMemory: String
    let messages: [NativeLLMMessage]
    let tokenBudget: Int
    let fixedPromptTokens: Int
    let autoCompactEnabled: Bool
    let conversationSummary: String?
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

@MainActor
final class ContextCompactionService {
    private static let minimumWorkingBudgetTokens = 256
    private static let minimumRetainedMessages = 5
    private static let memoryBudgetRatio = 0.35
    private static let workspaceLayerRatio = 0.50
    private static let agentLayerRatio = 0.30
    private static let personalLayerRatio = 0.20
    private static let maxSummaryChars = 1_200

    func estimateTokens(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return max(trimmed.count / 2, 1)
    }

    func estimateTokens(for messages: [NativeLLMMessage]) -> Int {
        messages.reduce(into: 0) { total, message in
            total += estimateTokens(for: message)
        }
    }

    func estimateTokens(for message: NativeLLMMessage) -> Int {
        message.contents.reduce(into: 0) { total, content in
            total += estimateTokens(for: textFromContent(content))
        }
    }

    func compact(request: ContextCompactionRequest) -> ContextCompactionResult {
        let workingBudget = max(
            request.tokenBudget - max(request.fixedPromptTokens, 0),
            Self.minimumWorkingBudgetTokens
        )

        let originalLayerTokens = estimateTokens(for: request.workspaceMemory) +
            estimateTokens(for: request.agentMemory) +
            estimateTokens(for: request.personalMemory)
        let originalMessageTokens = estimateTokens(for: request.messages)
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
                messages: compactedMessages
            ) > workingBudget, compactedMessages.count > Self.minimumRetainedMessages {
                droppedMessages.append(compactedMessages.removeFirst())
            }

            let availableLayerBudget = max(
                workingBudget - estimateTokens(for: compactedMessages),
                Self.minimumWorkingBudgetTokens / 2
            )
            let currentLayerTokens = estimateTokens(for: workspaceMemory) +
                estimateTokens(for: agentMemory) +
                estimateTokens(for: personalMemory)

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
                    note: "[워크스페이스 메모리 축약됨]"
                )
                workspaceMemory = workspaceResult.text
                truncatedWorkspace = workspaceResult.truncated

                let agentResult = trimText(
                    agentMemory,
                    tokenBudget: agentBudget,
                    note: "[에이전트 메모리 축약됨]"
                )
                agentMemory = agentResult.text
                truncatedAgent = agentResult.truncated

                let personalResult = trimText(
                    personalMemory,
                    tokenBudget: personalBudget,
                    note: "[개인 메모리 축약됨]"
                )
                personalMemory = personalResult.text
                truncatedPersonal = personalResult.truncated
            }
        }

        let compactedLayerTokens = estimateTokens(for: workspaceMemory) +
            estimateTokens(for: agentMemory) +
            estimateTokens(for: personalMemory)

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
        if estimateTokens(for: compactedMessages) > messageBudget {
            compactedMessages = compactFailSafeMessages(
                currentMessages: compactedMessages,
                messageBudget: messageBudget
            )
            if summarySnapshot == nil {
                summarySnapshot = makeSummarySnapshot(
                    droppedMessages: droppedMessages,
                    conversationSummary: request.conversationSummary
                )
            }
            usedSummaryFallback = summarySnapshot != nil
        }

        let finalTotal = compactedLayerTokens + estimateTokens(for: compactedMessages)
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
}

private extension ContextCompactionService {
    func totalTokens(
        workspaceMemory: String,
        agentMemory: String,
        personalMemory: String,
        messages: [NativeLLMMessage]
    ) -> Int {
        estimateTokens(for: workspaceMemory) +
            estimateTokens(for: agentMemory) +
            estimateTokens(for: personalMemory) +
            estimateTokens(for: messages)
    }

    func trimText(_ text: String, tokenBudget: Int, note: String) -> (text: String, truncated: Bool) {
        guard !text.isEmpty else { return ("", false) }
        let maxChars = max(tokenBudget * 2, 0)
        guard text.count > maxChars, maxChars > note.count + 16 else {
            return (text, false)
        }

        let trimmedBody = String(text.prefix(maxChars - note.count - 2))
        return ("\(trimmedBody)\n\(note)", true)
    }

    func compactFailSafeMessages(
        currentMessages: [NativeLLMMessage],
        messageBudget: Int
    ) -> [NativeLLMMessage] {
        guard !currentMessages.isEmpty else {
            return []
        }

        let preferredCount = min(Self.minimumRetainedMessages, currentMessages.count)
        var failSafeMessages = Array(currentMessages.suffix(preferredCount))

        if estimateTokens(for: failSafeMessages) <= messageBudget {
            return failSafeMessages
        }

        let perMessageBudget = max(messageBudget / max(failSafeMessages.count, 1), 16)
        failSafeMessages = failSafeMessages.map { trimmedMessage($0, tokenBudget: perMessageBudget) }

        if estimateTokens(for: failSafeMessages) <= messageBudget {
            return failSafeMessages
        }

        while estimateTokens(for: failSafeMessages) > messageBudget, failSafeMessages.count > 1 {
            failSafeMessages.removeFirst()
        }

        if estimateTokens(for: failSafeMessages) <= messageBudget {
            return failSafeMessages
        }

        guard let lastMessage = failSafeMessages.last else { return [] }
        return [trimmedMessage(lastMessage, tokenBudget: messageBudget)]
    }

    func trimmedMessage(_ message: NativeLLMMessage, tokenBudget: Int) -> NativeLLMMessage {
        let maxChars = max(tokenBudget * 2, 48)
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
