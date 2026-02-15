import Foundation

/// Protocol for plugin lifecycle management.
@MainActor
protocol PluginManagerProtocol {
    var plugins: [PluginInfo] { get }
    var pluginDirectory: URL { get }

    func scanPlugins()
    func enablePlugin(id: String)
    func disablePlugin(id: String)
    func removePlugin(id: String) throws
}
