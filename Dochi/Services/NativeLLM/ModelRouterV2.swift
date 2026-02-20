import Foundation

enum ModelRoutingChannel: String, Sendable {
    case chat
    case voice
    case telegram

    var prefersLowLatency: Bool {
        self == .voice
    }
}

struct ModelRoutingInput: Sendable {
    let userInput: String
    let channel: ModelRoutingChannel
    let includesImages: Bool

    init(userInput: String, channel: ModelRoutingChannel, includesImages: Bool) {
        self.userInput = userInput
        self.channel = channel
        self.includesImages = includesImages
    }
}

enum ModelRouteSource: String, Sendable {
    case realtimeLocalPreference
    case taskComplexity
    case primary
    case configuredFallback
    case offlineFallback
}

struct ModelRouteTarget: Sendable, Equatable {
    let provider: LLMProvider
    let model: String
    let source: ModelRouteSource
}

enum ModelRouteCandidateStatus: String, Sendable {
    case selected
    case ready
    case skippedUnsupportedProvider
    case skippedCircuitOpen
    case skippedVisionUnsupported
    case skippedProviderUnhealthy
}

struct ModelRouteCandidateEvaluation: Sendable, Equatable {
    let target: ModelRouteTarget
    let status: ModelRouteCandidateStatus
    let reason: String
}

struct ModelRoutingDecision: Sendable {
    let complexity: TaskComplexity
    let orderedReadyTargets: [ModelRouteTarget]
    let evaluations: [ModelRouteCandidateEvaluation]

    var selectedTarget: ModelRouteTarget? {
        orderedReadyTargets.first
    }

    var summary: String {
        let selectedLabel: String
        if let selectedTarget {
            selectedLabel = "\(selectedTarget.provider.rawValue)/\(selectedTarget.model) [\(selectedTarget.source.rawValue)]"
        } else {
            selectedLabel = "none"
        }

        let skippedCount = evaluations.filter {
            $0.status != .selected && $0.status != .ready
        }.count

        return "complexity=\(complexity.rawValue), selected=\(selectedLabel), candidates=\(evaluations.count), skipped=\(skippedCount)"
    }
}

@MainActor
final class ModelRouterV2 {
    struct CircuitBreakerPolicy: Sendable {
        let failureThreshold: Int
        let openDuration: TimeInterval

        init(failureThreshold: Int = 2, openDuration: TimeInterval = 30) {
            self.failureThreshold = max(1, failureThreshold)
            self.openDuration = max(1, openDuration)
        }

        static let `default` = CircuitBreakerPolicy()
    }

    private struct ProviderCircuitState: Sendable {
        var consecutiveFailures: Int = 0
        var openUntil: Date?
    }

    private let settings: AppSettings
    private let readinessProbe: (LLMProvider) async -> Bool
    private let supportsProvider: (LLMProvider) -> Bool
    private let circuitPolicy: CircuitBreakerPolicy
    private var circuits: [LLMProvider: ProviderCircuitState] = [:]

    init(
        settings: AppSettings,
        readinessProbe: @escaping (LLMProvider) async -> Bool,
        supportsProvider: @escaping (LLMProvider) -> Bool,
        circuitPolicy: CircuitBreakerPolicy = .default
    ) {
        self.settings = settings
        self.readinessProbe = readinessProbe
        self.supportsProvider = supportsProvider
        self.circuitPolicy = circuitPolicy
    }

    func decide(input: ModelRoutingInput, now: Date = Date()) async -> ModelRoutingDecision {
        let complexity = TaskComplexityClassifier.classify(input.userInput)
        let candidates = candidateChain(complexity: complexity, channel: input.channel)

        var readyTargets: [ModelRouteTarget] = []
        var evaluations: [ModelRouteCandidateEvaluation] = []

        for candidate in candidates {
            guard supportsProvider(candidate.provider) else {
                evaluations.append(ModelRouteCandidateEvaluation(
                    target: candidate,
                    status: .skippedUnsupportedProvider,
                    reason: "native_adapter_unavailable"
                ))
                continue
            }

            if isCircuitOpen(for: candidate.provider, now: now) {
                evaluations.append(ModelRouteCandidateEvaluation(
                    target: candidate,
                    status: .skippedCircuitOpen,
                    reason: "circuit_open"
                ))
                continue
            }

            if input.includesImages {
                let capabilities = ProviderCapabilityMatrix.capabilities(
                    for: candidate.provider,
                    model: candidate.model
                )
                if !capabilities.supportsVision {
                    evaluations.append(ModelRouteCandidateEvaluation(
                        target: candidate,
                        status: .skippedVisionUnsupported,
                        reason: "vision_unsupported"
                    ))
                    continue
                }
            }

            let ready = await readinessProbe(candidate.provider)
            guard ready else {
                evaluations.append(ModelRouteCandidateEvaluation(
                    target: candidate,
                    status: .skippedProviderUnhealthy,
                    reason: "provider_unhealthy_or_not_ready"
                ))
                continue
            }

            readyTargets.append(candidate)
            evaluations.append(ModelRouteCandidateEvaluation(
                target: candidate,
                status: readyTargets.count == 1 ? .selected : .ready,
                reason: readyTargets.count == 1 ? "selected_first_ready_candidate" : "ready_candidate"
            ))
        }

        return ModelRoutingDecision(
            complexity: complexity,
            orderedReadyTargets: readyTargets,
            evaluations: evaluations
        )
    }

