import Foundation

/// Switches between in-process Swift execution and the optional Hermes bridge
/// without changing the voice/avatar view model.
@MainActor
@Observable
final class AgentBackendRouter: AgentBackendProtocol {
    private(set) var connectionState: AgentBackendConnectionState = .disconnected {
        didSet {
            if oldValue != connectionState {
                onConnectionStateChanged?(connectionState)
            }
        }
    }

    @ObservationIgnored var onProactiveMessage: (@MainActor (String) -> Void)?
    @ObservationIgnored var onConnectionStateChanged: (@MainActor (AgentBackendConnectionState) -> Void)?

    private let native: AgentBackendProtocol
    private let hermes: AgentBackendProtocol
    private(set) var selectedKind: AgentBackendKind

    init(
        selectedKind: AgentBackendKind,
        native: AgentBackendProtocol,
        hermes: AgentBackendProtocol
    ) {
        self.selectedKind = selectedKind
        self.native = native
        self.hermes = hermes
        bindCurrent()
    }

    func select(_ kind: AgentBackendKind) {
        guard kind != selectedKind else { return }
        current.disconnect()
        selectedKind = kind
        bindCurrent()
        current.connect()
    }

    func connect() {
        bindCurrent()
        current.connect()
        connectionState = current.connectionState
    }

    func disconnect() {
        current.disconnect()
        connectionState = current.connectionState
    }

    func reconfigure(host: String, port: Int) {
        // `reconfigure` is the product-level "apply current settings" action.
        // Native ignores host/port and reloads provider + memory configuration;
        // Hermes applies the endpoint and reconnects.
        current.reconfigure(host: host, port: port)
        connectionState = current.connectionState
    }

    func replaceConversationHistory(
        _ history: [DochiAgentHistoryMessage],
        conversationId: String,
        user: String?
    ) {
        current.replaceConversationHistory(
            history,
            conversationId: conversationId,
            user: user
        )
    }

    func removeConversationHistory(conversationId: String, user: String?) {
        native.removeConversationHistory(conversationId: conversationId, user: user)
        hermes.removeConversationHistory(conversationId: conversationId, user: user)
    }

    func send(
        text: String,
        conversationId: String,
        user: String?
    ) -> AsyncThrowingStream<DochiAgentEvent, Error> {
        current.send(text: text, conversationId: conversationId, user: user)
    }

    private var current: AgentBackendProtocol {
        switch selectedKind {
        case .native: native
        case .hermesRemote: hermes
        }
    }

    private func bindCurrent() {
        native.onConnectionStateChanged = nil
        native.onProactiveMessage = nil
        hermes.onConnectionStateChanged = nil
        hermes.onProactiveMessage = nil

        current.onConnectionStateChanged = { [weak self] state in
            self?.connectionState = state
        }
        current.onProactiveMessage = { [weak self] message in
            self?.onProactiveMessage?(message)
        }
        connectionState = current.connectionState
    }
}
