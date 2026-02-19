import Foundation

/// Protocol for managing the agent runtime sidecar process.
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
}
