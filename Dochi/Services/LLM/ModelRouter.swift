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

    /// Resolve the primary model from current settings.
    func resolvePrimary() -> ResolvedModel? {
        let provider = settings.currentProvider
        let model = settings.llmModel
        guard let apiKey = keychainService.load(account: provider.keychainAccount),
              !apiKey.isEmpty else {
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

        guard let apiKey = keychainService.load(account: fallbackProvider.keychainAccount),
              !apiKey.isEmpty else {
            return nil
        }

        return ResolvedModel(provider: fallbackProvider, model: fallbackModel, apiKey: apiKey, isFallback: true)
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
