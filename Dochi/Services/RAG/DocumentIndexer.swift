import Foundation
import PDFKit

/// 문서를 파싱, 청킹, 임베딩하여 VectorStore에 저장하는 오케스트레이터.
@MainActor
@Observable
final class DocumentIndexer {
    private let vectorStore: VectorStore
    private let embeddingService: EmbeddingService
    private let settings: AppSettings

    /// 현재 인덱싱 상태
    private(set) var indexingState: RAGIndexingState = .idle

    /// 인덱싱된 문서 목록
    var documents: [RAGDocument] {
        vectorStore.loadDocuments()
    }

    /// 기존 인덱스에 저장된 임베딩 벡터의 차원 수 (없으면 nil)
    var storedEmbeddingDimension: Int? {
        vectorStore.storedEmbeddingDimension()
    }

    init(vectorStore: VectorStore, embeddingService: EmbeddingService, settings: AppSettings) {
        self.vectorStore = vectorStore
        self.embeddingService = embeddingService
        self.settings = settings
    }

    // MARK: - File Parsing

    /// 파일 URL에서 텍스트 추출
    func extractText(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        guard let fileType = RAGFileType.from(extension: ext) else {
            throw DocumentIndexerError.unsupportedFileType(ext)
        }

        switch fileType {
        case .pdf:
            return try extractPDFText(from: url)
        case .markdown, .text:
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    private func extractPDFText(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw DocumentIndexerError.pdfParsingFailed
        }

        var text = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let pageText = page.string {
                text += pageText + "\n\n"
            }
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DocumentIndexerError.emptyDocument
        }
        return trimmed
    }

    // MARK: - Indexing

