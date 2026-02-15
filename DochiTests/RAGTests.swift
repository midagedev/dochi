import XCTest
@testable import Dochi

// MARK: - ChunkSplitter Tests

final class ChunkSplitterTests: XCTestCase {

    func testSplitPlainTextShort() {
        let splitter = ChunkSplitter(maxChunkSize: 500, overlapSize: 100)
        let text = "짧은 텍스트입니다."
        let chunks = splitter.splitPlainText(text)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first?.content, text)
        XCTAssertEqual(chunks.first?.position, 0)
        XCTAssertNil(chunks.first?.sectionTitle)
    }

    func testSplitPlainTextEmpty() {
        let splitter = ChunkSplitter(maxChunkSize: 500, overlapSize: 100)
        let chunks = splitter.splitPlainText("")
        XCTAssertTrue(chunks.isEmpty)
    }

    func testSplitPlainTextMultiParagraph() {
        // minChunkSize is 100, so use at least 100 for maxChunkSize
        let splitter = ChunkSplitter(maxChunkSize: 100, overlapSize: 10)
        // Make text long enough that multiple paragraphs won't fit in one chunk
        let para1 = String(repeating: "가", count: 60)
        let para2 = String(repeating: "나", count: 60)
        let para3 = String(repeating: "다", count: 60)
        let text = "\(para1)\n\n\(para2)\n\n\(para3)"
        let chunks = splitter.splitPlainText(text)

        XCTAssertGreaterThan(chunks.count, 1)
        // Verify positions are sequential
        for (i, chunk) in chunks.enumerated() {
            XCTAssertEqual(chunk.position, i)
        }
    }

    func testSplitMarkdownSections() {
        let splitter = ChunkSplitter(maxChunkSize: 500, overlapSize: 50)
        let text = """
        # 제목 1
        첫 번째 섹션의 내용입니다.

        ## 제목 2
        두 번째 섹션의 내용입니다.

        ### 제목 3
        세 번째 섹션의 내용입니다.
        """
        let chunks = splitter.splitMarkdown(text)

        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].sectionTitle, "제목 1")
        XCTAssertEqual(chunks[1].sectionTitle, "제목 2")
        XCTAssertEqual(chunks[2].sectionTitle, "제목 3")
    }

    func testSplitMarkdownNoHeaders() {
        let splitter = ChunkSplitter(maxChunkSize: 500, overlapSize: 50)
        let text = "헤더 없는 일반 텍스트입니다."
        let chunks = splitter.splitMarkdown(text)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertNil(chunks.first?.sectionTitle)
    }

    func testSplitIntoSections() {
        let splitter = ChunkSplitter(maxChunkSize: 500, overlapSize: 50)
        let text = """
        # 소개
        여기는 소개입니다.

        ## 본론
        여기는 본론입니다.
        """
        let sections = splitter.splitIntoSections(text)

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].title, "소개")
        XCTAssertEqual(sections[1].title, "본론")
    }

    func testOverlap() {
        // minChunkSize is 100, use a larger text
        let splitter = ChunkSplitter(maxChunkSize: 100, overlapSize: 20)
        let para1 = String(repeating: "A", count: 70)
        let para2 = String(repeating: "B", count: 70)
        let para3 = String(repeating: "C", count: 70)
        let text = "\(para1)\n\n\(para2)\n\n\(para3)"
        let chunks = splitter.splitPlainText(text)

        XCTAssertGreaterThan(chunks.count, 1)
    }

    func testMinChunkSize() {
        // maxChunkSize below 100 should be clamped to 100
        let splitter = ChunkSplitter(maxChunkSize: 10, overlapSize: 0)
        XCTAssertEqual(splitter.maxChunkSize, 100)
    }

    func testOverlapClamp() {
        // overlapSize should be clamped to maxChunkSize / 2
        let splitter = ChunkSplitter(maxChunkSize: 200, overlapSize: 200)
        XCTAssertEqual(splitter.overlapSize, 100) // 200 / 2
    }
}

// MARK: - RAGModels Tests

final class RAGModelsTests: XCTestCase {

    func testRAGFileTypeFromExtension() {
        XCTAssertEqual(RAGFileType.from(extension: "pdf"), .pdf)
        XCTAssertEqual(RAGFileType.from(extension: "PDF"), .pdf)
        XCTAssertEqual(RAGFileType.from(extension: "md"), .markdown)
        XCTAssertEqual(RAGFileType.from(extension: "markdown"), .markdown)
        XCTAssertEqual(RAGFileType.from(extension: "txt"), .text)
        XCTAssertEqual(RAGFileType.from(extension: "text"), .text)
        XCTAssertNil(RAGFileType.from(extension: "docx"))
        XCTAssertNil(RAGFileType.from(extension: "xlsx"))
    }

