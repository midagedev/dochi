import Foundation
import SQLite3

/// SQLite 기반 벡터 저장소.
/// 문서와 청크를 저장하고, cosine similarity 검색을 지원한다.
@MainActor
@Observable
final class VectorStore {
    /// SQLite database handle wrapper to allow access from deinit.
    private final class DBHandle: @unchecked Sendable {
        var pointer: OpaquePointer?
    }

    private let dbHandle = DBHandle()
    private var db: OpaquePointer? {
        get { dbHandle.pointer }
        set { dbHandle.pointer = newValue }
    }
    private let dbPath: String

    /// 현재 인덱싱된 문서 수
    private(set) var documentCount: Int = 0
    /// 현재 인덱싱된 청크 수
    private(set) var chunkCount: Int = 0

    init(workspaceId: UUID) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let ragDir = appSupport
            .appendingPathComponent("Dochi")
            .appendingPathComponent("rag")
            .appendingPathComponent(workspaceId.uuidString)
        try? FileManager.default.createDirectory(at: ragDir, withIntermediateDirectories: true)
        self.dbPath = ragDir.appendingPathComponent("vectors.sqlite").path
        openDatabase()
        createTablesIfNeeded()
        refreshCounts()
    }

    /// 테스트용: 커스텀 경로로 초기화
    init(dbPath: String) {
        self.dbPath = dbPath
        let dir = (dbPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        openDatabase()
        createTablesIfNeeded()
        refreshCounts()
    }

    deinit {
        if let ptr = dbHandle.pointer {
            sqlite3_close(ptr)
        }
    }

    // MARK: - Database Setup

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            Log.storage.error("VectorStore: Failed to open database at \(self.dbPath)")
        }
    }

    private func createTablesIfNeeded() {
        let createDocuments = """
        CREATE TABLE IF NOT EXISTS documents (
            id TEXT PRIMARY KEY,
            fileName TEXT NOT NULL,
            filePath TEXT NOT NULL,
            fileSize INTEGER NOT NULL,
            fileType TEXT NOT NULL,
            chunkCount INTEGER DEFAULT 0,
            indexingStatus TEXT DEFAULT 'pending',
            lastIndexedAt TEXT,
            errorMessage TEXT
        );
        """

        let createChunks = """
        CREATE TABLE IF NOT EXISTS chunks (
            id TEXT PRIMARY KEY,
            documentId TEXT NOT NULL,
            content TEXT NOT NULL,
            sectionTitle TEXT,
            embedding BLOB,
            position INTEGER DEFAULT 0,
            FOREIGN KEY (documentId) REFERENCES documents(id) ON DELETE CASCADE
        );
        """

        let createIndex = """
        CREATE INDEX IF NOT EXISTS idx_chunks_document ON chunks(documentId);
        """

        executeSQL(createDocuments)
        executeSQL(createChunks)
        executeSQL(createIndex)
        executeSQL("PRAGMA foreign_keys = ON;")
    }

    // MARK: - SQLite Binding Helper

    /// SQLITE_TRANSIENT equivalent — tells SQLite to copy the string immediately
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func bindText(_ stmt: OpaquePointer?, index: Int32, value: String) {
        sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, Self.sqliteTransient)
    }

    // MARK: - Document CRUD

    func upsertDocument(_ doc: RAGDocument) {
        let sql = """
        INSERT OR REPLACE INTO documents (id, fileName, filePath, fileSize, fileType, chunkCount, indexingStatus, lastIndexedAt, errorMessage)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Log.storage.error("VectorStore: Failed to prepare upsert document")
            return
        }
        defer { sqlite3_finalize(stmt) }

        bindText(stmt, index: 1, value: doc.id.uuidString)
        bindText(stmt, index: 2, value: doc.fileName)
        bindText(stmt, index: 3, value: doc.filePath)
        sqlite3_bind_int64(stmt, 4, doc.fileSize)
        bindText(stmt, index: 5, value: doc.fileType.rawValue)
        sqlite3_bind_int(stmt, 6, Int32(doc.chunkCount))
        bindText(stmt, index: 7, value: doc.indexingStatus.rawValue)
        if let date = doc.lastIndexedAt {
            bindText(stmt, index: 8, value: ISO8601DateFormatter().string(from: date))
        } else {
            sqlite3_bind_null(stmt, 8)
        }
        if let error = doc.errorMessage {
            bindText(stmt, index: 9, value: error)
        } else {
            sqlite3_bind_null(stmt, 9)
        }

        if sqlite3_step(stmt) != SQLITE_DONE {
            Log.storage.error("VectorStore: Failed to upsert document \(doc.fileName)")
        }

        refreshCounts()
    }

    func loadDocuments() -> [RAGDocument] {
        let sql = "SELECT id, fileName, filePath, fileSize, fileType, chunkCount, indexingStatus, lastIndexedAt, errorMessage FROM documents ORDER BY fileName;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var docs: [RAGDocument] = []
        let formatter = ISO8601DateFormatter()

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
                  let id = UUID(uuidString: idStr),
                  let fileName = sqlite3_column_text(stmt, 1).map({ String(cString: $0) }),
                  let filePath = sqlite3_column_text(stmt, 2).map({ String(cString: $0) }),
                  let fileTypeStr = sqlite3_column_text(stmt, 4).map({ String(cString: $0) }),
                  let fileType = RAGFileType(rawValue: fileTypeStr),
                  let statusStr = sqlite3_column_text(stmt, 6).map({ String(cString: $0) }),
                  let status = RAGIndexingStatus(rawValue: statusStr)
            else { continue }

            let fileSize = sqlite3_column_int64(stmt, 3)
            let chunkCount = Int(sqlite3_column_int(stmt, 5))
            let lastIndexedAt: Date? = sqlite3_column_text(stmt, 7).flatMap {
                formatter.date(from: String(cString: $0))
            }
            let errorMessage: String? = sqlite3_column_text(stmt, 8).map { String(cString: $0) }

            docs.append(RAGDocument(
                id: id,
                fileName: fileName,
                filePath: filePath,
                fileSize: fileSize,
                fileType: fileType,
                chunkCount: chunkCount,
                indexingStatus: status,
                lastIndexedAt: lastIndexedAt,
                errorMessage: errorMessage
            ))
        }

        return docs
    }

    func deleteDocument(id: UUID) {
        // Delete chunks first (foreign key)
        let deleteChunksSQL = "DELETE FROM chunks WHERE documentId = ?;"
        var chunkStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteChunksSQL, -1, &chunkStmt, nil) == SQLITE_OK {
            bindText(chunkStmt, index: 1, value: id.uuidString)
            if sqlite3_step(chunkStmt) != SQLITE_DONE {
                Log.storage.error("VectorStore: Failed to delete chunks for document \(id.uuidString)")
            }
        }
        sqlite3_finalize(chunkStmt)

        let deleteDocSQL = "DELETE FROM documents WHERE id = ?;"
        var docStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteDocSQL, -1, &docStmt, nil) == SQLITE_OK {
            bindText(docStmt, index: 1, value: id.uuidString)
            if sqlite3_step(docStmt) != SQLITE_DONE {
                Log.storage.error("VectorStore: Failed to delete document \(id.uuidString)")
            }
        }
        sqlite3_finalize(docStmt)

        refreshCounts()
    }

    // MARK: - Chunk CRUD

    func insertChunks(_ chunks: [(id: UUID, documentId: UUID, content: String, sectionTitle: String?, embedding: [Float], position: Int)]) {
        executeSQL("BEGIN TRANSACTION;")

        let sql = """
        INSERT OR REPLACE INTO chunks (id, documentId, content, sectionTitle, embedding, position)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Log.storage.error("VectorStore: Failed to prepare insert chunk")
            executeSQL("ROLLBACK;")
            return
        }
        defer { sqlite3_finalize(stmt) }

        for chunk in chunks {
            sqlite3_reset(stmt)
            bindText(stmt, index: 1, value: chunk.id.uuidString)
            bindText(stmt, index: 2, value: chunk.documentId.uuidString)
            bindText(stmt, index: 3, value: chunk.content)
            if let title = chunk.sectionTitle {
                bindText(stmt, index: 4, value: title)
            } else {
                sqlite3_bind_null(stmt, 4)
            }

            // Store embedding as blob
            let embeddingData = chunk.embedding.withUnsafeBufferPointer { Data(buffer: $0) }
            _ = embeddingData.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 5, ptr.baseAddress, Int32(embeddingData.count), Self.sqliteTransient)
            }
            sqlite3_bind_int(stmt, 6, Int32(chunk.position))

            if sqlite3_step(stmt) != SQLITE_DONE {
                Log.storage.error("VectorStore: Failed to insert chunk")
            }
        }

        executeSQL("COMMIT;")
        refreshCounts()
    }

    func deleteChunks(documentId: UUID) {
        let sql = "DELETE FROM chunks WHERE documentId = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, index: 1, value: documentId.uuidString)
            if sqlite3_step(stmt) != SQLITE_DONE {
                Log.storage.error("VectorStore: Failed to delete chunks for document \(documentId.uuidString)")
            }
        }
        sqlite3_finalize(stmt)
        refreshCounts()
    }

    // MARK: - Vector Search

    /// 코사인 유사도 기반 벡터 검색
    func search(queryEmbedding: [Float], topK: Int = 3, minSimilarity: Double = 0.3) -> [RAGSearchResult] {
        let sql = """
        SELECT c.id, c.documentId, c.content, c.sectionTitle, c.embedding, c.position, d.fileName
        FROM chunks c
        JOIN documents d ON c.documentId = d.id
        WHERE d.indexingStatus = 'indexed' AND c.embedding IS NOT NULL;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var results: [(result: RAGSearchResult, similarity: Double)] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
                  let id = UUID(uuidString: idStr),
                  let docIdStr = sqlite3_column_text(stmt, 1).map({ String(cString: $0) }),
                  let docId = UUID(uuidString: docIdStr),
                  let content = sqlite3_column_text(stmt, 2).map({ String(cString: $0) }),
                  let fileName = sqlite3_column_text(stmt, 6).map({ String(cString: $0) })
            else { continue }

            let sectionTitle = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
            let position = Int(sqlite3_column_int(stmt, 5))

            // Read embedding blob
            guard let blobPtr = sqlite3_column_blob(stmt, 4) else { continue }
            let blobSize = Int(sqlite3_column_bytes(stmt, 4))
            let floatCount = blobSize / MemoryLayout<Float>.size
            guard floatCount == queryEmbedding.count else { continue }

            let embeddingPtr = blobPtr.bindMemory(to: Float.self, capacity: floatCount)
            let storedEmbedding = Array(UnsafeBufferPointer(start: embeddingPtr, count: floatCount))

            let similarity = cosineSimilarity(queryEmbedding, storedEmbedding)
            guard similarity >= minSimilarity else { continue }

            let result = RAGSearchResult(
                id: id,
                documentId: docId,
                fileName: fileName,
                sectionTitle: sectionTitle,
                content: content,
                similarity: similarity,
                position: position
            )
            results.append((result, similarity))
        }

        // Sort by similarity (descending) and take topK
        results.sort { $0.similarity > $1.similarity }
        return Array(results.prefix(topK).map(\.result))
    }

    // MARK: - Maintenance

    func clear() {
        executeSQL("DELETE FROM chunks;")
        executeSQL("DELETE FROM documents;")
        refreshCounts()
    }

    func refreshCounts() {
        documentCount = countRows("documents")
        chunkCount = countRows("chunks")
    }

    /// 기존 인덱스에 저장된 임베딩 벡터의 차원 수를 반환한다.
    /// 저장된 청크가 없으면 nil을 반환한다.
    func storedEmbeddingDimension() -> Int? {
        let sql = "SELECT embedding FROM chunks WHERE embedding IS NOT NULL LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW,
              sqlite3_column_blob(stmt, 0) != nil else { return nil }

        let blobSize = Int(sqlite3_column_bytes(stmt, 0))
        return blobSize / MemoryLayout<Float>.size
    }

    // MARK: - Helpers

    private func executeSQL(_ sql: String) {
        var errmsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errmsg) != SQLITE_OK {
            let msg = errmsg.map { String(cString: $0) } ?? "unknown"
            Log.storage.error("VectorStore SQL error: \(msg)")
            sqlite3_free(errmsg)
        }
    }

    private func countRows(_ table: String) -> Int {
        let sql = "SELECT COUNT(*) FROM \(table);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }
}

// MARK: - Cosine Similarity (Pure Swift)

/// 두 벡터 간의 코사인 유사도를 계산한다. 순수 Swift 구현.
func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return 0 }

    var dot: Float = 0
    var magA: Float = 0
    var magB: Float = 0

    for i in 0..<a.count {
        dot += a[i] * b[i]
        magA += a[i] * a[i]
        magB += b[i] * b[i]
    }

    let magnitude = sqrt(magA) * sqrt(magB)
    guard magnitude > 0 else { return 0 }
    return Double(dot / magnitude)
}
