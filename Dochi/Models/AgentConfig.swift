import Foundation

struct AgentConfig: Codable, Sendable {
    let name: String
    var wakeWord: String?
    var description: String?
    var defaultModel: String?
    var permissions: [String]?
    var preferredToolGroups: [String]?
    var shellPermissions: ShellPermissionConfig?
    var delegationPolicy: DelegationPolicy?

    var effectivePermissions: [String] {
        permissions ?? ["safe", "sensitive", "restricted"]
    }

    var effectivePreferredToolGroups: [String] {
        guard let preferredToolGroups else { return [] }

        var result: [String] = []
        var seen: Set<String> = []
        for raw in preferredToolGroups {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }
        return result
    }

    var effectiveShellPermissions: ShellPermissionConfig {
        shellPermissions ?? .default
    }

    var effectiveDelegationPolicy: DelegationPolicy {
        delegationPolicy ?? .default
    }

    // Custom decoder for backward compatibility with existing config files
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        wakeWord = try container.decodeIfPresent(String.self, forKey: .wakeWord)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        defaultModel = try container.decodeIfPresent(String.self, forKey: .defaultModel)
        permissions = try container.decodeIfPresent([String].self, forKey: .permissions)
        preferredToolGroups = try container.decodeIfPresent([String].self, forKey: .preferredToolGroups)
        shellPermissions = try container.decodeIfPresent(ShellPermissionConfig.self, forKey: .shellPermissions)
        delegationPolicy = try container.decodeIfPresent(DelegationPolicy.self, forKey: .delegationPolicy)
    }

    init(
        name: String,
        wakeWord: String? = nil,
        description: String? = nil,
        defaultModel: String? = nil,
        permissions: [String]? = nil,
        preferredToolGroups: [String]? = nil,
        shellPermissions: ShellPermissionConfig? = nil,
        delegationPolicy: DelegationPolicy? = nil
    ) {
        self.name = name
        self.wakeWord = wakeWord
        self.description = description
        self.defaultModel = defaultModel
        self.permissions = permissions
        self.preferredToolGroups = preferredToolGroups
        self.shellPermissions = shellPermissions
        self.delegationPolicy = delegationPolicy
    }
}
