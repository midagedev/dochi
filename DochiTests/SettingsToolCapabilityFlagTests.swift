import XCTest
@testable import Dochi

@MainActor
final class SettingsToolCapabilityFlagTests: XCTestCase {
    private static let flagKey = "capabilityRouterV2Enabled"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.flagKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.flagKey)
        super.tearDown()
    }

    func testSettingsListIncludesCapabilityRouterFlag() async {
        let settings = AppSettings()
        settings.capabilityRouterV2Enabled = false
        let listTool = SettingsListTool(settings: settings, keychainService: MockKeychainService())

        let result = await listTool.execute(arguments: [:])

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("capabilityRouterV2Enabled"))
    }

    func testSettingsSetAndGetCapabilityRouterFlag() async {
        let settings = AppSettings()
        let keychain = MockKeychainService()
        let setTool = SettingsSetTool(settings: settings, keychainService: keychain)
        let getTool = SettingsGetTool(settings: settings, keychainService: keychain)

        let setResult = await setTool.execute(arguments: [
            "key": "capabilityRouterV2Enabled",
            "value": "true",
        ])
        let getResult = await getTool.execute(arguments: [
            "key": "capabilityRouterV2Enabled",
        ])

        XCTAssertFalse(setResult.isError)
        XCTAssertFalse(getResult.isError)
        XCTAssertTrue(settings.capabilityRouterV2Enabled)
        XCTAssertTrue(getResult.content.contains("true"))
    }
}