    func testRAGDocumentCodable() throws {
        let doc = RAGDocument(
            id: UUID(),
            fileName: "test.pdf",
            filePath: "/path/to/test.pdf",
            fileSize: 1024,
            fileType: .pdf,
            chunkCount: 10,
            indexingStatus: .indexed,
            lastIndexedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(doc)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RAGDocument.self, from: data)

        XCTAssertEqual(decoded.id, doc.id)
        XCTAssertEqual(decoded.fileName, doc.fileName)
        XCTAssertEqual(decoded.filePath, doc.filePath)
        XCTAssertEqual(decoded.fileSize, doc.fileSize)
        XCTAssertEqual(decoded.fileType, doc.fileType)
        XCTAssertEqual(decoded.chunkCount, doc.chunkCount)
        XCTAssertEqual(decoded.indexingStatus, doc.indexingStatus)
    }

    func testRAGContextInfoCodable() throws {
        let info = RAGContextInfo(
            references: [
                RAGReference(
                    documentId: UUID().uuidString,
                    fileName: "test.md",
                    sectionTitle: "Introduction",
                    similarity: 0.85,
                    snippetPreview: "Preview text..."
                )
            ],
            totalCharsInjected: 500
        )

        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(RAGContextInfo.self, from: data)

        XCTAssertEqual(decoded.referenceCount, 1)
        XCTAssertEqual(decoded.totalCharsInjected, 500)
        XCTAssertTrue(decoded.hasReferences)
        XCTAssertEqual(decoded.estimatedTokens, 250)
    }

    func testRAGContextInfoEmpty() {
        let info = RAGContextInfo(references: [], totalCharsInjected: 0)
        XCTAssertFalse(info.hasReferences)
        XCTAssertEqual(info.referenceCount, 0)
    }

    func testRAGSearchResultSimilarityPercent() {
        let result = RAGSearchResult(
            id: UUID(),
            documentId: UUID(),
            fileName: "test.md",
            sectionTitle: nil,
            content: "content",
            similarity: 0.856,
            position: 0
        )
        XCTAssertEqual(result.similarityPercent, "86%")
    }

    func testRAGIndexingStateDisplayText() {
        XCTAssertEqual(RAGIndexingState.idle.displayText, "대기")
        XCTAssertEqual(RAGIndexingState.indexing(progress: 0.5, fileName: "test.pdf").displayText, "test.pdf 인덱싱 중... 50%")
        XCTAssertEqual(RAGIndexingState.completed(documentCount: 3, chunkCount: 15).displayText, "완료: 문서 3건, 청크 15건")
        XCTAssertEqual(RAGIndexingState.failed(error: "API 오류").displayText, "실패: API 오류")
    }

    func testRAGIndexingStateIsIndexing() {
        XCTAssertFalse(RAGIndexingState.idle.isIndexing)
        XCTAssertTrue(RAGIndexingState.indexing(progress: 0.5, fileName: "test").isIndexing)
        XCTAssertFalse(RAGIndexingState.completed(documentCount: 1, chunkCount: 5).isIndexing)
        XCTAssertFalse(RAGIndexingState.failed(error: "err").isIndexing)
    }

    func testRAGDocumentFileSizeDisplay() {
        let doc = RAGDocument(
            fileName: "test.pdf",
            filePath: "/path",
            fileSize: 1024 * 1024,
            fileType: .pdf
        )
        // ByteCountFormatter gives locale-dependent string, just check non-empty
        XCTAssertFalse(doc.fileSizeDisplay.isEmpty)
    }

    func testRAGIndexingStatusProperties() {
        for status in [RAGIndexingStatus.pending, .indexing, .indexed, .failed, .outdated] {
            XCTAssertFalse(status.displayName.isEmpty)
            XCTAssertFalse(status.icon.isEmpty)
        }
    }

    func testRAGFileTypeProperties() {
        for fileType in RAGFileType.allCases {
            XCTAssertFalse(fileType.displayName.isEmpty)
            XCTAssertFalse(fileType.extensions.isEmpty)
        }
    }
}

// MARK: - Cosine Similarity Tests

final class CosineSimilarityTests: XCTestCase {

    func testIdenticalVectors() {
        let a: [Float] = [1, 0, 0]
        let result = cosineSimilarity(a, a)
        XCTAssertEqual(result, 1.0, accuracy: 0.001)
    }

