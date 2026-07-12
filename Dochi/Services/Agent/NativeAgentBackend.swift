import AgentRuntimeCore
import Foundation

/// In-process AgentRuntimeKit backend used on iPhone and as an offline/native
/// option on macOS. Dochi continues to own presentation, STT, TTS, and avatar
/// state; this type owns only conversation execution.
@MainActor
@Observable
final class NativeAgentBackend: AgentBackendProtocol {
    private struct CachedHistory {
        var messages: [AgentMessage]
        var providerID: String?
        var model: String?
    }

    private(set) var connectionState: AgentBackendConnectionState = .disconnected {
        didSet {
            if oldValue != connectionState {
                onConnectionStateChanged?(connectionState)
            }
        }
    }

    @ObservationIgnored var onProactiveMessage: (@MainActor (String) -> Void)?
    @ObservationIgnored var onConnectionStateChanged: (@MainActor (AgentBackendConnectionState) -> Void)?

    private let runtime: AgentRuntime
    private let checkpointStore: (any AgentCheckpointStore)?
    private let definitionProvider: @MainActor () -> AgentDefinition
    private let configurationReloader: (@MainActor () async throws -> Void)?
    private let appID: String
    private var histories: [String: CachedHistory] = [:]
    private var connectionTask: Task<Void, Never>?
    private var connectionAttemptID: UUID?
    private var inFlightTasks: [UUID: Task<Void, Never>] = [:]

    init(
        runtime: AgentRuntime,
        agent: AgentDefinition,
        appID: String = "com.hckim.dochi",
        checkpointStore: (any AgentCheckpointStore)? = nil
    ) {
        self.runtime = runtime
        self.checkpointStore = checkpointStore
        self.definitionProvider = { agent }
        self.configurationReloader = nil
        self.appID = appID
    }

    init(
        runtime: AgentRuntime,
        appID: String = "com.hckim.dochi",
        checkpointStore: (any AgentCheckpointStore)? = nil,
        definitionProvider: @escaping @MainActor () -> AgentDefinition,
        configurationReloader: @escaping @MainActor () async throws -> Void
    ) {
        self.runtime = runtime
        self.checkpointStore = checkpointStore
        self.definitionProvider = definitionProvider
        self.configurationReloader = configurationReloader
        self.appID = appID
    }

