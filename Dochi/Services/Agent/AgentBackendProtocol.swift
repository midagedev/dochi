import Foundation

/// Product-facing event contract shared by local and remote agent backends.
enum DochiAgentEvent: Sendable {
    case delta(String)
    case toolStarted(name: String, summary: String?)
    case toolFinished(name: String, isError: Bool, summary: String?)
    case done(text: String, messageId: String?)
}

enum AgentBackendConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected(name: String?)
    case failed(String)
}

/// Minimal, provider-neutral history used to resume a persisted Dochi
/// conversation in an in-process backend. Remote backends such as Hermes own
/// their history server-side and may ignore these callbacks.
struct DochiAgentHistoryMessage: Sendable, Equatable {
    enum Role: Sendable, Equatable {
        case user
        case assistant
    }

    var role: Role
    var text: String
}

/// Headless backend seam consumed by Dochi's voice and avatar orchestrator.
///
/// Hermes and the native AgentRuntimeKit implementation both conform to this
/// contract. Provider, tool, and memory details do not leak into the UI layer.
@MainActor
protocol AgentBackendProtocol: AnyObject {
    var connectionState: AgentBackendConnectionState { get }
    var onProactiveMessage: (@MainActor (String) -> Void)? { get set }
    var onConnectionStateChanged: (@MainActor (AgentBackendConnectionState) -> Void)? { get set }

    func connect()
    func disconnect()
    func reconfigure(host: String, port: Int)
    func replaceConversationHistory(
        _ history: [DochiAgentHistoryMessage],
        conversationId: String,
        user: String?
    )
    func removeConversationHistory(conversationId: String, user: String?)
    func send(
        text: String,
        conversationId: String,
        user: String?
    ) -> AsyncThrowingStream<DochiAgentEvent, Error>
}

extension AgentBackendProtocol {
    func replaceConversationHistory(
        _ history: [DochiAgentHistoryMessage],
        conversationId: String,
        user: String?
    ) {}

    func removeConversationHistory(conversationId: String, user: String?) {}
}