    func testOrthogonalVectors() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [0, 1, 0]
        let result = cosineSimilarity(a, b)
        XCTAssertEqual(result, 0.0, accuracy: 0.001)
    }

    func testOppositeVectors() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [-1, 0, 0]
        let result = cosineSimilarity(a, b)
        XCTAssertEqual(result, -1.0, accuracy: 0.001)
    }

    func testSimilarVectors() {
        let a: [Float] = [1, 2, 3]
        let b: [Float] = [1, 2, 3.1]
        let result = cosineSimilarity(a, b)
        XCTAssertGreaterThan(result, 0.99)
    }

    func testEmptyVectors() {
        let result = cosineSimilarity([], [])
        XCTAssertEqual(result, 0.0)
    }

    func testDifferentLengthVectors() {
        let a: [Float] = [1, 2]
        let b: [Float] = [1, 2, 3]
        let result = cosineSimilarity(a, b)
        XCTAssertEqual(result, 0.0)
    }

    func testZeroVector() {
        let a: [Float] = [0, 0, 0]
        let b: [Float] = [1, 2, 3]
        let result = cosineSimilarity(a, b)
        XCTAssertEqual(result, 0.0)
    }
}

// MARK: - VectorStore Tests

@MainActor
final class VectorStoreTests: XCTestCase {

    private func makeTempStore() -> VectorStore {
        let tempDir = NSTemporaryDirectory() + "dochi_test_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir + "/vectors.sqlite"
        return VectorStore(dbPath: dbPath)
    }

    func testUpsertAndLoadDocuments() {
        let store = makeTempStore()
        let doc = RAGDocument(
            fileName: "test.md",
            filePath: "/tmp/test.md",
            fileSize: 1024,
            fileType: .markdown,
            chunkCount: 5,
            indexingStatus: .indexed,
            lastIndexedAt: Date()
        )

        store.upsertDocument(doc)
        let loaded = store.loadDocuments()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.fileName, "test.md")
        XCTAssertEqual(loaded.first?.chunkCount, 5)
        XCTAssertEqual(loaded.first?.indexingStatus, .indexed)
    }

    func testDeleteDocument() {
        let store = makeTempStore()
        let doc = RAGDocument(
            fileName: "test.md",
            filePath: "/tmp/test.md",
            fileSize: 1024,
            fileType: .markdown,
            indexingStatus: .indexed
        )
        store.upsertDocument(doc)

        XCTAssertEqual(store.loadDocuments().count, 1)

        store.deleteDocument(id: doc.id)

        XCTAssertEqual(store.loadDocuments().count, 0)
    }

    func testInsertChunksAndSearch() {
        let store = makeTempStore()
        let docId = UUID()
        let doc = RAGDocument(
            id: docId,
            fileName: "test.md",
            filePath: "/tmp/test.md",
            fileSize: 1024,
            fileType: .markdown,
            chunkCount: 2,
            indexingStatus: .indexed
        )
        store.upsertDocument(doc)

        // Create small embeddings for testing (3 dimensions)
        let chunk1Embedding: [Float] = [1.0, 0.0, 0.0]
        let chunk2Embedding: [Float] = [0.0, 1.0, 0.0]

        store.insertChunks([
            (id: UUID(), documentId: docId, content: "첫 번째 청크", sectionTitle: "섹션 1", embedding: chunk1Embedding, position: 0),
            (id: UUID(), documentId: docId, content: "두 번째 청크", sectionTitle: "섹션 2", embedding: chunk2Embedding, position: 1),
        ])

        // Search with query similar to chunk1
        let queryEmbedding: [Float] = [0.9, 0.1, 0.0]
        let results = store.search(queryEmbedding: queryEmbedding, topK: 2, minSimilarity: 0.0)

        XCTAssertEqual(results.count, 2)
        // First result should be chunk1 (more similar)
        XCTAssertEqual(results.first?.content, "첫 번째 청크")
        XCTAssertEqual(results.first?.fileName, "test.md")
    }

    func testSearchMinSimilarity() {
        let store = makeTempStore()
        let docId = UUID()
        let doc = RAGDocument(
            id: docId,
            fileName: "test.md",
            filePath: "/tmp/test.md",
            fileSize: 1024,
            fileType: .markdown,
            chunkCount: 1,
            indexingStatus: .indexed
        )
        store.upsertDocument(doc)

        let embedding: [Float] = [1.0, 0.0, 0.0]
        store.insertChunks([
            (id: UUID(), documentId: docId, content: "청크", sectionTitle: nil, embedding: embedding, position: 0),
        ])

        // Search with orthogonal vector — should have low similarity
        let queryEmbedding: [Float] = [0.0, 1.0, 0.0]
        let results = store.search(queryEmbedding: queryEmbedding, topK: 10, minSimilarity: 0.5)
        XCTAssertTrue(results.isEmpty)
    }

    func testClear() {
        let store = makeTempStore()
        let doc = RAGDocument(
            fileName: "test.md",
            filePath: "/tmp/test.md",
            fileSize: 1024,
            fileType: .markdown,
            indexingStatus: .indexed
        )
        store.upsertDocument(doc)
        XCTAssertEqual(store.documentCount, 1)

        store.clear()
        XCTAssertEqual(store.documentCount, 0)
        XCTAssertEqual(store.chunkCount, 0)
    }

    func testDocumentCounts() {
        let store = makeTempStore()

        XCTAssertEqual(store.documentCount, 0)
        XCTAssertEqual(store.chunkCount, 0)

        let docId = UUID()
        store.upsertDocument(RAGDocument(
            id: docId,
            fileName: "a.txt",
            filePath: "/tmp/a.txt",
            fileSize: 100,
            fileType: .text,
            indexingStatus: .indexed
        ))
        XCTAssertEqual(store.documentCount, 1)

        store.insertChunks([
            (id: UUID(), documentId: docId, content: "chunk1", sectionTitle: nil, embedding: [1, 0, 0], position: 0),
            (id: UUID(), documentId: docId, content: "chunk2", sectionTitle: nil, embedding: [0, 1, 0], position: 1),
        ])
        XCTAssertEqual(store.chunkCount, 2)
    }
}

