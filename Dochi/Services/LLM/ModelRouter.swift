import Foundation
import os

/// Resolved model configuration for an LLM request.
struct ResolvedModel: Sendable {
    let provider: LLMProvider
    let model: String
    let apiKey: String
    let isFallback: Bool
}

/// Resolves which model/provider to use and provides fallback on failure.
@MainActor
struct ModelRouter {
    private let settings: AppSettings
    private let keychainService: KeychainServiceProtocol

    init(settings: AppSettings, keychainService: KeychainServiceProtocol) {
        self.settings = settings
        self.keychainService = keychainService
    }

    /// Resolve the primary model from current settings, optionally overridden by agent config.
    func resolvePrimary(agentConfig: AgentConfig? = nil) -> ResolvedModel? {
        // Check agent-level model override
        if let agentModel = agentConfig?.defaultModel, !agentModel.isEmpty,
           let agentProvider = LLMProvider.provider(forModel: agentModel) {
            if let apiKey = resolveAPIKey(for: agentProvider) {
                Log.llm.info("Using agent model: \(agentProvider.displayName)/\(agentModel)")
                return ResolvedModel(provider: agentProvider, model: agentModel, apiKey: apiKey, isFallback: false)
            }
            Log.llm.warning("Agent model \(agentModel) configured but no API key for \(agentProvider.displayName), falling back to app settings")
        }

        // Fall back to app-level settings
        let provider = settings.currentProvider
        let model = settings.llmModel
        guard let apiKey = resolveAPIKey(for: provider) else {
            return nil
        }
        return ResolvedModel(provider: provider, model: model, apiKey: apiKey, isFallback: false)
    }

    /// Resolve the fallback model, if configured and different from primary.
    func resolveFallback() -> ResolvedModel? {
        let fallbackProviderRaw = settings.fallbackLLMProvider
        let fallbackModel = settings.fallbackLLMModel

        guard !fallbackProviderRaw.isEmpty, !fallbackModel.isEmpty,
              let fallbackProvider = LLMProvider(rawValue: fallbackProviderRaw) else {
            return nil
        }

        // Don't fallback to the exact same model
        if fallbackProvider == settings.currentProvider && fallbackModel == settings.llmModel {
            return nil
        }

        guard let apiKey = resolveAPIKey(for: fallbackProvider) else {
            return nil
        }

        return ResolvedModel(provider: fallbackProvider, model: fallbackModel, apiKey: apiKey, isFallback: true)
    }

    /// Resolve API key for a provider. Returns empty string for providers that don't require one.
    private func resolveAPIKey(for provider: LLMProvider) -> String? {
        if !provider.requiresAPIKey {
            // Provider like Ollama doesn't need an API key
            return keychainService.load(account: provider.keychainAccount) ?? ""
        }
        guard let apiKey = keychainService.load(account: provider.keychainAccount),
              !apiKey.isEmpty else {
            return nil
        }
        return apiKey
    }

    /// Whether a given error should trigger fallback to an alternate model.
    static func shouldFallback(for error: Error) -> Bool {
        guard let llmError = error as? LLMError else { return false }
        switch llmError {
        case .serverError, .timeout, .networkError, .emptyResponse, .rateLimited:
            return true
        case .modelNotFound:
            return true
        case .noAPIKey, .authenticationFailed, .cancelled, .invalidResponse:
            return false
        }
    }
}
