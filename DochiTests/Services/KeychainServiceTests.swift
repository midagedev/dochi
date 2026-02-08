import XCTest
@testable import Dochi

final class KeychainServiceTests: XCTestCase {
    var sut: KeychainService!
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut = KeychainService(baseDirectory: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        tempDir = nil
    }

    func testSaveAndLoad() {
        sut.save(account: "openai", value: "sk-test-123")

        let loaded = sut.load(account: "openai")

        XCTAssertEqual(loaded, "sk-test-123")
    }

    func testLoadNonExistentKeyReturnsNil() {
        let loaded = sut.load(account: "nonexistent")

        XCTAssertNil(loaded)
    }

    func testDeleteKey() {
        sut.save(account: "openai", value: "sk-test-123")

        sut.delete(account: "openai")
        let loaded = sut.load(account: "openai")

        XCTAssertNil(loaded)
    }

    func testUpdateExistingKey() {
        sut.save(account: "openai", value: "sk-old")

        sut.save(account: "openai", value: "sk-new")
        let loaded = sut.load(account: "openai")

        XCTAssertEqual(loaded, "sk-new")
    }

    func testMultipleAccounts() {
        sut.save(account: "openai", value: "sk-openai")
        sut.save(account: "anthropic", value: "sk-anthropic")

        XCTAssertEqual(sut.load(account: "openai"), "sk-openai")
        XCTAssertEqual(sut.load(account: "anthropic"), "sk-anthropic")
    }

    func testSaveEmptyValue() {
        sut.save(account: "openai", value: "")

        let loaded = sut.load(account: "openai")

        XCTAssertEqual(loaded, "")
    }

    func testDeleteNonExistentKeyDoesNotCrash() {
        sut.delete(account: "nonexistent")
        // Should not crash
    }
}
