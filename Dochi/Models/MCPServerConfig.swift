import Foundation

struct MCPServerConfig: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var command: String
    var arguments: [String]
    var environment: [String: String]
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        command: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.isEnabled = isEnabled
    }

    enum CodingKeys: String, CodingKey {
        case id, name, command, arguments, environment
        case isEnabled = "is_enabled"
    }
}
