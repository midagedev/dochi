import Foundation

/// Runtime sidecar process lifecycle states.
enum RuntimeState: String, Codable, Sendable {
    case notStarted
    case starting
    case ready
    case degraded
    case recovering
    case error
}

/// Response from the runtime `runtime.health` RPC method.
struct RuntimeHealthResponse: Codable, Sendable {
    let alive: Bool
    let uptimeMs: Int
    let activeSessions: Int
    let lastError: String?
}

/// Result from the runtime `runtime.initialize` RPC method.
struct RuntimeInitializeResponse: Codable, Sendable {
    let capabilities: [String]
    let runtimeSessionId: String
}

/// Result from the runtime `runtime.shutdown` RPC method.
struct RuntimeShutdownResponse: Codable, Sendable {
    let success: Bool
}

// MARK: - JSON-RPC Message Types

/// A JSON-RPC 2.0 request message.
struct JsonRpcRequest: Codable, Sendable {
    let jsonrpc: String
    let id: Int
    let method: String
    let params: [String: AnyCodableValue]?

    init(id: Int, method: String, params: [String: AnyCodableValue]? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

/// A JSON-RPC 2.0 response message.
struct JsonRpcResponse: Codable, Sendable {
    let jsonrpc: String
    let id: Int
    let result: AnyCodableValue?
    let error: JsonRpcErrorObject?
}

/// A JSON-RPC 2.0 error object.
struct JsonRpcErrorObject: Codable, Sendable {
    let code: Int
    let message: String
}

/// A JSON-RPC 2.0 notification (no id).
struct JsonRpcNotification: Codable, Sendable {
    let jsonrpc: String
    let method: String
    let params: [String: AnyCodableValue]?
}

// MARK: - AnyCodableValue

/// A type-erased Codable value for JSON-RPC params/results.
enum AnyCodableValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AnyCodableValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AnyCodableValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }
}
