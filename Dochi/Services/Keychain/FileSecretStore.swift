import Foundation
import os

/// File-based secret storage that avoids macOS keychain access prompts.
/// Stores secrets as JSON in Application Support with restrictive file permissions.
@MainActor
final class FileSecretStore {
    static let shared = FileSecretStore()

    private let fileURL: URL
    private var cache: [String: String] = [:]

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Dochi")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent(".secrets")

        // Set restrictive permissions on the directory
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: dir.path
        )

        loadFromDisk()
    }

    func store(key: String, value: String) {
        cache[key] = value
        saveToDisk()
    }

    func retrieve(key: String) -> String? {
        cache[key]
    }

    func remove(key: String) {
        cache.removeValue(forKey: key)
        saveToDisk()
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            cache = try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            Log.storage.error("Failed to load secrets: \(error.localizedDescription)")
        }
    }

    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            // Ensure restrictive file permissions (owner read/write only)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            Log.storage.error("Failed to save secrets: \(error.localizedDescription)")
        }
    }
}
