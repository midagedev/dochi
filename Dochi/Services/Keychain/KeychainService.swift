import Foundation
import Security
import os

@MainActor
final class KeychainService: KeychainServiceProtocol {
    private let service = "com.hckim.dochi"

    func save(account: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        let itemQuery = query(account: account)
        let updateStatus = SecItemUpdate(
            itemQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        let status: OSStatus
        if updateStatus == errSecItemNotFound {
            var newItem = itemQuery
            newItem[kSecValueData as String] = data
            status = SecItemAdd(newItem as CFDictionary, nil)
        } else {
            status = updateStatus
        }

        guard status == errSecSuccess else {
            Log.storage.error("Keychain save failed for \(account): \(status)")
            throw KeychainError.saveFailed(status)
        }
    }

    func load(account: String) -> String? {
        var lookup = query(account: account)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(account: String) throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            Log.storage.error("Keychain delete failed for \(account): \(status)")
            throw KeychainError.deleteFailed(status)
        }
    }

    private func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

enum KeychainError: Error {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
}
