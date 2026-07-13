import AgentRuntimeApple
import AgentRuntimeCore
import AgentRuntimeFileMemory
import AgentRuntimeMemory
import AgentRuntimeProviders
import Foundation
import Observation

@MainActor
@Observable
final class MobileAgentController {
    private(set) var phase: MobileAgentPhase = .starting
    private(set) var messages: [MobileChatMessage] = []
    private(set) var streamingText = ""
    private(set) var activeToolName: String?
    private(set) var pendingToolApproval: AgentToolApprovalRequest?
    private(set) var usage = AgentTokenUsage()
    private(set) var ownedMemoryRecords: [MemoryRecord] = []
    private(set) var isLoadingOwnedMemories = false
    private(set) var purgingMemoryID: UUID?
    private(set) var isPurgingAllOwnedMemories = false
    private(set) var memoryManagementErrorMessage: String?
    private(set) var memoryManagementNoticeMessage: String?
    var errorMessage: String?
    var completionFeedbackCounter = 0

    @ObservationIgnored var onAssistantReply: (@MainActor (String) -> Void)?

    var isRunning: Bool { runTask != nil }
    var sessionID: String { preferences.sessionID }
    var isMemoryManagementBusy: Bool {
        isLoadingOwnedMemories || purgingMemoryID != nil || isPurgingAllOwnedMemories
    }
    var fileMemoryStatus: MobileFileMemoryStatus {
        fileMemoryController?.status ?? .disabled
    }

    private let preferences: MobileAgentPreferences
    private let secretStore: KeychainAgentSecretStore
    private let approvalBroker: AgentToolApprovalBroker
    private let providerRegistry: ModelProviderRegistry?
    private let toolRegistry: AgentToolRegistry?
    private let runtime: AgentRuntime?
    private let checkpointStore: (any AgentCheckpointStore)?
    private let memoryRepository: MobileOwnedMemoryRepository?
    private let memoryTools: MemoryToolBundle?
    private let memoryContext: MemoryContextProvider?
    private let fileMemoryController: MobileFileMemoryController?
    private let conversationStore: (any MobileConversationStoring)?
    private var agentHistory: [AgentMessage] = []
    private var runTask: Task<Void, Never>?
    private var approvalTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var activeRunID: UUID?
    private var historyProviderID: String?
    private var historyModelID: String?
    private var hasStarted = false

    private static let appID = "com.hckim.dochi.mobile"
    private static let secretNamespace = appID

