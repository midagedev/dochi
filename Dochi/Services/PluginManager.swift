import Foundation

/// Manages plugin discovery, activation, and persistence.
@MainActor
@Observable
final class PluginManager: PluginManagerProtocol {

    // MARK: - State

    private(set) var plugins: [PluginInfo] = []

    let pluginDirectory: URL

    // MARK: - Private

    private let stateFileURL: URL
    private let fileManager = FileManager.default

    // MARK: - Init

    init(baseURL: URL? = nil) {
        let base = baseURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dochi")
        self.pluginDirectory = base.appendingPathComponent("plugins")
        self.stateFileURL = base.appendingPathComponent("plugins-state.json")

        ensureDirectoryExists()
        scanPlugins()
    }

    // MARK: - PluginManagerProtocol

    func scanPlugins() {
        var discovered: [PluginInfo] = []
        let savedStates = loadStates()

        guard let contents = try? fileManager.contentsOfDirectory(
            at: pluginDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            plugins = []
            Log.app.info("Plugin scan: no plugins directory or empty")
            return
        }

        for dir in contents {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let manifestURL = dir.appendingPathComponent("manifest.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                continue
            }

            do {
                let data = try Data(contentsOf: manifestURL)
                let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)

                guard validateManifest(manifest) else {
                    discovered.append(PluginInfo(
                        manifest: manifest,
                        status: .error,
                        loadedAt: Date(),
                        errorMessage: "매니페스트 검증 실패: 필수 필드 누락"
                    ))
                    continue
                }

                let status = savedStates[manifest.id] ?? .inactive
                discovered.append(PluginInfo(
                    manifest: manifest,
                    status: status,
                    loadedAt: Date()
                ))
                Log.app.debug("Plugin loaded: \(manifest.id) v\(manifest.version) [\(status.rawValue)]")
            } catch {
                Log.app.warning("Plugin manifest parse failed at \(dir.lastPathComponent): \(error.localizedDescription)")
                // Create a placeholder error entry
                let errorManifest = PluginManifest(
                    id: dir.lastPathComponent,
                    name: dir.lastPathComponent,
                    version: "?",
                    author: nil,
                    description: nil,
                    icon: nil,
                    capabilities: .init(),
                    permissions: .init(),
                    minAppVersion: nil
                )
                discovered.append(PluginInfo(
                    manifest: errorManifest,
                    status: .error,
                    loadedAt: Date(),
                    errorMessage: error.localizedDescription
                ))
            }
        }

        plugins = discovered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let pluginCount = plugins.count
        Log.app.info("Plugin scan complete: \(pluginCount) plugin(s) found")
    }

    func enablePlugin(id: String) {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else { return }
        plugins[index].status = .active
        plugins[index].errorMessage = nil
        saveStates()
        Log.app.info("Plugin enabled: \(id)")
    }

    func disablePlugin(id: String) {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else { return }
        plugins[index].status = .inactive
        saveStates()
        Log.app.info("Plugin disabled: \(id)")
    }

    func removePlugin(id: String) throws {
        let pluginDir = pluginDirectory.appendingPathComponent(id)
        guard fileManager.fileExists(atPath: pluginDir.path) else {
            Log.app.warning("Plugin directory not found for removal: \(id)")
            return
        }
        try fileManager.removeItem(at: pluginDir)
        plugins.removeAll { $0.id == id }

        // Clean up saved state
        var states = loadStates()
        states.removeValue(forKey: id)
        saveStates(states)

        Log.app.info("Plugin removed: \(id)")
    }

    // MARK: - Private Helpers

    private func ensureDirectoryExists() {
        if !fileManager.fileExists(atPath: pluginDirectory.path) {
            do {
                try fileManager.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
            } catch {
                Log.app.error("Failed to create plugins directory: \(error.localizedDescription)")
            }
        }
    }

    private func validateManifest(_ manifest: PluginManifest) -> Bool {
        !manifest.id.isEmpty && !manifest.name.isEmpty && !manifest.version.isEmpty
    }

    // MARK: - State Persistence

    private func loadStates() -> [String: PluginStatus] {
        guard let data = try? Data(contentsOf: stateFileURL),
              let file = try? JSONDecoder().decode(PluginStateFile.self, from: data) else {
            return [:]
        }
        return file.states
    }

    private func saveStates(_ overrideStates: [String: PluginStatus]? = nil) {
        let states: [String: PluginStatus]
        if let overrideStates {
            states = overrideStates
        } else {
            states = Dictionary(uniqueKeysWithValues: plugins.map { ($0.id, $0.status) })
        }
        let file = PluginStateFile(states: states)
        do {
            let data = try JSONEncoder().encode(file)
            try data.write(to: stateFileURL, options: .atomic)
        } catch {
            Log.app.error("Failed to save plugin states: \(error.localizedDescription)")
        }
    }
}
