import Foundation
import os

/// 프롬프트 파일 관리 서비스
/// ~/Library/Application Support/Dochi/ 디렉토리의 md 파일들을 관리
/// - system.md: 페르소나 + 행동 지침 (수동 편집)
/// - memory.md: 사용자 기억 (자동 누적)
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
        try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    private var systemFileURL: URL {
        baseDir.appendingPathComponent("system.md")
    }

    private var memoryFileURL: URL {
        baseDir.appendingPathComponent("memory.md")
    }

    // MARK: - System (페르소나 + 행동 지침)

    func loadSystem() -> String {
        (try? String(contentsOf: systemFileURL, encoding: .utf8)) ?? ""
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

    // MARK: - Memory (사용자 기억)

    func loadMemory() -> String {
        (try? String(contentsOf: memoryFileURL, encoding: .utf8)) ?? ""
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
        (try? fileManager.attributesOfItem(atPath: memoryFileURL.path)[.size] as? Int) ?? 0
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
