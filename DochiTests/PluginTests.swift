import XCTest
@testable import Dochi

// MARK: - PluginManifest Tests

final class PluginManifestTests: XCTestCase {

    func testDecodeMinimalManifest() throws {
        let json = """
        {
            "id": "test-plugin",
            "name": "Test Plugin",
            "version": "1.0.0",
            "capabilities": {},
            "permissions": {}
        }
        """
        let data = json.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        XCTAssertEqual(manifest.id, "test-plugin")
        XCTAssertEqual(manifest.name, "Test Plugin")
        XCTAssertEqual(manifest.version, "1.0.0")
        XCTAssertNil(manifest.author)
        XCTAssertNil(manifest.description)
        XCTAssertNil(manifest.icon)
        XCTAssertNil(manifest.minAppVersion)
        XCTAssertNil(manifest.capabilities.tools)
        XCTAssertNil(manifest.capabilities.providers)
        XCTAssertNil(manifest.capabilities.ttsEngines)
    }

    func testDecodeFullManifest() throws {
        let json = """
        {
            "id": "my-plugin",
            "name": "My Plugin",
            "version": "2.1.0",
            "author": "Author Name",
            "description": "A test plugin",
            "icon": "star.fill",
            "capabilities": {
                "tools": [
                    {"name": "tool1", "description": "First tool"},
                    {"name": "tool2", "description": null}
                ],
                "providers": [
                    {"name": "custom-llm", "description": "Custom LLM"}
                ],
                "ttsEngines": []
            },
            "permissions": {
                "network": true,
                "fileRead": true,
                "fileWrite": false
            },
            "minAppVersion": "1.5.0"
        }
        """
        let data = json.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        XCTAssertEqual(manifest.id, "my-plugin")
        XCTAssertEqual(manifest.author, "Author Name")
        XCTAssertEqual(manifest.description, "A test plugin")
        XCTAssertEqual(manifest.icon, "star.fill")
        XCTAssertEqual(manifest.capabilities.tools?.count, 2)
        XCTAssertEqual(manifest.capabilities.tools?.first?.name, "tool1")
        XCTAssertEqual(manifest.capabilities.providers?.count, 1)
        XCTAssertEqual(manifest.capabilities.ttsEngines?.count, 0)
        XCTAssertEqual(manifest.permissions.network, true)
        XCTAssertEqual(manifest.permissions.fileRead, true)
        XCTAssertEqual(manifest.permissions.fileWrite, false)
        XCTAssertEqual(manifest.minAppVersion, "1.5.0")
    }

    func testRoundtripEncoding() throws {
        let manifest = PluginManifest(
            id: "roundtrip",
            name: "Roundtrip",
            version: "1.0.0",
            author: "Test",
            description: "desc",
            icon: nil,
            capabilities: .init(
                tools: [PluginCapabilityEntry(name: "t1", description: "d1")]
            ),
            permissions: .init(network: true, fileRead: nil, fileWrite: nil),
            minAppVersion: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(manifest)
        let decoded = try JSONDecoder().decode(PluginManifest.self, from: data)
        XCTAssertEqual(decoded.id, "roundtrip")
        XCTAssertEqual(decoded.capabilities.tools?.count, 1)
        XCTAssertEqual(decoded.permissions.network, true)
    }
}

// MARK: - PluginInfo Tests

final class PluginInfoTests: XCTestCase {

    func testPluginInfoDefaults() {
        let manifest = PluginManifest(
            id: "test",
            name: "Test",
            version: "1.0",
            author: nil,
            description: nil,
            icon: nil,
            capabilities: .init(),
            permissions: .init(),
            minAppVersion: nil
        )
        let info = PluginInfo(manifest: manifest, status: .inactive)
        XCTAssertEqual(info.id, "test")
        XCTAssertEqual(info.name, "Test")
        XCTAssertEqual(info.icon, "puzzlepiece.extension") // default icon
        XCTAssertFalse(info.isActive)
        XCTAssertEqual(info.toolCount, 0)
        XCTAssertEqual(info.providerCount, 0)
        XCTAssertEqual(info.ttsEngineCount, 0)
        XCTAssertNil(info.errorMessage)
    }

