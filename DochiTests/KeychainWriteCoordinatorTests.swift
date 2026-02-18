import XCTest
@testable import Dochi

@MainActor
final class KeychainWriteCoordinatorTests: XCTestCase {
    func testSaveRequiredValueSuccess() {
        let keychain = MockKeychainService()
        let result = KeychainWriteCoordinator.saveRequiredValue(
            "sk-test",
            account: "openai_api_key",
            keychain: keychain
        )

        switch result {
        case .success:
            XCTAssertEqual(keychain.load(account: "openai_api_key"), "sk-test")
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }
    }

    func testSaveRequiredValueFailure() {
        let keychain = FailingKeychainService(failOnSave: true)
        let result = KeychainWriteCoordinator.saveRequiredValue(
            "sk-test",
            account: "openai_api_key",
            keychain: keychain
        )

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure:
            XCTAssertTrue(true)
        }
    }

    func testSaveTrimmedTokenSavesTrimmedValue() {
        let keychain = MockKeychainService()
        let result = KeychainWriteCoordinator.saveTrimmedToken(
            "  bot-token  ",
            account: "telegram_bot_token",
            keychain: keychain
        )

        switch result {
        case .success(let hasToken):
            XCTAssertTrue(hasToken)
            XCTAssertEqual(keychain.load(account: "telegram_bot_token"), "bot-token")
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }
    }

    func testSaveTrimmedTokenDeletesOnEmpty() {
        let keychain = MockKeychainService()
        try? keychain.save(account: "telegram_bot_token", value: "existing")

        let result = KeychainWriteCoordinator.saveTrimmedToken(
            "   ",
            account: "telegram_bot_token",
            keychain: keychain
        )

        switch result {
        case .success(let hasToken):
            XCTAssertFalse(hasToken)
            XCTAssertNil(keychain.load(account: "telegram_bot_token"))
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }
    }

    func testSaveTrimmedTokenFailureOnDelete() {
        let keychain = FailingKeychainService(failOnDelete: true)
        let result = KeychainWriteCoordinator.saveTrimmedToken(
            "",
            account: "telegram_bot_token",
            keychain: keychain
        )

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure:
            XCTAssertTrue(true)
        }
    }
}

@MainActor
private final class FailingKeychainService: KeychainServiceProtocol {
    let failOnSave: Bool
    let failOnDelete: Bool

    init(failOnSave: Bool = false, failOnDelete: Bool = false) {
        self.failOnSave = failOnSave
        self.failOnDelete = failOnDelete
    }

    func save(account: String, value: String) throws {
        if failOnSave {
            throw NSError(domain: "FailingKeychainService", code: 1, userInfo: [NSLocalizedDescriptionKey: "save failed"])
        }
    }

    func load(account: String) -> String? { nil }

    func delete(account: String) throws {
        if failOnDelete {
            throw NSError(domain: "FailingKeychainService", code: 2, userInfo: [NSLocalizedDescriptionKey: "delete failed"])
        }
    }
}