    init(preferences: MobileAgentPreferences) {
        self.preferences = preferences
        let secretStore = KeychainAgentSecretStore(configuration: .init(
            accessibility: .whenUnlockedThisDeviceOnly
        ))
        let approvalBroker = AgentToolApprovalBroker()
        self.secretStore = secretStore
        self.approvalBroker = approvalBroker

        do {
            let directory = try Self.supportDirectory()
            let memoryStore = try AppleProtectedMemoryStoreFactory.makeSQLiteStore(
                configuration: .init(
                    databaseURL: directory.appendingPathComponent("agent-memory.sqlite")
                )
            )
            let memoryApproval = MobileMemoryApprovalHandler(broker: approvalBroker)
            let memoryTools = MemoryToolFactory.make(
                store: memoryStore,
                approvalHandler: memoryApproval
            )
            let providerRegistry = ModelProviderRegistry()
            let toolRegistry = try AgentToolRegistry()
            let checkpointStore = ProtectedFileAgentCheckpointStore(configuration: .init(
                directory: directory.appendingPathComponent("checkpoints", isDirectory: true)
            ))
            let auditSink = RedactedJSONLAgentAuditSink(configuration: .init(
                fileURL: directory.appendingPathComponent("agent-audit.jsonl")
            ))
            let memoryContext = MemoryContextProvider(store: memoryStore)
            let fileMemoryController = MobileFileMemoryController(
                appID: Self.appID,
                store: memoryStore,
                localRootURL: try Self.localFileMemoryDirectory(),
                preferencesProvider: {
                    MobileFileMemoryPreferences(
                        memoryEnabled: preferences.memoryEnabled,
                        fileMemoryEnabled: preferences.fileMemoryEnabled,
                        location: preferences.currentFileMemoryLocation
                    )
                }
            )

            self.providerRegistry = providerRegistry
            self.toolRegistry = toolRegistry
            self.checkpointStore = checkpointStore
            self.memoryRepository = MobileOwnedMemoryRepository(
                store: memoryStore,
                appID: Self.appID,
                userID: preferences.userID
            )
            self.memoryTools = memoryTools
            self.memoryContext = memoryContext
            self.fileMemoryController = fileMemoryController
            self.conversationStore = MobileConversationStore(
                fileURL: directory.appendingPathComponent("conversation.json")
            )
            self.runtime = AgentRuntime(
                providers: providerRegistry,
                tools: toolRegistry,
                toolPolicy: DefaultAgentToolPolicy(
                    // Memory writes have their own content-aware policy and
                    // approval handler. Archive remains gated by runtime policy.
                    preapprovedSensitiveTools: ["memory.save", "memory.search"]
                ),
                approvalHandler: approvalBroker,
                checkpointStore: checkpointStore,
                auditSink: auditSink
            )
        } catch {
            providerRegistry = nil
            toolRegistry = nil
            runtime = nil
            checkpointStore = nil
            memoryRepository = nil
            memoryTools = nil
            memoryContext = nil
            fileMemoryController = nil
            conversationStore = nil
            phase = .failed
            errorMessage = error.localizedDescription
        }

        approvalTask = Task { [weak self, approvalBroker] in
            for await request in approvalBroker.requests {
                guard !Task.isCancelled, let self else { return }
                guard request.context.appID == Self.appID,
                      request.context.userID == self.preferences.userID,
                      request.context.sessionID == self.preferences.sessionID,
                      request.context.runID == self.activeRunID else { continue }
                self.pendingToolApproval = request
            }
        }
    }

    func start() async {
        guard !hasStarted, runtime != nil else { return }
        hasStarted = true
        do {
            if let persisted = try await conversationStore?.load(
                fallbackUserID: preferences.userID,
                fallbackSessionID: preferences.sessionID
            ), persisted.userID == preferences.userID {
                preferences.restoreSessionID(persisted.sessionID)
                historyProviderID = persisted.providerID
                historyModelID = persisted.modelID
                replaceHistory(with: persisted.messages)
            }
            try await reloadConfiguration()
            phase = .ready
        } catch is CancellationError {
            // A cancelled SwiftUI `.task` can be started again when the scene
            // returns. Do not permanently latch the controller half-started.
            hasStarted = false
            return
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
        }
    }

    func applyPreferences() async throws {
        try await reloadConfiguration()
        if phase == .failed, runtime != nil { phase = .ready }
    }