    /// 단일 파일을 인덱싱
    func indexFile(at url: URL) async throws {
        let fileName = url.lastPathComponent
        let filePath = url.path
        let ext = url.pathExtension.lowercased()

        guard let fileType = RAGFileType.from(extension: ext) else {
            throw DocumentIndexerError.unsupportedFileType(ext)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
        let fileSize = attributes[.size] as? Int64 ?? 0

        // Create or update document record
        let docId = existingDocumentId(filePath: filePath) ?? UUID()
        var doc = RAGDocument(
            id: docId,
            fileName: fileName,
            filePath: filePath,
            fileSize: fileSize,
            fileType: fileType,
            indexingStatus: .indexing
        )
        vectorStore.upsertDocument(doc)
        indexingState = .indexing(progress: 0.1, fileName: fileName)

        do {
            // 1. Extract text
            let text = try extractText(from: url)
            indexingState = .indexing(progress: 0.3, fileName: fileName)

            // 2. Split into chunks
            let splitter = ChunkSplitter(
                maxChunkSize: settings.ragChunkSize,
                overlapSize: settings.ragChunkOverlap
            )

            let chunks: [ChunkSplitter.Chunk]
            if fileType == .markdown {
                chunks = splitter.splitMarkdown(text)
            } else {
                chunks = splitter.splitPlainText(text)
            }

            guard !chunks.isEmpty else {
                throw DocumentIndexerError.emptyDocument
            }

            indexingState = .indexing(progress: 0.5, fileName: fileName)

            // 3. Generate embeddings
            let chunkTexts = chunks.map(\.content)
            let embeddings = try await embeddingService.embedBatch(chunkTexts)
            indexingState = .indexing(progress: 0.8, fileName: fileName)

            // 4. Delete old chunks for this document
            vectorStore.deleteChunks(documentId: docId)

            // 5. Store chunks with embeddings
            let chunkRecords = zip(chunks, embeddings).map { chunk, embedding in
                (id: UUID(), documentId: docId, content: chunk.content, sectionTitle: chunk.sectionTitle, embedding: embedding, position: chunk.position)
            }
            vectorStore.insertChunks(chunkRecords)

            // 6. Update document status
            doc.chunkCount = chunks.count
            doc.indexingStatus = .indexed
            doc.lastIndexedAt = Date()
            doc.errorMessage = nil
            vectorStore.upsertDocument(doc)

            indexingState = .completed(documentCount: 1, chunkCount: chunks.count)
            Log.storage.info("RAG: Indexed \(fileName) — \(chunks.count) chunks")

        } catch {
            doc.indexingStatus = .failed
            doc.errorMessage = error.localizedDescription
            vectorStore.upsertDocument(doc)
            indexingState = .failed(error: error.localizedDescription)
            Log.storage.error("RAG: Failed to index \(fileName): \(error.localizedDescription)")
            throw error
        }
    }

    /// 여러 파일을 인덱싱 (진행률 표시)
    func indexFiles(at urls: [URL]) async {
        var totalDocs = 0
        var totalChunks = 0

        for (index, url) in urls.enumerated() {
            let progress = Double(index) / Double(urls.count)
            indexingState = .indexing(progress: progress, fileName: url.lastPathComponent)

            do {
                try await indexFile(at: url)
                totalDocs += 1
                if case .completed(_, let chunks) = indexingState {
                    totalChunks += chunks
                }
            } catch {
                Log.storage.error("RAG: Skipping \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        indexingState = .completed(documentCount: totalDocs, chunkCount: totalChunks)
    }

    /// 폴더 내 모든 지원 파일을 인덱싱
    func indexFolder(at url: URL) async {
        let supportedExtensions = RAGFileType.allCases.flatMap(\.extensions)
        let fileURLs = collectSupportedFiles(at: url, extensions: supportedExtensions)

        guard !fileURLs.isEmpty else {
            indexingState = .failed(error: "지원되는 파일이 없습니다.")
            return
        }

        await indexFiles(at: fileURLs)
    }

    /// 폴더 내 지원 파일 수집 (동기)
    private func collectSupportedFiles(at url: URL, extensions: [String]) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }

        var result: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            if extensions.contains(ext) {
                result.append(fileURL)
            }
        }
        return result
    }

    /// 문서 삭제
    func removeDocument(id: UUID) {
        vectorStore.deleteDocument(id: id)
        Log.storage.info("RAG: Removed document \(id.uuidString)")
    }

    /// 전체 인덱스 초기화
    func clearAll() {
        vectorStore.clear()
        indexingState = .idle
        Log.storage.info("RAG: Cleared all documents and chunks")
    }

    /// 모든 문서 재인덱싱
    func reindexAll() async {
        let docs = documents
        guard !docs.isEmpty else {
            indexingState = .idle
            return
        }

        let urls = docs.compactMap { URL(fileURLWithPath: $0.filePath) }
        await indexFiles(at: urls)
    }

    // MARK: - Search

    /// 쿼리 텍스트로 벡터 검색
    func search(query: String, topK: Int? = nil, minSimilarity: Double? = nil) async throws -> [RAGSearchResult] {
        let queryEmbedding = try await embeddingService.embed(query)
        let k = topK ?? settings.ragTopK
        let sim = minSimilarity ?? settings.ragMinSimilarity
        return vectorStore.search(queryEmbedding: queryEmbedding, topK: k, minSimilarity: sim)
    }

    // MARK: - Helpers

    /// 파일 경로로 기존 문서 ID 조회
    private func existingDocumentId(filePath: String) -> UUID? {
        return documents.first(where: { $0.filePath == filePath })?.id
    }
}

// MARK: - DocumentIndexerError

enum DocumentIndexerError: Error, LocalizedError {
    case unsupportedFileType(String)
    case pdfParsingFailed
    case emptyDocument

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let ext):
            return "지원되지 않는 파일 형식입니다: .\(ext)"
        case .pdfParsingFailed:
            return "PDF 파일을 읽을 수 없습니다."
        case .emptyDocument:
            return "문서에 텍스트가 없습니다."
        }
    }
}
