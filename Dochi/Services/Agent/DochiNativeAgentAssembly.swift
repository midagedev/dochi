import AgentRuntimeApple
import AgentRuntimeCore
import AgentRuntimeMemory
import AgentRuntimeProviders
import Foundation

@MainActor
enum DochiNativeAgentAssembly {
    static let appID = "com.hckim.dochi"
    static let providerSecretNamespace = appID

    static func make(
        settings: AppSettings,
        approvalBroker: AgentToolApprovalBroker,
        secretStore: any AgentSecretStore = KeychainAgentSecretStore()
    ) throws -> NativeAgentBackend {
        let supportDirectory = try applicationSupportDirectory()
        let memoryStore = try ProtectedSQLiteMemoryStore(configuration: .init(
            databaseURL: supportDirectory.appendingPathComponent("agent-memory.sqlite")
        ))
        let memoryApproval = DochiMemoryApprovalHandler(broker: approvalBroker)
        let memoryBundle = MemoryToolFactory.make(
            store: memoryStore,
            approvalHandler: memoryApproval
        )
        let toolRegistry = try AgentToolRegistry(tools: [CurrentTimeAgentTool()])
        let providerRegistry = ModelProviderRegistry()
        let checkpointStore = ProtectedFileAgentCheckpointStore(configuration: .init(
            directory: supportDirectory.appendingPathComponent("checkpoints", isDirectory: true)
        ))
        let auditSink = RedactedJSONLAgentAuditSink(configuration: .init(
            fileURL: supportDirectory.appendingPathComponent("agent-audit.jsonl")
        ))
        let runtime = AgentRuntime(
            providers: providerRegistry,
            tools: toolRegistry,
            toolPolicy: DefaultAgentToolPolicy(
                preapprovedSensitiveTools: ["memory.save", "memory.search"]
            ),
            approvalHandler: approvalBroker,
            checkpointStore: checkpointStore,
            auditSink: auditSink
        )

        let credentialResolver = ProviderCredentialResolver(
            secretStore: secretStore,
            namespace: providerSecretNamespace,
            accounts: Dictionary(uniqueKeysWithValues: NativeModelProviderKind.allCases.map {
                ($0.rawValue, $0.keychainAccount)
            })
        )
        let memoryContext = MemoryContextProvider(store: memoryStore)
        let fileMemoryController = DochiFileMemoryController(
            appID: appID,
            store: memoryStore,
            localRootURL: supportDirectory.appendingPathComponent("FileMemory", isDirectory: true),
            preferencesProvider: {
                DochiFileMemoryPreferences(
                    memoryEnabled: settings.nativeMemoryEnabled,
                    fileMemoryEnabled: settings.nativeFileMemoryEnabled,
                    location: settings.currentNativeFileMemoryLocation
                )
            }
        )

        return NativeAgentBackend(
            runtime: runtime,
            appID: appID,
            checkpointStore: checkpointStore,
            definitionProvider: {
                AgentDefinition(
                    id: "도치 네이티브",
                    providerID: settings.currentNativeProviderKind.rawValue,
                    model: settings.nativeModel.trimmingCharacters(in: .whitespacesAndNewlines),
                    instructions: settings.nativeAgentInstructions,
                    maximumContextSensitivity: .privateData,
                    maxOutputTokens: 4_096
                )
            },
            configurationReloader: {
                await fileMemoryController.synchronize()
                try await configureMemoryRegistration(
                    shouldEnable: settings.nativeMemoryEnabled
                        && fileMemoryController.allowsMemoryAccess,
                    runtime: runtime,
                    context: memoryContext,
                    bundle: memoryBundle,
                    registry: toolRegistry
                )
                try await registerProviders(
                    settings: settings,
                    registry: providerRegistry,
                    secretStore: secretStore,
                    credentialResolver: credentialResolver
                )
            },
            preRunHook: {
                await fileMemoryController.synchronize()
                do {
                    try await configureMemoryRegistration(
                        shouldEnable: settings.nativeMemoryEnabled
                            && fileMemoryController.allowsMemoryAccess,
                        runtime: runtime,
                        context: memoryContext,
                        bundle: memoryBundle,
                        registry: toolRegistry
                    )
                } catch {
                    Log.runtime.error(
                        "Failed to apply native memory access gate: \(error.localizedDescription, privacy: .public)"
                    )
                }
            },
            fileMemoryController: fileMemoryController
        )
    }

