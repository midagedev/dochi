import XCTest
@testable import Dochi

final class RuntimeBridgeTests: XCTestCase {

    // MARK: - Exponential Backoff

    @MainActor
    func testBackoffDelayCalculation() {
        let service = RuntimeBridgeService()

        // 2^0 = 1
        XCTAssertEqual(service.backoffDelay(attempt: 0), 1.0)
        // 2^1 = 2
        XCTAssertEqual(service.backoffDelay(attempt: 1), 2.0)
        // 2^2 = 4
        XCTAssertEqual(service.backoffDelay(attempt: 2), 4.0)
        // 2^3 = 8
        XCTAssertEqual(service.backoffDelay(attempt: 3), 8.0)
        // 2^4 = 16
        XCTAssertEqual(service.backoffDelay(attempt: 4), 16.0)
        // 2^5 = 32 → capped at 30
        XCTAssertEqual(service.backoffDelay(attempt: 5), 30.0)
        // 2^10 = 1024 → capped at 30
        XCTAssertEqual(service.backoffDelay(attempt: 10), 30.0)
    }

    // MARK: - Initial State

    @MainActor
    func testInitialState() {
        let service = RuntimeBridgeService()
        XCTAssertEqual(service.runtimeState, .notStarted)
    }

    // MARK: - Mock RuntimeBridge

    @MainActor
    func testMockRuntimeBridgeStartStop() async throws {
        let mock = MockRuntimeBridgeService()
        XCTAssertEqual(mock.runtimeState, .notStarted)

        try await mock.startRuntime()
        XCTAssertEqual(mock.runtimeState, .ready)
        XCTAssertEqual(mock.startCallCount, 1)

        await mock.stopRuntime()
        XCTAssertEqual(mock.runtimeState, .notStarted)
        XCTAssertEqual(mock.stopCallCount, 1)
    }

    @MainActor
    func testMockRuntimeBridgeHealth() async throws {
        let mock = MockRuntimeBridgeService()
        try await mock.startRuntime()

        let health = try await mock.health()
        XCTAssertTrue(health.alive)
        XCTAssertEqual(health.activeSessions, 0)
        XCTAssertNil(health.lastError)
        XCTAssertEqual(mock.healthCallCount, 1)
    }

    @MainActor
    func testMockRuntimeBridgeHealthError() async {
        let mock = MockRuntimeBridgeService()
        mock.stubbedError = RuntimeBridgeError.notConnected

        do {
            _ = try await mock.health()
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is RuntimeBridgeError)
        }
    }

    @MainActor
    func testMockRuntimeBridgeCustomHealth() async throws {
        let mock = MockRuntimeBridgeService()
        mock.stubbedHealthResponse = RuntimeHealthResponse(
            alive: true, uptimeMs: 99999, activeSessions: 3, lastError: "test error"
        )

        let health = try await mock.health()
        XCTAssertEqual(health.uptimeMs, 99999)
        XCTAssertEqual(health.activeSessions, 3)
        XCTAssertEqual(health.lastError, "test error")
    }

    // MARK: - RuntimeBridgeError

    func testErrorDescriptions() {
        let errors: [(RuntimeBridgeError, String)] = [
            (.launchFailed("test"), "Runtime launch failed: test"),
            (.readyTimeout, "Runtime did not emit ready event within timeout"),
            (.connectionFailed("test"), "UDS connection failed: test"),
            (.notConnected, "Not connected to runtime"),
            (.connectionClosed, "Connection to runtime was closed"),
            (.rpcError(code: -32601, message: "Method not found"), "RPC error -32601: Method not found"),
            (.invalidResponse, "Invalid response from runtime"),
        ]

        for (error, expected) in errors {
            XCTAssertEqual(error.errorDescription, expected)
        }
    }
}