    func reloadConfiguration() async throws {
        guard let providerRegistry, let toolRegistry, let runtime else {
            throw MobileAgentError.notInitialized
        }
        await fileMemoryController?.synchronize()
        try await applyMemoryRegistration(
            runtime: runtime,
            toolRegistry: toolRegistry
        )
        let selectedModel = preferences.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedModel.isEmpty else { throw MobileAgentError.emptyModel }

        let resolver = ProviderCredentialResolver(
            secretStore: secretStore,
            namespace: Self.secretNamespace,
            accounts: Dictionary(uniqueKeysWithValues: MobileProviderKind.allCases.map {
                ($0.rawValue, $0.keychainAccount)
            })
        )
        switch preferences.currentProvider {
        case .anthropic:
            await providerRegistry.register(AnthropicMessagesProvider(
                identifier: MobileProviderKind.anthropic.rawValue,
                credentialResolver: resolver
            ))
        case .openAI:
            await providerRegistry.register(OpenAIResponsesProvider(
                identifier: MobileProviderKind.openAI.rawValue,
                credentialResolver: resolver
            ))
        case .gemini:
            await providerRegistry.register(GeminiGenerateContentProvider(
                identifier: MobileProviderKind.gemini.rawValue,
                credentialResolver: resolver
            ))
        case .openAICompatible:
            let endpoint = try MobileCompatibleEndpoint.chatCompletionsEndpoint(
                from: preferences.compatibleBaseURL
            )
            let stored = try await secretStore.loadSecret(
                namespace: Self.secretNamespace,
                account: MobileProviderKind.openAICompatible.keychainAccount
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            let optionalResolver: (any ProviderCredentialResolving)? =
                stored?.isEmpty == false ? resolver : nil
            await providerRegistry.register(OpenAIChatCompletionsProvider(
                identifier: MobileProviderKind.openAICompatible.rawValue,
                endpoint: endpoint,
                credentialResolver: optionalResolver,
                maxOutputTokensParameter: "max_tokens"
            ))
        }

    }

    func send(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, runTask == nil, let runtime else { return }
        guard !isMemoryManagementBusy else {
            errorMessage = MobileMemoryManagementError.operationInProgress.localizedDescription
            return
        }
        guard !preferences.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = MobileAgentError.emptyModel.localizedDescription
            return
        }

        prepareHistoryForCurrentProvider()
        let userMessage = MobileChatMessage(role: .user, text: text).agentMessage
        agentHistory.append(userMessage)
        refreshDisplayMessages()
        streamingText = ""
        errorMessage = nil
        phase = .thinking
        persistConversation()

        let request = AgentRunRequest(
            sessionID: preferences.sessionID,
            appID: Self.appID,
            userID: preferences.userID,
            agent: AgentDefinition(
                id: "도치",
                providerID: preferences.currentProvider.rawValue,
                model: preferences.model.trimmingCharacters(in: .whitespacesAndNewlines),
                instructions: """
                당신은 도치입니다. 사용자가 일상적으로 곁에 두는 친근하고 유능한 AI 동반자입니다. 기본적으로 자연스러운 한국어로 답하고, 허용된 도구와 기억이 도움이 될 때만 사용하세요. 확인되지 않은 사실을 지어내지 말고, 민감하거나 되돌리기 어려운 행동은 실행 전에 승인을 요청하세요.
                """,
                maximumContextSensitivity: .privateData,
                maxOutputTokens: 4_096
            ),
            messages: agentHistory,
            limits: AgentRunLimits(maxSteps: 8, maxToolCalls: 20, maxDuration: .seconds(180)),
            requiresCheckpointPersistence: true
        )
        activeRunID = request.id

        runTask = Task { [weak self] in
            guard let self else { return }
            var completedCheckpointIDs: Set<UUID> = []
            defer {
                self.runTask = nil
                if self.activeRunID == request.id { self.activeRunID = nil }
                if self.phase.isBusy { self.phase = .ready }
            }
            do {
                try await self.reloadConfiguration()
                try Task.checkCancellation()
                for try await event in runtime.run(request) {
                    try Task.checkCancellation()
                    guard self.activeRunID == request.id else { throw CancellationError() }
                    switch event {
                    case .assistantTextDelta(let delta):
                        self.streamingText += delta
                        self.phase = .speaking
                    case .toolStarted(let call, _):
                        self.activeToolName = call.name
                        self.phase = .usingTool
                    case .toolFinished:
                        self.activeToolName = nil
                        self.phase = .thinking
                    case .toolApprovalRequested(let approval):
                        self.pendingToolApproval = approval
                    case .usage(let latest):
                        self.usage = latest
                    case .completed(let result):
                        if let checkpoint = result.lastCheckpoint {
                            completedCheckpointIDs.insert(checkpoint.id)
                        }
                        self.historyProviderID = request.agent.providerID
                        self.historyModelID = request.agent.model
                        self.replaceHistory(with: result.messages)
                        let finalText = result.finalMessage.text
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        self.streamingText = ""
                        self.activeToolName = nil
                        self.pendingToolApproval = nil
                        do {
                            try await self.persistCompletedConversation(
                                checkpointIDs: completedCheckpointIDs
                            )
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            throw MobileAgentError.completedConversationPersistenceFailed
                        }
                        self.phase = .ready
                        self.completionFeedbackCounter += 1
                        if !finalText.isEmpty { self.onAssistantReply?(finalText) }
                    case .checkpointSaved(let checkpoint):
                        completedCheckpointIDs.insert(checkpoint.id)
                    case .runStarted, .contextPrepared, .contextProviderFailed,
                         .modelStepStarted, .assistantReasoningDelta,
                         .toolRequested:
                        break
                    }
                }
            } catch is CancellationError {
                guard self.activeRunID == request.id else { return }
                self.preservePartialReply()
                self.phase = .ready
            } catch {
                guard self.activeRunID == request.id else { return }
                self.preservePartialReply()
                self.phase = .failed
                self.errorMessage = error.localizedDescription
            }
            if self.pendingToolApproval?.context.runID == request.id {
                self.pendingToolApproval = nil
            }
            await self.approvalBroker.cancelAll(reason: "에이전트 실행이 종료되었습니다.")
        }
    }

