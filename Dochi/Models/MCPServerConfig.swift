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

extension MCPServerConfig {
    /// Standard coding MCP profiles (filesystem / git / shell).
    ///
    /// - Parameters:
    ///   - workspaceRoot: Base path for filesystem and shell profiles.
    ///   - gitRepositoryPath: Git repository root for git profile. If nil, git profile is added disabled.
    static func codingDefaultProfiles(
        workspaceRoot: String? = nil,
        gitRepositoryPath: String? = nil
    ) -> [MCPServerConfig] {
        let resolvedWorkspace = normalizePath(
            workspaceRoot
                ?? detectDefaultWorkspaceRoot()
        )
        let rawGitRepo = gitRepositoryPath ?? detectDefaultGitRepositoryPath()
        let resolvedGitRepo = normalizePath(rawGitRepo)
        let gitEnabled = rawGitRepo != nil && !resolvedGitRepo.isEmpty

        let filesystem = MCPServerConfig(
            name: "coding-filesystem",
            command: "npx",
            arguments: [
                "-y",
                "@modelcontextprotocol/server-filesystem",
                resolvedWorkspace,
            ]
        )

        let git = MCPServerConfig(
            name: "coding-git",
            command: "uvx",
            arguments: [
                "mcp-server-git",
                "--repository",
                gitEnabled ? resolvedGitRepo : resolvedWorkspace,
            ],
            isEnabled: gitEnabled
        )

        let shell = MCPServerConfig(
            name: "coding-shell",
            command: "npx",
            arguments: [
                "-y",
                "@mako10k/mcp-shell-server",
            ],
            environment: [
                "MCP_SHELL_DEFAULT_WORKDIR": resolvedWorkspace,
                "MCP_ALLOWED_WORKDIRS": resolvedWorkspace,
                "LOG_LEVEL": "warn",
            ]
        )

        return [filesystem, git, shell]
    }

    static func detectDefaultWorkspaceRoot() -> String {
        if let gitRepo = detectDefaultGitRepositoryPath() {
            return gitRepo
        }

        let candidates: [String?] = [
            ProcessInfo.processInfo.environment["PWD"],
            FileManager.default.currentDirectoryPath,
            NSHomeDirectory(),
        ]

        for candidate in candidates {
            let normalized = normalizePath(candidate)
            if !normalized.isEmpty {
                return normalized
            }
        }

        return NSHomeDirectory()
    }

    static func detectDefaultGitRepositoryPath() -> String? {
        let candidates: [String?] = [
            ProcessInfo.processInfo.environment["PWD"],
            FileManager.default.currentDirectoryPath,
        ]

        for candidate in candidates {
            guard let root = nearestGitRepositoryRoot(from: candidate) else { continue }
            return root
        }

        return nil
    }

    private static func nearestGitRepositoryRoot(from rawPath: String?) -> String? {
        let normalized = normalizePath(rawPath)
        guard !normalized.isEmpty else { return nil }

        let fm = FileManager.default
        var currentURL = URL(fileURLWithPath: normalized).standardizedFileURL

        while true {
            let gitPath = currentURL.appendingPathComponent(".git").path
            if fm.fileExists(atPath: gitPath) {
                return currentURL.path
            }

            let parent = currentURL.deletingLastPathComponent()
            if parent.path == currentURL.path {
                break
            }
            currentURL = parent
        }

        return nil
    }

    private static func normalizePath(_ rawPath: String?) -> String {
        guard let rawPath else { return "" }
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return NSString(string: trimmed).expandingTildeInPath
    }
}