// MARK: - Message RAGContextInfo Backward Compatibility Tests

final class MessageRAGCompatibilityTests: XCTestCase {

    func testDecodeMessageWithoutRAGContextInfo() throws {
        // Simulate old message format (no ragContextInfo field)
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "role": "assistant",
            "content": "Hello!",
            "timestamp": "2024-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let message = try decoder.decode(Message.self, from: json.data(using: .utf8)!)
        XCTAssertNil(message.ragContextInfo)
    }

    func testDecodeMessageWithRAGContextInfo() throws {
        let json = """
        {
            "id": "22222222-2222-2222-2222-222222222222",
            "role": "assistant",
            "content": "Based on the document...",
            "timestamp": "2024-01-01T00:00:00Z",
            "ragContextInfo": {
                "references": [
                    {
                        "documentId": "33333333-3333-3333-3333-333333333333",
                        "fileName": "guide.md",
                        "sectionTitle": "Getting Started",
                        "similarity": 0.92,
                        "snippetPreview": "This guide covers..."
                    }
                ],
                "totalCharsInjected": 350
            }
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let message = try decoder.decode(Message.self, from: json.data(using: .utf8)!)
        XCTAssertNotNil(message.ragContextInfo)
        XCTAssertEqual(message.ragContextInfo?.referenceCount, 1)
        XCTAssertEqual(message.ragContextInfo?.references.first?.fileName, "guide.md")
        XCTAssertEqual(message.ragContextInfo?.totalCharsInjected, 350)
    }

    func testEncodeDecodeRoundTrip() throws {
        let ragInfo = RAGContextInfo(
            references: [
                RAGReference(
                    documentId: UUID().uuidString,
                    fileName: "notes.txt",
                    sectionTitle: nil,
                    similarity: 0.75,
                    snippetPreview: "Some notes..."
                )
            ],
            totalCharsInjected: 200
        )

        let message = Message(
            role: .assistant,
            content: "Response with RAG",
            ragContextInfo: ragInfo
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Message.self, from: data)

        XCTAssertEqual(decoded.ragContextInfo?.referenceCount, 1)
        XCTAssertEqual(decoded.ragContextInfo?.totalCharsInjected, 200)
        XCTAssertEqual(decoded.ragContextInfo?.references.first?.fileName, "notes.txt")
    }
}

// MARK: - EmbeddingError Tests

final class EmbeddingErrorTests: XCTestCase {

    func testErrorDescriptions() {
        XCTAssertNotNil(EmbeddingError.noAPIKey.errorDescription)
        XCTAssertNotNil(EmbeddingError.invalidResponse.errorDescription)
        XCTAssertNotNil(EmbeddingError.apiError(statusCode: 400, message: "bad request").errorDescription)
        XCTAssertNotNil(EmbeddingError.parseError.errorDescription)
        XCTAssertNotNil(EmbeddingError.emptyResponse.errorDescription)
    }
}

// MARK: - DocumentIndexerError Tests

final class DocumentIndexerErrorTests: XCTestCase {

    func testErrorDescriptions() {
        XCTAssertNotNil(DocumentIndexerError.unsupportedFileType("docx").errorDescription)
        XCTAssertNotNil(DocumentIndexerError.pdfParsingFailed.errorDescription)
        XCTAssertNotNil(DocumentIndexerError.emptyDocument.errorDescription)
    }
}
