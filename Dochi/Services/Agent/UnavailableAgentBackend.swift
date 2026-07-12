import Foundation

@MainActor
final class UnavailableAgentBackend: AgentBackendProtocol {
    private let message: String
    private(set) var connectionState: AgentBackendConnectionState
    var onProactiveMessage: (@MainActor (String) -> Void)?
    var onConnectionStateChanged: (@MainActor (AgentBackendConnectionState) -> Void)?

    init(error: Error) {
        self.message = error.localizedDescription
        self.connectionState = .failed(error.localizedDescription)
    }

    func connect() {
        connectionState = .failed(message)
        onConnectionStateChanged?(connectionState)
    }

    func disconnect() {
        connectionState = .disconnected
        onConnectionStateChanged?(connectionState)
    }

    func reconfigure(host: String, port: Int) { connect() }

    func send(
        text: String,
        conversationId: String,
        user: String?
    ) -> AsyncThrowingStream<DochiAgentEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: UnavailableAgentBackendError(message: message))
        }
    }
}

struct UnavailableAgentBackendError: LocalizedError, Sendable {
    var message: String
    var errorDescription: String? { message }
}
