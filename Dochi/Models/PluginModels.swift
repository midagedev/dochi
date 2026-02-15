import Foundation

// MARK: - PluginManifest

/// JSON manifest describing a plugin's metadata, capabilities, and permissions.
struct PluginManifest: Codable, Sendable {
    let id: String
    let name: String
    let version: String
    let author: String?
    let description: String?
    let icon: String?
    let capabilities: PluginCapabilities
    let permissions: PluginPermissions
    let minAppVersion: String?

    struct PluginCapabilities: Codable, Sendable {
        var tools: [PluginCapabilityEntry]?
        var providers: [PluginCapabilityEntry]?
        var ttsEngines: [PluginCapabilityEntry]?
    }

    struct PluginPermissions: Codable, Sendable {
        var network: Bool?
        var fileRead: Bool?
        var fileWrite: Bool?
    }
}

// MARK: - PluginCapabilityEntry

/// A single capability item provided by a plugin.
struct PluginCapabilityEntry: Codable, Sendable, Identifiable {
    let name: String
    let description: String?

    var id: String { name }
}

// MARK: - PluginStatus

/// Plugin activation status.
enum PluginStatus: String, Codable, Sendable {
    case active
    case inactive
    case error
}

// MARK: - PluginInfo

/// Runtime info for a loaded plugin, combining manifest data with runtime state.
struct PluginInfo: Identifiable, Sendable {
    let manifest: PluginManifest
    var status: PluginStatus
    var loadedAt: Date?
    var errorMessage: String?
    var directoryURL: URL?

    var id: String { manifest.id }
    var name: String { manifest.name }
    var version: String { manifest.version }
    var author: String? { manifest.author }
    var pluginDescription: String? { manifest.description }
    var icon: String { manifest.icon ?? "puzzlepiece.extension" }

    var toolCount: Int { manifest.capabilities.tools?.count ?? 0 }
    var providerCount: Int { manifest.capabilities.providers?.count ?? 0 }
    var ttsEngineCount: Int { manifest.capabilities.ttsEngines?.count ?? 0 }

    var isActive: Bool { status == .active }
}

// MARK: - PluginStateFile

/// Persisted plugin activation states.
struct PluginStateFile: Codable, Sendable {
    var states: [String: PluginStatus]
}
