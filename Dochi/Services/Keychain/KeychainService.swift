import Foundation
import Security
import os

@MainActor
final class KeychainService: KeychainServiceProtocol {
    private let service = "com.hckim.dochi"

    func save(account: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        let status = saveToKeychain(account: account, data: data)

        guard status == errSecSuccess else {
            Log.storage.error("Keychain save failed for \(account): \(status)")
            throw KeychainError.saveFailed(status)
        }
    }

    func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            Log.storage.error("Keychain delete failed for \(account): \(status)")
            throw KeychainError.deleteFailed(status)
        }
    }

    private func saveToKeychain(account: String, data: Data) -> OSStatus {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        return SecItemAdd(addQuery as CFDictionary, nil)
    }
}

enum KeychainError: Error {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
}
