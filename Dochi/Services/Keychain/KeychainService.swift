import Foundation
import Security
import os

@MainActor
final class KeychainService: KeychainServiceProtocol {
    private let service = "com.hckim.dochi"

    func save(account: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            Log.storage.error("Keychain save failed for \(account): \(status)")
            throw KeychainError.saveFailed(status)
        }
    }

    func load(account: String) -> String? {
        // Try data protection keychain first
        let dpQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true
        ]
        var result: AnyObject?
        let dpStatus = SecItemCopyMatching(dpQuery as CFDictionary, &result)
        if dpStatus == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }

        // Fallback: try legacy keychain (for migration of pre-existing keys)
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        result = nil
        let legacyStatus = SecItemCopyMatching(legacyQuery as CFDictionary, &result)
        if legacyStatus == errSecSuccess, let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            // Migrate to data protection keychain
            try? save(account: account, value: value)
            // Delete from legacy keychain
            let deleteLegacy: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(deleteLegacy as CFDictionary)
            Log.storage.info("Migrated keychain item '\(account)' to data protection keychain")
            return value
        }

        return nil
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            Log.storage.error("Keychain delete failed for \(account): \(status)")
            throw KeychainError.deleteFailed(status)
        }
    }
}

enum KeychainError: Error {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
}
