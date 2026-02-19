import XCTest
@testable import Dochi

final class RuntimeStateTests: XCTestCase {

    // MARK: - RuntimeState Encoding/Decoding

    func testRuntimeStateRawValues() {
        XCTAssertEqual(RuntimeState.notStarted.rawValue, "notStarted")
        XCTAssertEqual(RuntimeState.starting.rawValue, "starting")
        XCTAssertEqual(RuntimeState.ready.rawValue, "ready")
        XCTAssertEqual(RuntimeState.degraded.rawValue, "degraded")
        XCTAssertEqual(RuntimeState.recovering.rawValue, "recovering")
        XCTAssertEqual(RuntimeState.error.rawValue, "error")
    }

    func testRuntimeStateCodableRoundTrip() throws {
        let states: [RuntimeState] = [.notStarted, .starting, .ready, .degraded, .recovering, .error]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for state in states {
            let data = try encoder.encode(state)
            let decoded = try decoder.decode(RuntimeState.self, from: data)
            XCTAssertEqual(decoded, state)
        }
    }

    // MARK: - RuntimeHealthResponse

    func testHealthResponseDecoding() throws {
        let json = """
        {"alive":true,"uptimeMs":12345,"activeSessions":2,"lastError":null}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(RuntimeHealthResponse.self, from: data)

        XCTAssertTrue(response.alive)
        XCTAssertEqual(response.uptimeMs, 12345)
        XCTAssertEqual(response.activeSessions, 2)
        XCTAssertNil(response.lastError)
    }

    func testHealthResponseWithError() throws {
        let json = """
        {"alive":false,"uptimeMs":0,"activeSessions":0,"lastError":"connection timeout"}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(RuntimeHealthResponse.self, from: data)

        XCTAssertFalse(response.alive)
        XCTAssertEqual(response.lastError, "connection timeout")
    }

    func testHealthResponseEncodingRoundTrip() throws {
        let original = RuntimeHealthResponse(alive: true, uptimeMs: 5000, activeSessions: 1, lastError: nil)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(RuntimeHealthResponse.self, from: data)

        XCTAssertEqual(decoded.alive, original.alive)
        XCTAssertEqual(decoded.uptimeMs, original.uptimeMs)
        XCTAssertEqual(decoded.activeSessions, original.activeSessions)
        XCTAssertEqual(decoded.lastError, original.lastError)
    }

    // MARK: - RuntimeInitializeResponse

    func testInitializeResponseDecoding() throws {
        let json = """
        {"capabilities":["session.open","session.run","tool.dispatch"],"runtimeSessionId":"abc-123"}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(RuntimeInitializeResponse.self, from: data)

        XCTAssertEqual(response.capabilities, ["session.open", "session.run", "tool.dispatch"])
        XCTAssertEqual(response.runtimeSessionId, "abc-123")
    }

    // MARK: - RuntimeShutdownResponse

    func testShutdownResponseDecoding() throws {
        let json = """
        {"success":true}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(RuntimeShutdownResponse.self, from: data)

        XCTAssertTrue(response.success)
    }

    // MARK: - JsonRpcRequest

    func testJsonRpcRequestEncoding() throws {
        let request = JsonRpcRequest(id: 1, method: "runtime.health")
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json["id"] as? Int, 1)
        XCTAssertEqual(json["method"] as? String, "runtime.health")
    }

    func testJsonRpcRequestWithParams() throws {
        let params: [String: AnyCodableValue] = [
            "runtimeVersion": .string("0.1.0"),
            "configProfile": .string("default"),
        ]
        let request = JsonRpcRequest(id: 2, method: "runtime.initialize", params: params)
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(JsonRpcRequest.self, from: data)

        XCTAssertEqual(decoded.jsonrpc, "2.0")
        XCTAssertEqual(decoded.id, 2)
        XCTAssertEqual(decoded.method, "runtime.initialize")
        XCTAssertEqual(decoded.params?["runtimeVersion"]?.stringValue, "0.1.0")
        XCTAssertEqual(decoded.params?["configProfile"]?.stringValue, "default")
    }

    // MARK: - JsonRpcResponse

    func testJsonRpcResponseDecoding() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":{"alive":true,"uptimeMs":1000,"activeSessions":0,"lastError":null}}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(JsonRpcResponse.self, from: data)

        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, 1)
        XCTAssertNotNil(response.result)
        XCTAssertNil(response.error)
    }

    func testJsonRpcResponseErrorDecoding() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"Method not found"}}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(JsonRpcResponse.self, from: data)

        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, 1)
        XCTAssertNil(response.result)
        XCTAssertNotNil(response.error)
        XCTAssertEqual(response.error?.code, -32601)
        XCTAssertEqual(response.error?.message, "Method not found")
    }

    // MARK: - AnyCodableValue

    func testAnyCodableValueTypes() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let values: [AnyCodableValue] = [
            .string("hello"),
            .int(42),
            .double(3.14),
            .bool(true),
            .null,
            .array([.string("a"), .int(1)]),
            .object(["key": .string("value")]),
        ]

        for value in values {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(AnyCodableValue.self, from: data)

            switch (value, decoded) {
            case (.string(let a), .string(let b)):
                XCTAssertEqual(a, b)
            case (.int(let a), .int(let b)):
                XCTAssertEqual(a, b)
            case (.double(let a), .double(let b)):
                XCTAssertEqual(a, b, accuracy: 0.001)
            case (.bool(let a), .bool(let b)):
                XCTAssertEqual(a, b)
            case (.null, .null):
                break
            case (.array, .array):
                break // Deep comparison not needed for this test
            case (.object, .object):
                break
            default:
                XCTFail("Type mismatch: \(value) vs \(decoded)")
            }
        }
    }

    func testAnyCodableValueAccessors() {
        XCTAssertEqual(AnyCodableValue.string("test").stringValue, "test")
        XCTAssertNil(AnyCodableValue.int(42).stringValue)

        XCTAssertEqual(AnyCodableValue.int(42).intValue, 42)
        XCTAssertNil(AnyCodableValue.string("test").intValue)

        XCTAssertEqual(AnyCodableValue.bool(true).boolValue, true)
        XCTAssertNil(AnyCodableValue.string("test").boolValue)
    }
}
