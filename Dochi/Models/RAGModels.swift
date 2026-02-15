import Foundation

// MARK: - RAGFileType

enum RAGFileType: String, Codable, Sendable, CaseIterable {
    case pdf
    case markdown
    case text

    var displayName: String {
        switch self {
        case .pdf: return "PDF"
        case .markdown: return "Markdown"
        case .text: return "텍스트"
        }
    }

    var extensions: [String] {
        switch self {
        case .pdf: return ["pdf"]
        case .markdown: return ["md", "markdown"]
        case .text: return ["txt", "text"]
        }
    }

    static func from(extension ext: String) -> RAGFileType? {
        let lower = ext.lowercased()
        return allCases.first { $0.extensions.contains(lower) }
    }
}

// MARK: - RAGIndexingStatus

enum RAGIndexingStatus: String, Codable, Sendable {
    case pending
    case indexing
    case indexed
    case failed
    case outdated

    var displayName: String {
        switch self {
        case .pending: return "대기 중"
        case .indexing: return "인덱싱 중"
        case .indexed: return "완료"
        case .failed: return "실패"
        case .outdated: return "갱신 필요"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .indexing: return "arrow.triangle.2.circlepath"
        case .indexed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .outdated: return "exclamationmark.triangle"
        }
    }
}

// MARK: - RAGDocument

struct RAGDocument: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let fileName: String
    let filePath: String
    let fileSize: Int64
    let fileType: RAGFileType
    var chunkCount: Int
    var indexingStatus: RAGIndexingStatus
    var lastIndexedAt: Date?
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        fileName: String,
        filePath: String,
        fileSize: Int64,
        fileType: RAGFileType,
        chunkCount: Int = 0,
        indexingStatus: RAGIndexingStatus = .pending,
        lastIndexedAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.fileSize = fileSize
        self.fileType = fileType
        self.chunkCount = chunkCount
        self.indexingStatus = indexingStatus
        self.lastIndexedAt = lastIndexedAt
        self.errorMessage = errorMessage
    }

    var fileSizeDisplay: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

// MARK: - RAGSearchResult

struct RAGSearchResult: Identifiable, Sendable {
    let id: UUID
    let documentId: UUID
    let fileName: String
    let sectionTitle: String?
    let content: String
    let similarity: Double
    let position: Int

    var similarityPercent: String {
        String(format: "%.0f%%", similarity * 100)
    }
}

// MARK: - RAGReference

struct RAGReference: Codable, Sendable, Equatable {
    let documentId: String
    let fileName: String
    let sectionTitle: String?
    let similarity: Double
    let snippetPreview: String
}

// MARK: - RAGContextInfo

struct RAGContextInfo: Codable, Sendable, Equatable {
    let references: [RAGReference]
    let totalCharsInjected: Int

    var referenceCount: Int { references.count }

    var hasReferences: Bool { !references.isEmpty }

    /// 대략적인 토큰 수 추정 (한국어 기준 ~2자/토큰)
    var estimatedTokens: Int { totalCharsInjected / 2 }
}

// MARK: - RAGIndexingState

enum RAGIndexingState: Sendable, Equatable {
    case idle
    case indexing(progress: Double, fileName: String)
    case completed(documentCount: Int, chunkCount: Int)
    case failed(error: String)

    var isIndexing: Bool {
        if case .indexing = self { return true }
        return false
    }

    var displayText: String {
        switch self {
        case .idle:
            return "대기"
        case .indexing(let progress, let fileName):
            return "\(fileName) 인덱싱 중... \(Int(progress * 100))%"
        case .completed(let docCount, let chunkCount):
            return "완료: 문서 \(docCount)건, 청크 \(chunkCount)건"
        case .failed(let error):
            return "실패: \(error)"
        }
    }
}