    func connect() {
        switch connectionState {
        case .connecting, .connected:
            return
        case .disconnected, .failed:
            break
        }
        connectionTask?.cancel()
        connectionTask = nil
        connectionAttemptID = nil

        guard let configurationReloader else {
            connectionState = .connected(name: definitionProvider().id)
            return
        }

        let attemptID = UUID()
        connectionAttemptID = attemptID
        connectionState = .connecting
        connectionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if connectionAttemptID == attemptID {
                    connectionTask = nil
                    connectionAttemptID = nil
                }
            }
            do {
                try await configurationReloader()
                try Task.checkCancellation()
                guard connectionAttemptID == attemptID else { return }
                connectionState = .connected(name: definitionProvider().id)
            } catch is CancellationError {
                // A newer connection attempt or an explicit disconnect owns
                // the state now.
            } catch {
                guard connectionAttemptID == attemptID else { return }
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func disconnect() {
        connectionAttemptID = nil
        connectionTask?.cancel()
        connectionTask = nil
        let tasks = Array(inFlightTasks.values)
        inFlightTasks.removeAll()
        for task in tasks { task.cancel() }
        connectionState = .disconnected
    }

    func reconfigure(host: String, port: Int) {
        // Host and port are ignored, but this reloads provider/model settings.
        disconnect()
        connect()
    }

    func replaceConversationHistory(
        _ history: [DochiAgentHistoryMessage],
        conversationId: String,
        user: String?
    ) {
        histories[conversationId] = CachedHistory(
            messages: Self.agentMessages(from: history),
            providerID: nil,
            model: nil
        )
    }

    func removeConversationHistory(conversationId: String, user: String?) {
        histories[conversationId] = nil

        guard let checkpointStore else { return }
        let agentID = definitionProvider().id
        let appID = appID
        Task {
            do {
                try await checkpointStore.deleteAll(
                    appID: appID,
                    userID: user,
                    sessionID: conversationId,
                    agentID: agentID
                )
            } catch {
                Log.storage.error(
                    "Failed to delete native agent checkpoints: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    func send(
        text: String,
        conversationId: String,
        user: String?
    ) -> AsyncThrowingStream<DochiAgentEvent, Error> {
        guard case .connected = connectionState else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NativeAgentBackendError.notConnected)
            }
        }
        let definition = definitionProvider()
        guard !definition.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NativeAgentBackendError.missingModel)
            }
        }

        let cachedHistory = histories[conversationId]

        let runID = UUID()
        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish(throwing: CancellationError())
                    return
                }
                defer { inFlightTasks[runID] = nil }
                do {
                    try Task.checkCancellation()
                    var messages = await messagesForRun(
                        cachedHistory,
                        definition: definition,
                        conversationId: conversationId,
                        user: user
                    )
                    try Task.checkCancellation()
                    messages.append(AgentMessage(role: .user, text: text))
                    let request = AgentRunRequest(
                        sessionID: conversationId,
                        appID: appID,
                        userID: user,
                        agent: definition,
                        messages: messages
                    )
                    for try await event in runtime.run(request) {
                        try Task.checkCancellation()
                        switch event {
                        case .assistantTextDelta(let delta):
                            continuation.yield(.delta(delta))
                        case .toolStarted(let call, let descriptor):
                            continuation.yield(.toolStarted(
                                name: call.name,
                                summary: descriptor.description
                            ))
                        case .toolFinished(let call, let result):
                            continuation.yield(.toolFinished(
                                name: call.name,
                                isError: result.isError,
                                summary: result.summary
                            ))
                        case .completed(let result):
                            histories[conversationId] = CachedHistory(
                                messages: result.messages.filter { $0.role != .system },
                                providerID: definition.providerID,
                                model: definition.model
                            )
                            continuation.yield(.done(
                                text: result.finalMessage.text,
                                messageId: result.finalMessage.id.uuidString
                            ))
                        case .contextProviderFailed(let identifier, let message):
                            Log.runtime.warning(
                                "Native agent context provider failed (\(identifier, privacy: .public)): \(message, privacy: .public)"
                            )
                        case .runStarted, .contextPrepared,
                             .modelStepStarted, .assistantReasoningDelta,
                             .toolRequested, .toolApprovalRequested, .usage,
                             .checkpointSaved:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            inFlightTasks[runID] = task
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func messagesForRun(
        _ cachedHistory: CachedHistory?,
        definition: AgentDefinition,
        conversationId: String,
        user: String?
    ) async -> [AgentMessage] {
        guard let cachedHistory else { return [] }

        let visibleHistory = Self.visibleHistory(from: cachedHistory.messages)
        let fallbackMessages: [AgentMessage]
        if cachedHistory.providerID == definition.providerID,
           cachedHistory.model == definition.model {
            // This history was produced in the current process by the same
            // adapter, so its opaque continuation remains valid.
            fallbackMessages = cachedHistory.messages
        } else {
            // Persisted UI history is deliberately provider-neutral. Never
            // carry opaque provider state across a provider or model switch.
            fallbackMessages = Self.agentMessages(from: visibleHistory)
        }

        guard let checkpointStore else { return fallbackMessages }
        do {
            guard let checkpoint = try await checkpointStore.latest(
                appID: appID,
                userID: user,
                sessionID: conversationId,
                agentID: definition.id
            ),
            checkpoint.providerID == definition.providerID,
            checkpoint.model == definition.model,
            Self.isCompletedTurn(checkpoint),
            Self.visibleHistory(from: checkpoint.messages) == visibleHistory else {
                return fallbackMessages
            }

            // The protected checkpoint is the only persisted source for
            // provider-owned continuation payloads. The visible transcript
            // match prevents a stale or cross-conversation checkpoint from
            // being attached to a different UI conversation.
            return checkpoint.messages.filter { $0.role != .system }
        } catch {
            Log.storage.warning(
                "Failed to restore native agent checkpoint; using visible history: \(error.localizedDescription, privacy: .public)"
            )
            return fallbackMessages
        }
    }

    private static func isCompletedTurn(_ checkpoint: AgentRunCheckpoint) -> Bool {
        guard checkpoint.toolExecutions.allSatisfy({ $0.state == .completed }),
              let finalMessage = checkpoint.messages.last(where: { $0.role != .system }),
              finalMessage.role == .assistant,
              finalMessage.toolCalls.isEmpty else {
            return false
        }
        return checkpoint.messages.allSatisfy { message in
            message.providerContinuation?.providerIdentifier == nil
                || message.providerContinuation?.providerIdentifier == checkpoint.providerID
        }
    }

    private static func visibleHistory(
        from messages: [AgentMessage]
    ) -> [DochiAgentHistoryMessage] {
        messages.compactMap { message in
            guard !message.text.isEmpty else { return nil }
            switch message.role {
            case .user:
                return DochiAgentHistoryMessage(role: .user, text: message.text)
            case .assistant:
                return DochiAgentHistoryMessage(role: .assistant, text: message.text)
            case .system, .tool:
                return nil
            }
        }
    }

    private static func agentMessages(
        from history: [DochiAgentHistoryMessage]
    ) -> [AgentMessage] {
        history.map { message in
            AgentMessage(
                role: message.role == .user ? .user : .assistant,
                text: message.text
            )
        }
    }
}

enum NativeAgentBackendError: LocalizedError {
    case notConnected
    case missingModel

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "네이티브 에이전트가 준비되지 않았습니다."
        case .missingModel:
            "네이티브 에이전트 모델 이름이 비어 있습니다. 설정에서 모델을 입력해주세요."
        }
    }
}
