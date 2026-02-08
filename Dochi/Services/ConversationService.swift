import Foundation
import os

/// 대화 히스토리 저장 서비스
/// ~/Library/Application Support/Dochi/conversations/ 디렉토리에 JSON 파일로 저장
@MainActor
final class ConversationService: ConversationServiceProtocol {
    private let fileManager: FileManager
    private let conversationsDir: URL

    init(baseDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let baseDirectory {
            self.conversationsDir = baseDirectory.appendingPathComponent("conversations", isDirectory: true)
        } else {
            let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Dochi", isDirectory: true)
                .appendingPathComponent("conversations", isDirectory: true)
            self.conversationsDir = dir
        }
        do {
            try fileManager.createDirectory(at: conversationsDir, withIntermediateDirectories: true)
        } catch {
            Log.storage.error("대화 디렉토리 생성 실패: \(error, privacy: .public)")
        }
    }

    private func fileURL(for id: UUID) -> URL {
        conversationsDir.appendingPathComponent("\(id.uuidString).json")
    }

    /// 전체 대화 목록 반환 (updatedAt 내림차순)
    func list() -> [Conversation] {
        let files: [URL]
        do {
            files = try fileManager.contentsOfDirectory(at: conversationsDir, includingPropertiesForKeys: nil)
        } catch {
            Log.storage.warning("대화 디렉토리 읽기 실패: \(error, privacy: .public)")
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Conversation? in
                do {
                    let data = try Data(contentsOf: url)
                    return try decoder.decode(Conversation.self, from: data)
                } catch {
                    Log.storage.warning("대화 파일 파싱 실패 \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
                    return nil
                }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 단일 대화 로드
    func load(id: UUID) -> Conversation? {
        let url = fileURL(for: id)
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Conversation.self, from: data)
        } catch {
            Log.storage.warning("대화 로드 실패 \(id): \(error, privacy: .public)")
            return nil
        }
    }

    /// 대화 저장
    func save(_ conversation: Conversation) {
        let url = fileURL(for: conversation.id)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(conversation)
            try data.write(to: url)
        } catch {
            Log.storage.error("대화 저장 실패 \(conversation.id): \(error, privacy: .public)")
        }
    }

    /// 대화 삭제
    func delete(id: UUID) {
        let url = fileURL(for: id)
        do {
            try fileManager.removeItem(at: url)
        } catch {
            Log.storage.error("대화 삭제 실패 \(id): \(error, privacy: .public)")
        }
    }
}