    func cancel() {
        guard runTask != nil else { return }
        runTask?.cancel()
        activeToolName = nil
        pendingToolApproval = nil
        Task { await approvalBroker.cancelAll(reason: "사용자가 실행을 중단했습니다.") }
    }

    func newConversation() {
        let previousIdentity = MobileCheckpointIdentity(
            appID: Self.appID,
            userID: preferences.userID,
            sessionID: preferences.sessionID,
            agentID: Self.agentID
        )
        let previousRunTask = runTask
        let wasRunning = runTask != nil
        activeRunID = nil
        previousRunTask?.cancel()
        pendingToolApproval = nil
        activeToolName = nil
        streamingText = ""
        replaceHistory(with: [])
        historyProviderID = preferences.currentProvider.rawValue
        historyModelID = preferences.model.trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.beginNewSession()
        errorMessage = nil
        phase = wasRunning ? .starting : .ready
        persistConversation()
        Task { await approvalBroker.cancelAll(reason: "새 대화를 시작했습니다.") }
        Task { [checkpointStore] in
            // Wait until cancellation has fully unwound so a write-ahead
            // checkpoint cannot appear after cleanup has already inspected the
            // old conversation identity.
            await previousRunTask?.value
            guard let checkpointStore else { return }
            _ = try? await MobileCheckpointCleanup.deleteConversationIfSafe(
                previousIdentity,
                from: checkpointStore
            )
        }
    }

    func resolveApproval(
        _ decision: AgentToolApprovalDecision,
        requestID: UUID? = nil
    ) {
        guard let pendingToolApproval else { return }
        guard requestID == nil || requestID == pendingToolApproval.id else { return }
        self.pendingToolApproval = nil
        let enforcedDecision: AgentToolApprovalDecision
        if case .allowForSession = decision,
           !MobileToolPresentation.allowsSessionApproval(pendingToolApproval) {
            enforcedDecision = .allowOnce
        } else {
            enforcedDecision = decision
        }
        Task {
            await approvalBroker.resolve(
                requestID: pendingToolApproval.id,
                decision: enforcedDecision
            )
        }
    }

    func dismissError() {
        errorMessage = nil
        if phase == .failed, runtime != nil { phase = .ready }
    }

