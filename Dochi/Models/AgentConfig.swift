import Foundation

struct AgentConfig: Codable, Sendable {
    let name: String
    var wakeWord: String?
    var description: String?
    var defaultModel: String?
    var permissions: [String]?

    var effectivePermissions: [String] {
        permissions ?? ["safe"]
    }
}