    private static func configureMemoryRegistration(
        shouldEnable: Bool,
        runtime: AgentRuntime,
        context: MemoryContextProvider,
        bundle: MemoryToolBundle,
        registry: AgentToolRegistry
    ) async throws {
        guard shouldEnable else {
            await removeMemoryRegistration(
                runtime: runtime,
                context: context,
                registry: registry
            )
            return
        }

        do {
            for tool in bundle.tools {
                try await registry.replace(tool)
            }
            await runtime.contexts.register(context)
        } catch {
            await removeMemoryRegistration(
                runtime: runtime,
                context: context,
                registry: registry
            )
            throw error
        }
    }

    private static func removeMemoryRegistration(
        runtime: AgentRuntime,
        context: MemoryContextProvider,
        registry: AgentToolRegistry
    ) async {
        await runtime.contexts.remove(identifier: context.identifier)
        for name in ["memory.save", "memory.search", "memory.archive"] {
            await registry.remove(named: name)
        }
    }

    private static func registerProviders(
        settings: AppSettings,
        registry: ModelProviderRegistry,
        secretStore: any AgentSecretStore,
        credentialResolver: ProviderCredentialResolver
    ) async throws {
        guard !settings.nativeModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DochiNativeAgentAssemblyError.missingModel(
                settings.currentNativeProviderKind.displayName
            )
        }

        await registry.register(AnthropicMessagesProvider(
            identifier: NativeModelProviderKind.anthropic.rawValue,
            credentialResolver: credentialResolver
        ))
        await registry.register(OpenAIResponsesProvider(
            identifier: NativeModelProviderKind.openAI.rawValue,
            credentialResolver: credentialResolver
        ))
        await registry.register(GeminiGenerateContentProvider(
            identifier: NativeModelProviderKind.gemini.rawValue,
            credentialResolver: credentialResolver
        ))

        let selectedProvider = settings.currentNativeProviderKind
        if selectedProvider != .openAICompatible {
            do {
                _ = try await credentialResolver.credential(for: selectedProvider.rawValue)
            } catch is ProviderCredentialError {
                throw DochiNativeAgentAssemblyError.missingProviderCredential(
                    selectedProvider.displayName
                )
            }
        }

        guard selectedProvider == .openAICompatible else {
            await registry.remove(identifier: NativeModelProviderKind.openAICompatible.rawValue)
            return
        }
        let endpoint: URL
        do {
            endpoint = try DochiCompatibleEndpoint.chatCompletionsEndpoint(
                from: settings.nativeCompatibleBaseURL
            )
        } catch {
            await registry.remove(identifier: NativeModelProviderKind.openAICompatible.rawValue)
            throw DochiNativeAgentAssemblyError.invalidCompatibleBaseURL
        }

        let storedCompatibleKey = try await secretStore.loadSecret(
            namespace: providerSecretNamespace,
            account: NativeModelProviderKind.openAICompatible.keychainAccount
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let compatibleCredential: (any ProviderCredentialResolving)? =
            storedCompatibleKey?.isEmpty == false ? credentialResolver : nil
        await registry.register(OpenAIChatCompletionsProvider(
            identifier: NativeModelProviderKind.openAICompatible.rawValue,
            endpoint: endpoint,
            credentialResolver: compatibleCredential,
            maxOutputTokensParameter: "max_tokens"
        ))
    }