    func refreshFileMemory() async {
        await fileMemoryController?.synchronize()
        guard let runtime, let toolRegistry else { return }
        do {
            try await applyMemoryRegistration(
                runtime: runtime,
                toolRegistry: toolRegistry
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyMemoryRegistration(
        runtime: AgentRuntime,
        toolRegistry: AgentToolRegistry
    ) async throws {
        let shouldEnable = preferences.memoryEnabled
            && (fileMemoryController?.allowsMemoryAccess ?? true)
        guard shouldEnable, let memoryContext, let memoryTools else {
            if let memoryContext {
                await runtime.contexts.remove(identifier: memoryContext.identifier)
            }
            for name in ["memory.save", "memory.search", "memory.archive"] {
                await toolRegistry.remove(named: name)
            }
            return
        }

        do {
            for tool in memoryTools.tools {
                try await toolRegistry.replace(tool)
            }
            await runtime.contexts.register(memoryContext)
        } catch {
            await runtime.contexts.remove(identifier: memoryContext.identifier)
            for name in ["memory.save", "memory.search", "memory.archive"] {
                await toolRegistry.remove(named: name)
            }
            throw error
        }
    }

    func refreshOwnedMemories() async {
        guard !isLoadingOwnedMemories else { return }
        guard let memoryRepository = beginMemoryManagementOperation() else { return }
        isLoadingOwnedMemories = true
        memoryManagementNoticeMessage = nil
        defer { isLoadingOwnedMemories = false }
        do {
            let records = try await memoryRepository.records()
            try Task.checkCancellation()
            ownedMemoryRecords = records
        } catch is CancellationError {
            return
        } catch {
            memoryManagementErrorMessage = error.localizedDescription
        }
    }

    func purgeOwnedMemory(_ record: MemoryRecord) async {
        guard let memoryRepository = beginMemoryManagementOperation() else { return }
        purgingMemoryID = record.id
        memoryManagementNoticeMessage = nil
        defer { purgingMemoryID = nil }
        do {
            let result = try await memoryRepository.purge(record)
            try Task.checkCancellation()
            ownedMemoryRecords.removeAll { $0.id == record.id }
            memoryManagementNoticeMessage = result.didPurgeAnything
                ? "기억을 기기에서 영구 삭제했습니다."
                : "이 기억은 이미 삭제되어 있었습니다."
        } catch is CancellationError {
            return
        } catch {
            memoryManagementErrorMessage = error.localizedDescription
        }
    }

    func purgeAllOwnedMemories() async {
        guard let memoryRepository = beginMemoryManagementOperation() else { return }
        isPurgingAllOwnedMemories = true
        memoryManagementNoticeMessage = nil
        defer { isPurgingAllOwnedMemories = false }
        do {
            let result = try await memoryRepository.purgeAll()
            try Task.checkCancellation()
            ownedMemoryRecords = []
            memoryManagementNoticeMessage = result.recordsPurged > 0
                ? "이 사용자의 저장된 기억 \(result.recordsPurged)개를 영구 삭제했습니다."
                : "삭제할 저장된 기억이 없었습니다."
        } catch is CancellationError {
            return
        } catch {
            memoryManagementErrorMessage = error.localizedDescription
        }
    }

    func dismissMemoryManagementError() {
        memoryManagementErrorMessage = nil
    }

    func loadAPIKey(for provider: MobileProviderKind) async throws -> String {
        try await secretStore.loadSecret(
            namespace: Self.secretNamespace,
            account: provider.keychainAccount
        ) ?? ""
    }

    func saveAPIKey(_ rawValue: String, for provider: MobileProviderKind) async throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            try await secretStore.deleteSecret(
                namespace: Self.secretNamespace,
                account: provider.keychainAccount
            )
        } else {
            try await secretStore.saveSecret(
                value,
                namespace: Self.secretNamespace,
                account: provider.keychainAccount
            )
        }
        try await reloadConfiguration()
    }

    private func preservePartialReply() {
        let partial = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partial.isEmpty {
            agentHistory.append(MobileChatMessage(
                role: .assistant,
                text: "\(partial) (중단됨)"
            ).agentMessage)
            refreshDisplayMessages()
            persistConversation()
        }
        streamingText = ""
        activeToolName = nil
    }

    private func replaceHistory(with messages: [AgentMessage]) {
        agentHistory = messages
        refreshDisplayMessages()
    }

    private func refreshDisplayMessages() {
        messages = MobileChatMessage.displayMessages(from: agentHistory)
    }

    /// Provider continuations are adapter-owned. When a user changes providers,
    /// retain the visible dialogue but remove opaque continuation and tool-turn
    /// state before the new adapter receives history.
    private func prepareHistoryForCurrentProvider() {
        let current = preferences.currentProvider.rawValue
        let currentModel = preferences.model.trimmingCharacters(in: .whitespacesAndNewlines)
        agentHistory = MobileHistoryCompatibility.sanitizedHistory(
            agentHistory,
            storedProviderID: historyProviderID,
            storedModelID: historyModelID,
            currentProviderID: current,
            currentModelID: currentModel
        )
        historyProviderID = current
        historyModelID = currentModel
        refreshDisplayMessages()
    }

    private func persistConversation() {
        let snapshot = conversationSnapshot()
        persistenceTask?.cancel()
        persistenceTask = Task { [conversationStore] in
            guard let conversationStore else { return }
            do {
                try Task.checkCancellation()
                try await conversationStore.save(snapshot)
            } catch is CancellationError {
                return
            } catch {
                // Conversation persistence must not interrupt an otherwise valid reply.
            }
        }
    }

    /// A completed runtime turn is committed in durability order: first the
    /// full provider-aware conversation snapshot, then the exact checkpoints
    /// observed during that run. If snapshot persistence fails, cleanup is
    /// never entered and the checkpoint remains available for recovery.
    private func persistCompletedConversation(checkpointIDs: Set<UUID>) async throws {
        persistenceTask?.cancel()
        await persistenceTask?.value
        persistenceTask = nil
        guard let conversationStore else { throw MobileAgentError.notInitialized }
        try await MobileCompletedRunCommitter.commit(
            snapshot: conversationSnapshot(),
            conversationStore: conversationStore,
            checkpointIDs: checkpointIDs,
            checkpointStore: checkpointStore
        )
    }

    private func conversationSnapshot() -> MobileConversationSnapshot {
        MobileConversationSnapshot(
            userID: preferences.userID,
            sessionID: preferences.sessionID,
            providerID: historyProviderID,
            modelID: historyModelID,
            messages: agentHistory
        )
    }

    private func beginMemoryManagementOperation() -> MobileOwnedMemoryRepository? {
        memoryManagementErrorMessage = nil
        guard !isRunning else {
            memoryManagementErrorMessage = MobileMemoryManagementError.agentRunning.localizedDescription
            return nil
        }
        guard !isMemoryManagementBusy else {
            memoryManagementErrorMessage = MobileMemoryManagementError.operationInProgress.localizedDescription
            return nil
        }
        guard let memoryRepository else {
            memoryManagementErrorMessage = MobileMemoryManagementError.unavailable.localizedDescription
            return nil
        }
        return memoryRepository
    }

    private static func supportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("DochiMobile", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw MobileAgentError.unsafeConversationLocation
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: directory.path
        )
        return directory
    }