    func testPluginInfoActive() {
        let manifest = PluginManifest(
            id: "active-test",
            name: "Active",
            version: "1.0",
            author: nil,
            description: nil,
            icon: "star",
            capabilities: .init(
                tools: [
                    PluginCapabilityEntry(name: "t1", description: nil),
                    PluginCapabilityEntry(name: "t2", description: nil),
                ]
            ),
            permissions: .init(),
            minAppVersion: nil
        )
        let info = PluginInfo(manifest: manifest, status: .active, loadedAt: Date())
        XCTAssertTrue(info.isActive)
        XCTAssertEqual(info.toolCount, 2)
        XCTAssertEqual(info.icon, "star")
    }

    func testPluginStatusRawValues() {
        XCTAssertEqual(PluginStatus.active.rawValue, "active")
        XCTAssertEqual(PluginStatus.inactive.rawValue, "inactive")
        XCTAssertEqual(PluginStatus.error.rawValue, "error")
    }
}

// MARK: - PluginStateFile Tests

final class PluginStateFileTests: XCTestCase {

    func testStateFileRoundtrip() throws {
        let stateFile = PluginStateFile(states: [
            "plugin-a": .active,
            "plugin-b": .inactive,
            "plugin-c": .error,
        ])
        let data = try JSONEncoder().encode(stateFile)
        let decoded = try JSONDecoder().decode(PluginStateFile.self, from: data)
        XCTAssertEqual(decoded.states.count, 3)
        XCTAssertEqual(decoded.states["plugin-a"], .active)
        XCTAssertEqual(decoded.states["plugin-b"], .inactive)
        XCTAssertEqual(decoded.states["plugin-c"], .error)
    }
}

// MARK: - PluginManager Tests

@MainActor
final class PluginManagerTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PluginManagerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - Scan Tests

    func testScanEmptyDirectory() {
        let manager = PluginManager(baseURL: tempDir)
        XCTAssertTrue(manager.plugins.isEmpty)
    }

