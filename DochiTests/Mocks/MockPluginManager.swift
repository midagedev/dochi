import Foundation
@testable import Dochi

@MainActor
final class MockPluginManager: PluginManagerProtocol {
    var plugins: [PluginInfo] = []
    var pluginDirectory: URL = URL(fileURLWithPath: "/tmp/mock-plugins")

    var scanCallCount = 0
    var enableCallCount = 0
    var disableCallCount = 0
    var removeCallCount = 0
    var lastEnabledId: String?
    var lastDisabledId: String?
    var lastRemovedId: String?
    var stubbedRemoveError: Error?

    func scanPlugins() {
        scanCallCount += 1
    }

    func enablePlugin(id: String) {
        enableCallCount += 1
        lastEnabledId = id
        if let index = plugins.firstIndex(where: { $0.id == id }) {
            plugins[index].status = .active
        }
    }

    func disablePlugin(id: String) {
        disableCallCount += 1
        lastDisabledId = id
        if let index = plugins.firstIndex(where: { $0.id == id }) {
            plugins[index].status = .inactive
        }
    }

    func removePlugin(id: String) throws {
        removeCallCount += 1
        lastRemovedId = id
        if let error = stubbedRemoveError { throw error }
        plugins.removeAll { $0.id == id }
    }
}