    private static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("Dochi/AgentRuntime", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    nonisolated static func approvalSessionID(
        provenanceSessionID: String?,
        scopedSessionID: String?
    ) -> String {
        for candidate in [provenanceSessionID, scopedSessionID] {
            let normalized = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let normalized, !normalized.isEmpty { return normalized }
        }
        return "memory"
    }
}

enum DochiCompatibleEndpoint {
    static func validatedBaseURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw DochiNativeAgentAssemblyError.invalidCompatibleBaseURL
        }
        guard scheme == "https" || (scheme == "http" && isLoopback(host)) else {
            throw DochiNativeAgentAssemblyError.invalidCompatibleBaseURL
        }
        components.scheme = scheme
        guard let url = components.url else {
            throw DochiNativeAgentAssemblyError.invalidCompatibleBaseURL
        }
        return url
    }

    static func chatCompletionsEndpoint(from rawValue: String) throws -> URL {
        let baseURL = try validatedBaseURL(from: rawValue)
        let components = baseURL.pathComponents.filter { $0 != "/" }
        if components.suffix(2) == ["chat", "completions"] { return baseURL }
        if components.isEmpty {
            return baseURL
                .appendingPathComponent("v1", isDirectory: true)
                .appendingPathComponent("chat", isDirectory: true)
                .appendingPathComponent("completions", isDirectory: false)
        }
        return baseURL
            .appendingPathComponent("chat", isDirectory: true)
            .appendingPathComponent("completions", isDirectory: false)
    }

    static func isLoopback(_ host: String) -> Bool {
        let normalized = host
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if normalized == "localhost" || normalized.hasSuffix(".localhost") || normalized == "::1" {
            return true
        }
        let octets = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4,
              octets.first == "127",
              octets.allSatisfy({ part in
                  guard let value = Int(part) else { return false }
                  return (0...255).contains(value)
              }) else {
            return false
        }
        return true
    }
}

private struct CurrentTimeAgentTool: AgentTool, Sendable {
    let descriptor = AgentToolDescriptor(
        name: "current_time",
        description: "Return the user's current local date, time, time zone, and ISO-8601 timestamp.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
            "additionalProperties": .bool(false),
        ])
    )

    func execute(
        arguments: JSONValue,
        context: AgentToolExecutionContext
    ) async throws -> AgentToolOutput {
        let now = Date()
        return AgentToolOutput(
            content: .object([
                "localized": .string(now.formatted(date: .complete, time: .standard)),
                "iso8601": .string(ISO8601DateFormatter().string(from: now)),
                "time_zone": .string(TimeZone.current.identifier),
            ]),
            summary: "현재 시각을 확인했습니다."
        )
    }
}

private struct DochiMemoryApprovalHandler: MemoryApprovalHandler, Sendable {
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
                    "content": .string(proposal.content),
                ])
            ),
            descriptor: AgentToolDescriptor(
                name: "memory.persist_sensitive",
                description: "민감한 장기 기억을 저장합니다. 내용은 로컬 승인 UI에만 표시하고 감사 로그에는 기록하지 않습니다.",
                inputSchema: .object(["type": .string("object")]),
                risk: .sensitive,
                sideEffect: .idempotent
            ),
            reason: request.reason,
            context: AgentToolExecutionContext(
                runID: UUID(uuidString: proposal.provenance.sourceID ?? "") ?? UUID(),
                sessionID: DochiNativeAgentAssembly.approvalSessionID(
                    provenanceSessionID: proposal.provenance.metadata["sessionID"]?.stringValue,
                    scopedSessionID: proposal.scope.sessionID
                ),
                appID: proposal.scope.appID,
                userID: proposal.scope.userID,
                agentID: proposal.scope.agentID ?? "dochi-native"
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

enum DochiNativeAgentAssemblyError: LocalizedError {
    case invalidCompatibleBaseURL
    case missingProviderCredential(String)
    case missingModel(String)

    var errorDescription: String? {
        switch self {
        case .invalidCompatibleBaseURL:
            "OpenAI 호환 Base URL은 HTTPS 주소여야 합니다. HTTP는 localhost에서만 허용됩니다."
        case .missingProviderCredential(let provider):
            "\(provider) API 키를 Keychain에 저장한 뒤 설정을 적용해주세요."
        case .missingModel(let provider):
            "\(provider)에서 사용할 모델 이름을 입력한 뒤 설정을 적용해주세요."
        }
    }
}
