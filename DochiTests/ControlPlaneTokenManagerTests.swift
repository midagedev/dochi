import XCTest
import Darwin
@testable import Dochi

final class ControlPlaneTokenManagerTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private var tokenURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let suffix = String(UUID().uuidString.prefix(8))
        tempDirectoryURL = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("dc-token-\(suffix)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        tokenURL = tempDirectoryURL.appendingPathComponent("control-plane.token")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
        try super.tearDownWithError()
    }

    func testRotateChangesTokenAndPersistsToFile() throws {
        let manager = ControlPlaneTokenManager(tokenFileURL: tokenURL)
        let first = manager.currentToken()
        let second = manager.rotate()

        XCTAssertNotEqual(first, second)
        let fileToken = try String(contentsOf: tokenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(fileToken, second)
    }

    func testValidateChecksCurrentToken() {
        let manager = ControlPlaneTokenManager(tokenFileURL: tokenURL)
        let current = manager.currentToken()
        let old = manager.rotate()

        XCTAssertTrue(manager.validate(old))
        XCTAssertFalse(manager.validate(current))
        XCTAssertFalse(manager.validate(nil))
        XCTAssertFalse(manager.validate(""))
    }

    func testPersistedTokenFilePermissionIs0600() throws {
        _ = ControlPlaneTokenManager(tokenFileURL: tokenURL)

        var fileStat = stat()
        let result = tokenURL.path.withCString { cString in
            stat(cString, &fileStat)
        }
        XCTAssertEqual(result, 0)
        XCTAssertEqual(fileStat.st_mode & 0o777, 0o600)
    }

    func testRotateKeepsCurrentTokenWhenPersistFails() {
        let invalidTokenURL = URL(fileURLWithPath: "/dev/null/control-plane.token")
        let manager = ControlPlaneTokenManager(tokenFileURL: invalidTokenURL)
        let beforeRotate = manager.currentToken()

        let rotated = manager.rotate()

        XCTAssertEqual(rotated, beforeRotate)
        XCTAssertEqual(manager.currentToken(), beforeRotate)
    }
}
