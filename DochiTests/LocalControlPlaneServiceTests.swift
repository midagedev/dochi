import XCTest
import Darwin
@testable import Dochi

final class LocalControlPlaneServiceTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private var socketURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let suffix = String(UUID().uuidString.prefix(8))
        tempDirectoryURL = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("dc-\(suffix)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        socketURL = tempDirectoryURL.appendingPathComponent("dochi.sock")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
        try super.tearDownWithError()
    }

    func testRoundTripResponseIncludesRequestId() throws {
        let service = LocalControlPlaneService(socketURL: socketURL) { method, params in
            guard method == "app.ping" else {
                return .failure(code: "method_not_found", message: "unknown method")
            }
            return .ok([
                "pong": true,
                "echo": params["value"] as? String ?? "",
            ])
        }
        defer { service.stop() }

        service.start()
        try waitForSocket()

        let response = try sendJSONRequest([
            "request_id": "req-1",
            "method": "app.ping",
            "params": ["value": "hello"],
        ])

        XCTAssertEqual(response["request_id"] as? String, "req-1")
        XCTAssertEqual(response["ok"] as? Bool, true)
        let result = response["result"] as? [String: Any]
        XCTAssertEqual(result?["pong"] as? Bool, true)
        XCTAssertEqual(result?["echo"] as? String, "hello")
    }

    func testUnknownMethodReturnsStructuredError() throws {
        let service = LocalControlPlaneService(socketURL: socketURL) { method, _ in
            .failure(code: "method_not_found", message: "지원하지 않는 메서드: \(method)")
        }
        defer { service.stop() }

        service.start()
        try waitForSocket()

        let response = try sendJSONRequest([
            "request_id": "req-unknown",
            "method": "unknown.method",
            "params": [:],
        ])

        XCTAssertEqual(response["request_id"] as? String, "req-unknown")
        XCTAssertEqual(response["ok"] as? Bool, false)
        let error = response["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? String, "method_not_found")
        XCTAssertTrue((error?["message"] as? String ?? "").contains("unknown.method"))
    }

    func testInvalidJSONReturnsParseError() throws {
        let service = LocalControlPlaneService(socketURL: socketURL) { _, _ in
            XCTFail("handler should not be called for invalid JSON")
            return .failure(code: "unexpected", message: "unexpected")
        }
        defer { service.stop() }

        service.start()
        try waitForSocket()

        let response = try sendRawRequest("{invalid json}\n")

        XCTAssertEqual(response["ok"] as? Bool, false)
        let error = response["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? String, "invalid_json")
    }

    func testSocketFilePermissionIs0600() throws {
        let service = LocalControlPlaneService(socketURL: socketURL) { _, _ in
            .ok(["status": "ok"])
        }
        defer { service.stop() }

        service.start()
        try waitForSocket()

        var fileStat = stat()
        let result = socketURL.path.withCString { cString in
            stat(cString, &fileStat)
        }
        XCTAssertEqual(result, 0)
        let permissionBits = fileStat.st_mode & 0o777
        XCTAssertEqual(permissionBits, 0o600)
    }

    func testRejectsRequestWithoutAuthTokenWhenProviderConfigured() throws {
        let service = LocalControlPlaneService(
            socketURL: socketURL,
            methodHandler: { _, _ in .ok(["status": "ok"]) },
            authTokenProvider: { "secret-token" }
        )
        defer { service.stop() }

        service.start()
        try waitForSocket()

        let response = try sendJSONRequest([
            "request_id": "auth-missing",
            "method": "app.ping",
            "params": [:],
        ])

        XCTAssertEqual(response["ok"] as? Bool, false)
        let error = response["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? String, "unauthorized")
    }

    func testAcceptsRequestWithValidAuthToken() throws {
        let service = LocalControlPlaneService(
            socketURL: socketURL,
            methodHandler: { method, _ in .ok(["echo_method": method]) },
            authTokenProvider: { "secret-token" }
        )
        defer { service.stop() }

        service.start()
        try waitForSocket()

        let response = try sendJSONRequest([
            "request_id": "auth-ok",
            "method": "app.ping",
            "auth_token": "secret-token",
            "params": [:],
        ])

        XCTAssertEqual(response["ok"] as? Bool, true)
        let result = response["result"] as? [String: Any]
        XCTAssertEqual(result?["echo_method"] as? String, "app.ping")
    }

    private func waitForSocket(timeout: TimeInterval = 2.0) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: socketURL.path) {
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw NSError(domain: "LocalControlPlaneServiceTests", code: 1)
    }

    private func sendJSONRequest(_ payload: [String: Any]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard var text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "LocalControlPlaneServiceTests", code: 2)
        }
        text.append("\n")
        return try sendRawRequest(text)
    }

    private func sendRawRequest(_ rawText: String) throws -> [String: Any] {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "LocalControlPlaneServiceTests", code: 3)
        }
        defer {
            shutdown(fd, SHUT_RDWR)
            close(fd)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path)
        let pathBytes = socketURL.path.utf8CString
        guard pathBytes.count < maxPathLength else {
            throw NSError(domain: "LocalControlPlaneServiceTests", code: 4)
        }

        withUnsafeMutableBytes(of: &addr.sun_path) { rawBuffer in
            rawBuffer.initializeMemory(as: UInt8.self, repeating: 0)
            for (index, byte) in pathBytes.enumerated() {
                rawBuffer[index] = UInt8(bitPattern: byte)
            }
        }

        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw NSError(domain: "LocalControlPlaneServiceTests", code: 5)
        }

        let requestData = Data(rawText.utf8)
        try requestData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw NSError(domain: "LocalControlPlaneServiceTests", code: 6)
            }
            var written = 0
            while written < requestData.count {
                let pointer = baseAddress.advanced(by: written)
                let count = write(fd, pointer, requestData.count - written)
                if count <= 0 {
                    throw NSError(domain: "LocalControlPlaneServiceTests", code: 7)
                }
                written += count
            }
        }

        shutdown(fd, SHUT_WR)

        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            received.append(buffer, count: count)
            if received.contains(0x0A) { break }
        }

        guard !received.isEmpty else {
            throw NSError(domain: "LocalControlPlaneServiceTests", code: 8)
        }

        let lineData: Data
        if let newlineIndex = received.firstIndex(of: 0x0A) {
            lineData = Data(received.prefix(upTo: newlineIndex))
        } else {
            lineData = received
        }

        guard let json = try JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
            throw NSError(domain: "LocalControlPlaneServiceTests", code: 9)
        }
        return json
    }
}
