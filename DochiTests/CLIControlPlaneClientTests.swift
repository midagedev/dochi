import XCTest
@testable import Dochi

final class CLIControlPlaneClientTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private var socketURL: URL!
    private var tokenURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let suffix = String(UUID().uuidString.prefix(8))
        tempDirectoryURL = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("dc-cli-\(suffix)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        socketURL = tempDirectoryURL.appendingPathComponent("dochi.sock")
        tokenURL = tempDirectoryURL.appendingPathComponent("control-plane.token")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
        try super.tearDownWithError()
    }

    func testCallReturnsResultPayload() throws {
        let service = LocalControlPlaneService(socketURL: socketURL) { method, params in
            guard method == "app.ping" else {
                return .failure(code: "method_not_found", message: method)
            }
            return .ok([
                "status": "ok",
                "echo": params["message"] as? String ?? "",
            ])
        }
        defer { service.stop() }

        service.start()
        try waitForSocket()

        let client = CLIControlPlaneClient(socketURL: socketURL)
        let result = try client.call(method: "app.ping", params: ["message": "hello"])

        XCTAssertEqual(result["status"] as? String, "ok")
        XCTAssertEqual(result["echo"] as? String, "hello")
    }

    func testCallThrowsRemoteErrorWhenMethodFails() throws {
        let service = LocalControlPlaneService(socketURL: socketURL) { _, _ in
            .failure(code: "forbidden", message: "denied")
        }
        defer { service.stop() }

        service.start()
        try waitForSocket()

        let client = CLIControlPlaneClient(socketURL: socketURL)
        XCTAssertThrowsError(try client.call(method: "tool.execute")) { error in
            guard case CLIControlPlaneError.remoteError(let code, let message) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(code, "forbidden")
            XCTAssertEqual(message, "denied")
        }
    }

    func testCallThrowsConnectFailedWhenSocketIsUnavailable() {
        let missingSocket = tempDirectoryURL.appendingPathComponent("missing.sock")
        let client = CLIControlPlaneClient(socketURL: missingSocket, timeoutSeconds: 1)

        XCTAssertThrowsError(try client.call(method: "app.ping")) { error in
            guard case CLIControlPlaneError.connectFailed = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testCallIncludesAuthTokenFromTokenFile() throws {
        try Data("secret-token".utf8).write(to: tokenURL, options: .atomic)

        let service = LocalControlPlaneService(
            socketURL: socketURL,
            methodHandler: { method, _ in
                guard method == "app.ping" else {
                    return .failure(code: "method_not_found", message: method)
                }
                return .ok(["status": "ok"])
            },
            authTokenProvider: { "secret-token" }
        )
        defer { service.stop() }

        service.start()
        try waitForSocket()

        let client = CLIControlPlaneClient(socketURL: socketURL, tokenURL: tokenURL)
        let result = try client.call(method: "app.ping")
        XCTAssertEqual(result["status"] as? String, "ok")
    }

    func testCallThrowsUnauthorizedWhenTokenDoesNotMatch() throws {
        try Data("wrong-token".utf8).write(to: tokenURL, options: .atomic)

        let service = LocalControlPlaneService(
            socketURL: socketURL,
            methodHandler: { _, _ in .ok(["status": "ok"]) },
            authTokenProvider: { "secret-token" }
        )
        defer { service.stop() }

        service.start()
        try waitForSocket()

        let client = CLIControlPlaneClient(socketURL: socketURL, tokenURL: tokenURL)
        XCTAssertThrowsError(try client.call(method: "app.ping")) { error in
            guard case CLIControlPlaneError.remoteError(let code, _) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(code, "unauthorized")
        }
    }

    private func waitForSocket(timeout: TimeInterval = 2.0) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: socketURL.path) {
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw NSError(domain: "CLIControlPlaneClientTests", code: 1)
    }
}
