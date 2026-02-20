import Foundation

/// Groups multiple MCP server configurations into a named profile.
/// For example, the built-in "coding" profile bundles filesystem, git, and shell servers.
struct MCPServerProfile: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var displayName: String
    var description: String
    var servers: [MCPServerConfig]
    var isEnabled: Bool
    var autoRestart: Bool
    var maxRestartAttempts: Int
    var healthCheckIntervalSeconds: UInt64

    init(
        id: UUID = UUID(),
        name: String,
        displayName: String = "",
        description: String = "",
        servers: [MCPServerConfig] = [],
        isEnabled: Bool = true,
        autoRestart: Bool = true,
        maxRestartAttempts: Int = 3,
        healthCheckIntervalSeconds: UInt64 = 8
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName.isEmpty ? name : displayName
        self.description = description
        self.servers = servers
        self.isEnabled = isEnabled
        self.autoRestart = autoRestart
        self.maxRestartAttempts = maxRestartAttempts
        self.healthCheckIntervalSeconds = healthCheckIntervalSeconds
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, servers
        case displayName = "display_name"
        case isEnabled = "is_enabled"
        case autoRestart = "auto_restart"
        case maxRestartAttempts = "max_restart_attempts"
        case healthCheckIntervalSeconds = "health_check_interval_seconds"
    }

    // MARK: - Built-in Profiles

    /// Creates the default "coding" profile wrapping the three coding MCP servers.
    static func coding(
        workspaceRoot: String? = nil,
        gitRepositoryPath: String? = nil
    ) -> MCPServerProfile {
        MCPServerProfile(
            name: "coding",
            displayName: "코딩",
            description: "파일시스템, Git, 셸 MCP 서버 프로파일",
            servers: MCPServerConfig.codingDefaultProfiles(
                workspaceRoot: workspaceRoot,
                gitRepositoryPath: gitRepositoryPath
            ),
            isEnabled: true,
            autoRestart: true,
            maxRestartAttempts: 3,
            healthCheckIntervalSeconds: 8
        )
    }

    /// All built-in profile names.
    static let builtInProfiles: Set<String> = ["coding"]

    /// Whether this profile is a built-in (non-removable) profile.
    var isBuiltIn: Bool {
        Self.builtInProfiles.contains(name)
    }

    /// Finds a server config within this profile by name.
    func server(named serverName: String) -> MCPServerConfig? {
        servers.first { $0.name == serverName }
    }

    /// Returns a copy of this profile with the given server config replaced (matched by ID).
    func withUpdatedServer(_ config: MCPServerConfig) -> MCPServerProfile {
        var updated = self
        if let idx = updated.servers.firstIndex(where: { $0.id == config.id }) {
            updated.servers[idx] = config
        }
        return updated
    }
}
