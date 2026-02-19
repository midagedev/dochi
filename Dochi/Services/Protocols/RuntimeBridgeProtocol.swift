import Foundation

/// Protocol for managing the agent runtime sidecar process.
///
/// `@MainActor` 근거: `runtimeState`가 SwiftUI View에서 관찰되어 런타임 상태 표시
/// (연결 중/준비됨/오류 등)에 사용되므로 UI 스레드 격리가 필요하다.
@MainActor
protocol RuntimeBridgeProtocol {
    /// Current state of the runtime process.
    var runtimeState: RuntimeState { get }

    /// Start the runtime sidecar process and establish connection.
    func startRuntime() async throws

    /// Stop the runtime sidecar process gracefully.
    func stopRuntime() async

    /// Query the runtime health status.
    func health() async throws -> RuntimeHealthResponse

    // MARK: - Tool Dispatch

    /// Configure tool dispatch with the app's built-in tool service.
    func configureToolDispatch(toolService: any BuiltInToolServiceProtocol)

    // MARK: - Session Management

    /// Open or reuse a session for the given parameters.
    func openSession(params: SessionOpenParams) async throws -> SessionOpenResult

    /// Start a session run and return a stream of bridge events.
    /// The stream yields partial text, tool calls, and completes on `session.completed` or `session.failed`.
    func runSession(params: SessionRunParams) -> AsyncThrowingStream<BridgeEvent, Error>

    /// Interrupt an active session run.
    func interruptSession(sessionId: String) async throws -> SessionInterruptResult

    /// Close a session.
    func closeSession(sessionId: String) async throws -> SessionCloseResult
}