    /// The device-local canonical memory folder is intentionally under the
    /// app's Documents container so users can edit it in Files. Conversations,
    /// checkpoints, and the derived SQLite index remain in Application Support.
    private static func localFileMemoryDirectory() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = documents.appendingPathComponent("Memory", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [
                .posixPermissions: NSNumber(value: Int16(0o700)),
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
            ]
        )
        return directory
    }

    private static let agentID = "도치"
}

struct MobileOwnedMemoryRepository: Sendable {
    let store: any MemoryStore
    let appID: String
    let userID: String

    func records() async throws -> [MemoryRecord] {
        try await store.recordsOwned(appID: appID, userID: userID)
    }

    func purge(_ record: MemoryRecord) async throws -> MemoryPurgeResult {
        guard owns(record.scope) else {
            throw MobileMemoryManagementError.recordNotOwned
        }
        return try await store.purge(id: record.id, scope: record.scope)
    }

    func purgeAll() async throws -> MemoryPurgeResult {
        try await store.purgeOwned(appID: appID, userID: userID)
    }

    func owns(_ scope: MemoryScope) -> Bool {
        scope.level != .application
            && scope.appID == appID
            && scope.userID == userID
    }
}

enum MobileMemoryManagementError: LocalizedError, Sendable, Equatable {
    case unavailable
    case agentRunning
    case operationInProgress
    case recordNotOwned

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "보호된 기억 저장소를 사용할 수 없습니다."
        case .agentRunning:
            "도치가 답변하는 동안에는 저장된 기억을 조회하거나 삭제할 수 없습니다. 답변이 끝난 뒤 다시 시도해 주세요."
        case .operationInProgress:
            "다른 기억 작업이 진행 중입니다. 잠시 후 다시 시도해 주세요."
        case .recordNotOwned:
            "현재 앱과 사용자에게 속하지 않은 기억은 삭제할 수 없습니다."
        }
    }
}

