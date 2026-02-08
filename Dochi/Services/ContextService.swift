import Foundation
import os

/// 프롬프트 파일 관리 서비스
/// ~/Library/Application Support/Dochi/ 디렉토리의 md 파일들을 관리
/// - system.md: 페르소나 + 행동 지침 (수동 편집)
/// - memory.md: 사용자 기억 (레거시, fallback)
/// - family.md: 가족 공유 기억
/// - memory/{userId}.md: 개인 기억
/// - profiles.json: 사용자 프로필
final class ContextService: ContextServiceProtocol {
    private let fileManager: FileManager
    private let baseDir: URL

    init(baseDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let baseDirectory {
            self.baseDir = baseDirectory
        } else {
            let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Dochi", isDirectory: true)
            self.baseDir = dir
        }
        do {
            try fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        } catch {
            Log.storage.error("기본 디렉토리 생성 실패: \(error, privacy: .public)")
        }
        do {
            try fileManager.createDirectory(at: memoryDir, withIntermediateDirectories: true)
        } catch {
            Log.storage.error("메모리 디렉토리 생성 실패: \(error, privacy: .public)")
        }
    }

    private var systemFileURL: URL {
        baseDir.appendingPathComponent("system.md")
    }

    private var memoryFileURL: URL {
        baseDir.appendingPathComponent("memory.md")
    }

    private var familyFileURL: URL {
        baseDir.appendingPathComponent("family.md")
    }

    private var profilesFileURL: URL {
        baseDir.appendingPathComponent("profiles.json")
    }

    private var memoryDir: URL {
        baseDir.appendingPathComponent("memory", isDirectory: true)
    }

    private func userMemoryFileURL(userId: UUID) -> URL {
        memoryDir.appendingPathComponent("\(userId.uuidString).md")
    }

    // MARK: - System (페르소나 + 행동 지침)

    func loadSystem() -> String {
        do {
            return try String(contentsOf: systemFileURL, encoding: .utf8)
        } catch {
            Log.storage.debug("system.md 로드 실패 (파일 없을 수 있음): \(error, privacy: .public)")
            return ""
        }
    }

    func saveSystem(_ content: String) {
        do {
            try content.write(to: systemFileURL, atomically: true, encoding: .utf8)
        } catch {
            Log.storage.error("system.md 저장 실패: \(error, privacy: .public)")
        }
    }

    var systemPath: String {
        systemFileURL.path
    }

    // MARK: - Memory (레거시 사용자 기억)

    func loadMemory() -> String {
        do {
            return try String(contentsOf: memoryFileURL, encoding: .utf8)
        } catch {
            Log.storage.debug("memory.md 로드 실패 (파일 없을 수 있음): \(error, privacy: .public)")
            return ""
        }
    }

    func saveMemory(_ content: String) {
        do {
            try content.write(to: memoryFileURL, atomically: true, encoding: .utf8)
        } catch {
            Log.storage.error("memory.md 저장 실패: \(error, privacy: .public)")
        }
    }

    func appendMemory(_ content: String) {
        var current = loadMemory()
        if !current.isEmpty && !current.hasSuffix("\n") {
            current += "\n"
        }
        current += content
        saveMemory(current)
    }

    var memoryPath: String {
        memoryFileURL.path
    }

    var memorySize: Int {
        do {
            let attrs = try fileManager.attributesOfItem(atPath: memoryFileURL.path)
            return attrs[.size] as? Int ?? 0
        } catch {
            Log.storage.debug("memory.md 크기 조회 실패: \(error, privacy: .public)")
            return 0
        }
    }

    // MARK: - Family Memory (가족 공유 기억)

    func loadFamilyMemory() -> String {
        do {
            return try String(contentsOf: familyFileURL, encoding: .utf8)
        } catch {
            Log.storage.debug("family.md 로드 실패 (파일 없을 수 있음): \(error, privacy: .public)")
            return ""
        }
    }

    func saveFamilyMemory(_ content: String) {
        do {
            try content.write(to: familyFileURL, atomically: true, encoding: .utf8)
        } catch {
            Log.storage.error("family.md 저장 실패: \(error, privacy: .public)")
        }
    }

    func appendFamilyMemory(_ content: String) {
        var current = loadFamilyMemory()
        if !current.isEmpty && !current.hasSuffix("\n") {
            current += "\n"
        }
        current += content
        saveFamilyMemory(current)
    }

    // MARK: - User Memory (개인 기억)

    func loadUserMemory(userId: UUID) -> String {
        do {
            return try String(contentsOf: userMemoryFileURL(userId: userId), encoding: .utf8)
        } catch {
            Log.storage.debug("사용자 메모리 로드 실패 \(userId) (파일 없을 수 있음): \(error, privacy: .public)")
            return ""
        }
    }

    func saveUserMemory(userId: UUID, content: String) {
        do {
            try content.write(to: userMemoryFileURL(userId: userId), atomically: true, encoding: .utf8)
        } catch {
            Log.storage.error("사용자 메모리 저장 실패 \(userId): \(error, privacy: .public)")
        }
    }

    func appendUserMemory(userId: UUID, content: String) {
        var current = loadUserMemory(userId: userId)
        if !current.isEmpty && !current.hasSuffix("\n") {
            current += "\n"
        }
        current += content
        saveUserMemory(userId: userId, content: current)
    }

    // MARK: - Profiles (사용자 프로필)

    func loadProfiles() -> [UserProfile] {
        guard let data = try? Data(contentsOf: profilesFileURL) else {
            // 파일 없으면 프로필 미설정 상태 (정상)
            return []
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([UserProfile].self, from: data)
        } catch {
            Log.storage.error("profiles.json 로드 실패: \(error, privacy: .public)")
            return []
        }
    }

    func saveProfiles(_ profiles: [UserProfile]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(profiles)
            try data.write(to: profilesFileURL)
        } catch {
            Log.storage.error("profiles.json 저장 실패: \(error, privacy: .public)")
        }
    }

    // MARK: - Legacy (마이그레이션용)

    /// 기존 context.md → memory.md 마이그레이션
    func migrateIfNeeded() {
        let oldContextURL = baseDir.appendingPathComponent("context.md")

        // 기존 context.md가 있고 memory.md가 없으면 이동
        if fileManager.fileExists(atPath: oldContextURL.path) && !fileManager.fileExists(atPath: memoryFileURL.path) {
            do {
                try fileManager.moveItem(at: oldContextURL, to: memoryFileURL)
                Log.storage.info("context.md → memory.md 마이그레이션 완료")
            } catch {
                Log.storage.error("context.md → memory.md 마이그레이션 실패: \(error, privacy: .public)")
            }
        }
    }
}
