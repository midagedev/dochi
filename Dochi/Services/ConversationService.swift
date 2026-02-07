import Foundation
import os

/// 대화 히스토리 저장 서비스
/// ~/Library/Application Support/Dochi/conversations/ 디렉토리에 JSON 파일로 저장
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
        try? fileManager.createDirectory(at: conversationsDir, withIntermediateDirectories: true)
    }

    private func fileURL(for id: UUID) -> URL {
        conversationsDir.appendingPathComponent("\(id.uuidString).json")
    }

    /// 전체 대화 목록 반환 (updatedAt 내림차순)
    func list() -> [Conversation] {
        guard let files = try? fileManager.contentsOfDirectory(at: conversationsDir, includingPropertiesForKeys: nil) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Conversation? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Conversation.self, from: data)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 단일 대화 로드
    func load(id: UUID) -> Conversation? {
        let url = fileURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Conversation.self, from: data)
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
