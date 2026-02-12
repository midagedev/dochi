import Foundation
import os

/// Stores API keys and secrets using file-based storage.
/// Avoids macOS keychain access prompts that occur with development builds.
@MainActor
final class KeychainService: KeychainServiceProtocol {
    private let store = FileSecretStore.shared

    func save(account: String, value: String) throws {
        store.store(key: account, value: value)
    }

    func load(account: String) -> String? {
        store.retrieve(key: account)
    }

    func delete(account: String) throws {
        store.remove(key: account)
    }
}

enum KeychainError: Error {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
}