    func recordAttempt(provider: LLMProvider, success: Bool, now: Date = Date()) {
        var state = circuits[provider] ?? ProviderCircuitState()

        if success {
            state.consecutiveFailures = 0
            state.openUntil = nil
            circuits[provider] = state
            return
        }

        if let openUntil = state.openUntil, openUntil > now {
            circuits[provider] = state
            return
        }

        state.consecutiveFailures += 1
        if state.consecutiveFailures >= circuitPolicy.failureThreshold {
            state.consecutiveFailures = 0
            state.openUntil = now.addingTimeInterval(circuitPolicy.openDuration)
        }
        circuits[provider] = state
    }

    func isCircuitOpen(for provider: LLMProvider, now: Date = Date()) -> Bool {
        guard var state = circuits[provider], let openUntil = state.openUntil else {
            return false
        }

        if openUntil <= now {
            state.openUntil = nil
            state.consecutiveFailures = 0
            circuits[provider] = state
            return false
        }

        return true
    }
}

private extension ModelRouterV2 {
    func candidateChain(complexity: TaskComplexity, channel: ModelRoutingChannel) -> [ModelRouteTarget] {
        var candidates: [ModelRouteTarget] = []

        if channel.prefersLowLatency,
           let realtimePreferred = realtimePreferredLocalTarget() {
            candidates.append(realtimePreferred)
        }

        if settings.taskRoutingEnabled,
           let complexityTarget = complexityTarget(for: complexity) {
            candidates.append(complexityTarget)
        }

        if let primaryTarget = makeTarget(
            provider: settings.currentProvider,
            model: settings.llmModel,
            source: .primary
        ) {
            candidates.append(primaryTarget)
        }

        if let fallbackTarget = configuredTarget(
            providerRaw: settings.fallbackLLMProvider,
            modelRaw: settings.fallbackLLMModel,
            source: .configuredFallback
        ) {
            candidates.append(fallbackTarget)
        }

        if settings.offlineFallbackEnabled,
           let offlineTarget = configuredTarget(
               providerRaw: settings.offlineFallbackProvider,
               modelRaw: settings.offlineFallbackModel,
               source: .offlineFallback
           ) {
            candidates.append(offlineTarget)
        }

        return deduplicated(candidates)
    }

    func realtimePreferredLocalTarget() -> ModelRouteTarget? {
        if settings.offlineFallbackEnabled,
           let offlineTarget = configuredTarget(
               providerRaw: settings.offlineFallbackProvider,
               modelRaw: settings.offlineFallbackModel,
               source: .realtimeLocalPreference
           ),
           offlineTarget.provider.isLocal {
            return offlineTarget
        }

        if settings.currentProvider.isLocal,
           let primaryLocal = makeTarget(
               provider: settings.currentProvider,
               model: settings.llmModel,
               source: .realtimeLocalPreference
           ) {
            return primaryLocal
        }

        if let fallback = configuredTarget(
            providerRaw: settings.fallbackLLMProvider,
            modelRaw: settings.fallbackLLMModel,
            source: .realtimeLocalPreference
        ), fallback.provider.isLocal {
            return fallback
        }

        return nil
    }

    func complexityTarget(for complexity: TaskComplexity) -> ModelRouteTarget? {
        switch complexity {
        case .light:
            return configuredTarget(
                providerRaw: settings.lightModelProvider,
                modelRaw: settings.lightModelName,
                source: .taskComplexity
            )
        case .heavy:
            return configuredTarget(
                providerRaw: settings.heavyModelProvider,
                modelRaw: settings.heavyModelName,
                source: .taskComplexity
            )
        case .standard:
            return nil
        }
    }

    func configuredTarget(
        providerRaw: String,
        modelRaw: String,
        source: ModelRouteSource
    ) -> ModelRouteTarget? {
        let providerName = providerRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !providerName.isEmpty,
              let provider = LLMProvider(rawValue: providerName) else {
            return nil
        }

        return makeTarget(provider: provider, model: modelRaw, source: source)
    }

    func makeTarget(provider: LLMProvider, model: String, source: ModelRouteSource) -> ModelRouteTarget? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = trimmed.isEmpty ? provider.onboardingDefaultModel : trimmed
        guard !resolvedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return ModelRouteTarget(
            provider: provider,
            model: resolvedModel,
            source: source
        )
    }

    func deduplicated(_ targets: [ModelRouteTarget]) -> [ModelRouteTarget] {
        var seen: Set<String> = []
        var result: [ModelRouteTarget] = []

        for target in targets {
            let key = "\(target.provider.rawValue)|\(target.model.lowercased())"
            if seen.insert(key).inserted {
                result.append(target)
            }
        }

        return result
    }
}