struct MobileCheckpointIdentity: Sendable, Hashable {
    var appID: String
    var userID: String?
    var sessionID: String
    var agentID: String
}

enum MobileCheckpointCleanup {
    static func deleteCompletedRun(
        checkpointIDs: Set<UUID>,
        from store: any AgentCheckpointStore
    ) async throws {
        // Deleting exact IDs prevents a successful later run from erasing an
        // unresolved checkpoint belonging to an earlier interrupted run in the
        // same conversation.
        for id in checkpointIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            try Task.checkCancellation()
            try await store.delete(id: id)
        }
    }

    @discardableResult
    static func deleteConversationIfSafe(
        _ identity: MobileCheckpointIdentity,
        from store: any AgentCheckpointStore
    ) async throws -> Bool {
        var removedIDs: Set<UUID> = []
        while let latest = try await store.latest(
            appID: identity.appID,
            userID: identity.userID,
            sessionID: identity.sessionID,
            agentID: identity.agentID
        ) {
            try Task.checkCancellation()
            guard !latest.toolExecutions.contains(where: {
                $0.sideEffect == .nonIdempotent && $0.state != .completed
            }) else {
                return false
            }
            // Remove only the exact checkpoint just inspected. Querying again
            // then reveals the next older checkpoint, so an unresolved ledger
            // can never be hidden behind a newer, safe checkpoint.
            guard removedIDs.insert(latest.id).inserted else { return false }
            try await store.delete(id: latest.id)
        }
        return true
    }
}

enum MobileCompletedRunCommitter {
    static func commit(
        snapshot: MobileConversationSnapshot,
        conversationStore: any MobileConversationStoring,
        checkpointIDs: Set<UUID>,
        checkpointStore: (any AgentCheckpointStore)?
    ) async throws {
        try Task.checkCancellation()
        try await conversationStore.save(snapshot)
        try Task.checkCancellation()
        guard !checkpointIDs.isEmpty, let checkpointStore else { return }
        // Cleanup failure is recoverable because the durable snapshot already
        // exists. Keep the checkpoint rather than turning a valid answer into
        // an apparent send failure; a later cleanup can safely retry exact IDs.
        try? await MobileCheckpointCleanup.deleteCompletedRun(
            checkpointIDs: checkpointIDs,
            from: checkpointStore
        )
    }
}

private struct MobileMemoryApprovalHandler: MemoryApprovalHandler, Sendable {
    let broker: AgentToolApprovalBroker

    func requestApproval(_ request: MemoryApprovalRequest) async -> MemoryApprovalDecision {
        let proposal = request.proposal
        let toolRequest = AgentToolApprovalRequest(
            call: AgentToolCall(
                id: request.id.uuidString,
                name: "memory.persist_sensitive",
                arguments: .object([
                    "scope": .string(proposal.scope.level.rawValue),
                    "kind": .string(proposal.kind.rawValue),
                    "sensitivity": .string(proposal.sensitivity.rawValue),
                    // Kept only in the in-memory local approval request so the
                    // user can see exactly what would be stored.
                    "content": .string(proposal.content),
                ])
            ),
            descriptor: AgentToolDescriptor(
                name: "memory.persist_sensitive",
                description: "민감한 기억을 장기 저장합니다. 실제 내용은 로컬 승인 UI에서만 표시하고 감사 로그에는 남기지 않습니다.",
                inputSchema: .object(["type": .string("object")]),
                risk: .sensitive,
                sideEffect: .idempotent
            ),
            reason: request.reason,
            context: AgentToolExecutionContext(
                runID: UUID(uuidString: proposal.provenance.sourceID ?? "") ?? UUID(),
                sessionID: proposal.provenance.metadata["sessionID"]?.stringValue
                    ?? proposal.scope.sessionID
                    ?? "memory",
                appID: proposal.scope.appID,
                userID: proposal.scope.userID,
                agentID: proposal.scope.agentID ?? proposal.provenance.actorID ?? "도치"
            )
        )
        switch await broker.requestApproval(toolRequest) {
        case .allowOnce, .allowForSession:
            return .approve
        case .deny(let reason):
            return .deny(reason: reason)
        }
    }
}
