import Foundation
import Auth

/// File-based AuthLocalStorage for Supabase, avoiding macOS keychain prompts.
struct FileAuthStorage: AuthLocalStorage {
    private let dirURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.dirURL = appSupport.appendingPathComponent("Dochi/supabase-auth")
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: dirURL.path
        )
    }

    func store(key: String, value: Data) throws {
        let url = dirURL.appendingPathComponent(safeFileName(key))
        try value.write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    func retrieve(key: String) throws -> Data? {
        let url = dirURL.appendingPathComponent(safeFileName(key))
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func remove(key: String) throws {
        let url = dirURL.appendingPathComponent(safeFileName(key))
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func safeFileName(_ key: String) -> String {
        key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
    }
}
