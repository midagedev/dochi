import Foundation

final class NativeAgentLoopService {
    private let adapters: [LLMProvider: any NativeLLMProviderAdapter]

    init(adapters: [any NativeLLMProviderAdapter]) {
        var map: [LLMProvider: any NativeLLMProviderAdapter] = [:]
        for adapter in adapters {
            map[adapter.provider] = adapter
        }
        self.adapters = map
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
        return adapter.stream(request: request)
    }
}
