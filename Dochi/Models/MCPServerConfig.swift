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

    static func normalizePath(_ rawPath: String?) -> String {
        guard let rawPath else { return "" }
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return NSString(string: trimmed).expandingTildeInPath
    }

    // MARK: - Coding-Git Repo Path Helpers

    /// Whether this config is a coding-git profile.
    var isCodingGitProfile: Bool {
        name == "coding-git"
    }

    /// Extracts the `--repository` value from arguments, if present.
    var codingGitRepoPath: String? {
        guard isCodingGitProfile else { return nil }
        guard let idx = arguments.firstIndex(of: "--repository"),
              arguments.index(after: idx) < arguments.endIndex else { return nil }
        let path = arguments[arguments.index(after: idx)]
        return path.isEmpty ? nil : path
    }

    /// Returns a new config with the `--repository` argument updated to `newPath`.
    /// If `--repository` is not found in arguments, appends it.
    /// Enables the profile if it was previously disabled.
    func withUpdatedRepoPath(_ newPath: String) -> MCPServerConfig {
        let normalized = Self.normalizePath(newPath)
        guard !normalized.isEmpty else { return self }

        var newArgs = arguments
        if let idx = newArgs.firstIndex(of: "--repository"),
           newArgs.index(after: idx) < newArgs.endIndex {
            newArgs[newArgs.index(after: idx)] = normalized
        } else {
            newArgs.append("--repository")
            newArgs.append(normalized)
        }

        return MCPServerConfig(
            id: id,
            name: name,
            command: command,
            arguments: newArgs,
            environment: environment,
            isEnabled: true
        )
    }

    /// Validates that a path is a directory containing a `.git` subfolder.
    static func isValidGitRepository(at path: String) -> Bool {
        let normalized = normalizePath(path)
        guard !normalized.isEmpty else { return false }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: normalized, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        let gitPath = URL(fileURLWithPath: normalized).appendingPathComponent(".git").path
        return fm.fileExists(atPath: gitPath)
    }
}
