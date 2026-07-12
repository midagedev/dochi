import XCTest
@testable import Dochi

@MainActor
final class HermesAgentBridgeTests: XCTestCase {
    func testLoopbackBareHostUsesPlainWebSocket() throws {
        let ipv4 = try HermesBridgeEndpoint(host: "127.42.1.9", port: 8765)
        let localhost = try HermesBridgeEndpoint(host: "localhost", port: 9000)
        let ipv6 = try HermesBridgeEndpoint(host: "[::1]", port: 8765)

        XCTAssertEqual(ipv4.url.absoluteString, "ws://127.42.1.9:8765")
        XCTAssertEqual(localhost.url.absoluteString, "ws://localhost:9000")
        XCTAssertEqual(ipv6.url.scheme, "ws")
        XCTAssertEqual(ipv6.url.host, "::1")
    }

    func testRemoteBareHostDefaultsToTLS() throws {
        let endpoint = try HermesBridgeEndpoint(host: "hermes.example.com", port: 443)

        XCTAssertEqual(endpoint.url.absoluteString, "wss://hermes.example.com:443")
    }

    func testExplicitRemoteTLSAddressIsAccepted() throws {
        let endpoint = try HermesBridgeEndpoint(host: "wss://Hermes.Example.com", port: 9443)

        XCTAssertEqual(endpoint.host, "hermes.example.com")
        XCTAssertEqual(endpoint.url.absoluteString, "wss://hermes.example.com:9443")
    }

    func testRemotePlainWebSocketIsRejected() {
        XCTAssertThrowsError(
            try HermesBridgeEndpoint(host: "ws://hermes.example.com", port: 8765)
        ) { error in
            XCTAssertEqual(error as? HermesBridgeEndpointError, .insecureRemoteEndpoint)
        }
    }

    func testEndpointRejectsInvalidPortCredentialsAndURLPayload() {
        XCTAssertThrowsError(
            try HermesBridgeEndpoint(host: "localhost", port: 0)
        ) { error in
            XCTAssertEqual(error as? HermesBridgeEndpointError, .invalidPort)
        }
        XCTAssertThrowsError(
            try HermesBridgeEndpoint(host: "wss://user:secret@example.com", port: 443)
        ) { error in
            XCTAssertEqual(error as? HermesBridgeEndpointError, .unsupportedURLComponents)
        }
        XCTAssertThrowsError(
            try HermesBridgeEndpoint(host: "wss://example.com/socket?token=secret", port: 443)
        ) { error in
            XCTAssertEqual(error as? HermesBridgeEndpointError, .unsupportedURLComponents)
        }
        XCTAssertThrowsError(
            try HermesBridgeEndpoint(host: "https://example.com", port: 443)
        ) { error in
            XCTAssertEqual(error as? HermesBridgeEndpointError, .unsupportedScheme)
        }
    }

    func testInvalidSavedHostFailsClosedWithoutCrashing() {
        let bridge = HermesAgentBridge(host: "ws://remote.example.com", port: 8765)

        guard case .failed(let message) = bridge.connectionState else {
            return XCTFail("Invalid saved endpoint must be represented as a failed connection")
        }
        XCTAssertTrue(message.contains("wss://"))

        bridge.connect()

        guard case .failed = bridge.connectionState else {
            return XCTFail("Connecting must remain fail-closed until settings are corrected")
        }
    }

    func testDisconnectInvalidatesReconnectAndStaleSocketGenerations() {
        var generation = HermesConnectionGeneration()
        let first = generation.beginConnection()

        XCTAssertTrue(generation.accepts(first))
        XCTAssertTrue(generation.mayReconnect(after: first))

        generation.disconnect()

        XCTAssertFalse(generation.accepts(first))
        XCTAssertFalse(generation.mayReconnect(after: first))

        let second = generation.beginConnection()
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(generation.accepts(first))
        XCTAssertTrue(generation.accepts(second))
        XCTAssertTrue(generation.mayReconnect(after: second))
    }
}