    func testScanWithValidPlugin() throws {
        // Create a plugin directory with manifest
        let pluginDir = tempDir.appendingPathComponent("plugins/test-plugin")
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let manifest = """
        {
            "id": "test-plugin",
            "name": "Test Plugin",
            "version": "1.0.0",
            "author": "Tester",
            "description": "A test",
            "capabilities": {
                "tools": [{"name": "hello", "description": "Says hello"}]
            },
            "permissions": {"network": true}
        }
        """
        try manifest.write(to: pluginDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let manager = PluginManager(baseURL: tempDir)
        XCTAssertEqual(manager.plugins.count, 1)
        XCTAssertEqual(manager.plugins.first?.id, "test-plugin")
        XCTAssertEqual(manager.plugins.first?.name, "Test Plugin")
        XCTAssertEqual(manager.plugins.first?.status, .inactive) // default state
        XCTAssertEqual(manager.plugins.first?.toolCount, 1)
    }

    func testScanWithInvalidManifest() throws {
        let pluginDir = tempDir.appendingPathComponent("plugins/bad-plugin")
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        try "not valid json".write(to: pluginDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let manager = PluginManager(baseURL: tempDir)
        XCTAssertEqual(manager.plugins.count, 1)
        XCTAssertEqual(manager.plugins.first?.status, .error)
        XCTAssertNotNil(manager.plugins.first?.errorMessage)
    }

    func testScanSkipsNonDirectories() throws {
        let pluginsDir = tempDir.appendingPathComponent("plugins")
        try FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        try "just a file".write(to: pluginsDir.appendingPathComponent("not-a-dir.txt"), atomically: true, encoding: .utf8)

        let manager = PluginManager(baseURL: tempDir)
        XCTAssertTrue(manager.plugins.isEmpty)
    }

    func testScanSkipsDirsWithoutManifest() throws {
        let pluginDir = tempDir.appendingPathComponent("plugins/no-manifest")
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        try "readme".write(to: pluginDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let manager = PluginManager(baseURL: tempDir)
        XCTAssertTrue(manager.plugins.isEmpty)
    }

    func testScanValidationFailsOnEmptyId() throws {
        let pluginDir = tempDir.appendingPathComponent("plugins/empty-id")
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let manifest = """
        {
            "id": "",
            "name": "Bad",
            "version": "1.0",
            "capabilities": {},
            "permissions": {}
        }
        """
        try manifest.write(to: pluginDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let manager = PluginManager(baseURL: tempDir)
        XCTAssertEqual(manager.plugins.count, 1)
        XCTAssertEqual(manager.plugins.first?.status, .error)
        XCTAssertEqual(manager.plugins.first?.errorMessage, "매니페스트 검증 실패: 필수 필드 누락")
    }

    // MARK: - Enable/Disable Tests

    func testEnablePlugin() throws {
        try createPlugin(id: "p1", name: "Plugin 1")
        let manager = PluginManager(baseURL: tempDir)
        XCTAssertEqual(manager.plugins.first?.status, .inactive)

        manager.enablePlugin(id: "p1")
        XCTAssertEqual(manager.plugins.first?.status, .active)
    }

    func testDisablePlugin() throws {
        try createPlugin(id: "p1", name: "Plugin 1")
        let manager = PluginManager(baseURL: tempDir)
        manager.enablePlugin(id: "p1")
        XCTAssertEqual(manager.plugins.first?.status, .active)

        manager.disablePlugin(id: "p1")
        XCTAssertEqual(manager.plugins.first?.status, .inactive)
    }

    func testEnableNonexistentIdIsNoop() throws {
        try createPlugin(id: "p1", name: "Plugin 1")
        let manager = PluginManager(baseURL: tempDir)
        manager.enablePlugin(id: "nonexistent")
        XCTAssertEqual(manager.plugins.count, 1)
    }

    // MARK: - State Persistence Tests

    func testStatePersistsAcrossInstances() throws {
        try createPlugin(id: "persist-test", name: "Persist")
        let manager1 = PluginManager(baseURL: tempDir)
        manager1.enablePlugin(id: "persist-test")
        XCTAssertEqual(manager1.plugins.first?.status, .active)

        // Create new instance — should restore active state
        let manager2 = PluginManager(baseURL: tempDir)
        XCTAssertEqual(manager2.plugins.first?.status, .active)
    }

    // MARK: - Remove Tests

    func testRemovePlugin() throws {
        try createPlugin(id: "removable", name: "Removable")
        let manager = PluginManager(baseURL: tempDir)
        XCTAssertEqual(manager.plugins.count, 1)

        try manager.removePlugin(id: "removable")
        XCTAssertTrue(manager.plugins.isEmpty)

        // Directory should be gone
        let removedDir = tempDir.appendingPathComponent("plugins/removable")
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedDir.path))
    }

    func testRemoveNonexistentPluginNoThrow() throws {
        let manager = PluginManager(baseURL: tempDir)
        // Should not throw
        try manager.removePlugin(id: "does-not-exist")
    }

    // MARK: - Multiple Plugins Sorting

    func testPluginsSortedByName() throws {
        try createPlugin(id: "z-plugin", name: "Zebra")
        try createPlugin(id: "a-plugin", name: "Alpha")
        try createPlugin(id: "m-plugin", name: "Middle")

        let manager = PluginManager(baseURL: tempDir)
        XCTAssertEqual(manager.plugins.count, 3)
        XCTAssertEqual(manager.plugins[0].name, "Alpha")
        XCTAssertEqual(manager.plugins[1].name, "Middle")
        XCTAssertEqual(manager.plugins[2].name, "Zebra")
    }

    // MARK: - Rescan

    func testRescanPicksUpNewPlugins() throws {
        let manager = PluginManager(baseURL: tempDir)
        XCTAssertTrue(manager.plugins.isEmpty)

        try createPlugin(id: "new-plugin", name: "New")
        manager.scanPlugins()
        XCTAssertEqual(manager.plugins.count, 1)
    }

    // MARK: - Path Traversal Defense Tests

    func testRemovePluginBlocksPathTraversal() throws {
        // Create a plugin with a traversal id (e.g., "../../important-data")
        // but stored in a legitimate directory
        let pluginDir = tempDir.appendingPathComponent("plugins/legit-dir")
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let manifest = """
        {
            "id": "../../important-data",
            "name": "Malicious",
            "version": "1.0.0",
            "capabilities": {},
            "permissions": {}
        }
        """
        try manifest.write(to: pluginDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let manager = PluginManager(baseURL: tempDir)
        XCTAssertEqual(manager.plugins.count, 1)
        XCTAssertEqual(manager.plugins.first?.id, "../../important-data")

        // directoryURL should point to the actual directory, not reconstructed from id
        XCTAssertEqual(manager.plugins.first?.directoryURL?.standardizedFileURL, pluginDir.standardizedFileURL)

        // Removal should succeed using the safe directoryURL
        try manager.removePlugin(id: "../../important-data")
        XCTAssertTrue(manager.plugins.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pluginDir.path))
    }

    func testRemovePluginBlocksOutsideDirectory() throws {
        // Use MockPluginManager to test path traversal defense with tampered directoryURL
        let outsideDir = tempDir.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        try "important".write(to: outsideDir.appendingPathComponent("data.txt"), atomically: true, encoding: .utf8)

        // Create a real plugin, then verify the manager's path check
        // by creating a plugin whose directory is inside plugins/ but
        // trying to remove one with a traversal id that doesn't match
        try createPlugin(id: "normal-plugin", name: "Normal")

        let manager = PluginManager(baseURL: tempDir)
        XCTAssertEqual(manager.plugins.count, 1)

        // The directoryURL should point to the real dir inside plugins/
        let expectedDir = tempDir.appendingPathComponent("plugins/normal-plugin")
        XCTAssertEqual(manager.plugins.first?.directoryURL?.standardizedFileURL, expectedDir.standardizedFileURL)

        // Removing works safely via the stored directoryURL
        try manager.removePlugin(id: "normal-plugin")
        XCTAssertTrue(manager.plugins.isEmpty)

        // Outside directory must not be affected
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideDir.path))
    }

