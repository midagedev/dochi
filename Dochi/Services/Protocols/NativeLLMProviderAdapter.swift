import Foundation

protocol NativeLLMProviderAdapter: Sendable {
    var provider: LLMProvider { get }

    func stream(request: NativeLLMRequest) -> AsyncThrowingStream<NativeLLMStreamEvent, Error>
}
