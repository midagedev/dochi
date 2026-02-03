import Foundation
@testable import Dochi

final class MockKeychainService: KeychainServiceProtocol {
    var storage: [String: String] = [:]

    func save(account: String, value: String) {
        storage[account] = value
    }

    func load(account: String) -> String? {
        storage[account]
    }

    func delete(account: String) {
        storage.removeValue(forKey: account)
    }
}