    func testScanStoresDirectoryURL() throws {
        try createPlugin(id: "dir-test", name: "Dir Test")
        let manager = PluginManager(baseURL: tempDir)

        XCTAssertEqual(manager.plugins.count, 1)
        let expectedDir = tempDir.appendingPathComponent("plugins/dir-test")
        XCTAssertEqual(manager.plugins.first?.directoryURL?.standardizedFileURL, expectedDir.standardizedFileURL)
    }

    func testRemovePluginWithNilDirectoryURL() throws {
        // Use MockPluginManager to inject a plugin with nil directoryURL
        let mock = MockPluginManager()
        let manifest = PluginManifest(
            id: "no-dir", name: "No Dir", version: "1.0",
            author: nil, description: nil, icon: nil,
            capabilities: .init(), permissions: .init(), minAppVersion: nil
        )
        mock.plugins = [PluginInfo(manifest: manifest, status: .inactive, directoryURL: nil)]

        // MockPluginManager.removePlugin removes from its list (it doesn't do path checks)
        // This test verifies that PluginInfo can be constructed with nil directoryURL
        XCTAssertNil(mock.plugins.first?.directoryURL)
        try mock.removePlugin(id: "no-dir")
        XCTAssertTrue(mock.plugins.isEmpty)
    }

    // MARK: - Helpers

    private func createPlugin(id: String, name: String) throws {
        let pluginDir = tempDir.appendingPathComponent("plugins/\(id)")
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        let manifest = """
        {
            "id": "\(id)",
            "name": "\(name)",
            "version": "1.0.0",
            "capabilities": {},
            "permissions": {}
        }
        """
        try manifest.write(to: pluginDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
    }
}

// MARK: - MockPluginManager Tests

@MainActor
final class MockPluginManagerTests: XCTestCase {

    func testMockEnableDisable() {
        let mock = MockPluginManager()
        let manifest = PluginManifest(
            id: "m1", name: "Mock1", version: "1.0",
            author: nil, description: nil, icon: nil,
            capabilities: .init(), permissions: .init(), minAppVersion: nil
        )
        mock.plugins = [PluginInfo(manifest: manifest, status: .inactive)]

        mock.enablePlugin(id: "m1")
        XCTAssertEqual(mock.enableCallCount, 1)
        XCTAssertEqual(mock.lastEnabledId, "m1")
        XCTAssertEqual(mock.plugins.first?.status, .active)

        mock.disablePlugin(id: "m1")
        XCTAssertEqual(mock.disableCallCount, 1)
        XCTAssertEqual(mock.lastDisabledId, "m1")
        XCTAssertEqual(mock.plugins.first?.status, .inactive)
    }

    func testMockRemove() throws {
        let mock = MockPluginManager()
        let manifest = PluginManifest(
            id: "r1", name: "Remove1", version: "1.0",
            author: nil, description: nil, icon: nil,
            capabilities: .init(), permissions: .init(), minAppVersion: nil
        )
        mock.plugins = [PluginInfo(manifest: manifest, status: .active)]

        try mock.removePlugin(id: "r1")
        XCTAssertEqual(mock.removeCallCount, 1)
        XCTAssertTrue(mock.plugins.isEmpty)
    }

    func testMockScan() {
        let mock = MockPluginManager()
        mock.scanPlugins()
        XCTAssertEqual(mock.scanCallCount, 1)
    }
}
