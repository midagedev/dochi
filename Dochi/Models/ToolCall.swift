import Foundation

struct CodableToolCall: Codable, Sendable {
    let id: String
    let name: String
    let argumentsJSON: String

    var arguments: [String: Any] {
        guard let data = argumentsJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }
}

struct ToolCall: @unchecked Sendable {
    let id: String
    let name: String
    let arguments: [String: Any]

    var codable: CodableToolCall {
        let data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data()
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return CodableToolCall(id: id, name: name, argumentsJSON: json)
    }
}
