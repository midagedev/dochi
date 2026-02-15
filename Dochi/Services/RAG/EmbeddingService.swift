import Foundation

/// OpenAI text-embedding API를 호출하여 텍스트 임베딩 벡터를 생성하는 서비스.
@MainActor
final class EmbeddingService {
    private let keychainService: KeychainServiceProtocol
    private let model: String
    private let batchSize: Int

    /// 임베딩 벡터 차원 수 (text-embedding-3-small = 1536)
    static let embeddingDimension = 1536

    init(keychainService: KeychainServiceProtocol, model: String = "text-embedding-3-small", batchSize: Int = 100) {
        self.keychainService = keychainService
        self.model = model
        self.batchSize = min(max(1, batchSize), 100)
    }

    // MARK: - Public

    /// 단일 텍스트의 임베딩 벡터 생성
    func embed(_ text: String) async throws -> [Float] {
        let results = try await embedBatch([text])
        guard let first = results.first else {
            throw EmbeddingError.emptyResponse
        }
        return first
    }

    /// 여러 텍스트의 임베딩 벡터를 배치로 생성
    func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }

        guard let apiKey = keychainService.load(account: "openai_api_key"), !apiKey.isEmpty else {
            throw EmbeddingError.noAPIKey
        }

        var allEmbeddings: [[Float]] = []

        // Process in batches
        for batchStart in stride(from: 0, to: texts.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, texts.count)
            let batch = Array(texts[batchStart..<batchEnd])

            let embeddings = try await callAPI(texts: batch, apiKey: apiKey)
            allEmbeddings.append(contentsOf: embeddings)
        }

        return allEmbeddings
    }

    // MARK: - API Call

    private func callAPI(texts: [String], apiKey: String) async throws -> [[Float]] {
        let url = URL(string: "https://api.openai.com/v1/embeddings")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "input": texts
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbeddingError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            Log.llm.error("Embedding API error \(httpResponse.statusCode): \(errorBody)")
            throw EmbeddingError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]]
        else {
            throw EmbeddingError.parseError
        }

        // Sort by index to maintain order
        let sorted = dataArray.sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }

        var embeddings: [[Float]] = []
        for item in sorted {
            guard let embeddingValues = item["embedding"] as? [NSNumber] else {
                throw EmbeddingError.parseError
            }
            embeddings.append(embeddingValues.map { $0.floatValue })
        }

        return embeddings
    }
}

// MARK: - EmbeddingError

enum EmbeddingError: Error, LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parseError
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenAI API 키가 설정되지 않았습니다. 설정 > API 키에서 입력하세요."
        case .invalidResponse:
            return "임베딩 API에서 잘못된 응답을 받았습니다."
        case .apiError(let code, let msg):
            return "임베딩 API 오류 (\(code)): \(msg)"
        case .parseError:
            return "임베딩 응답 파싱에 실패했습니다."
        case .emptyResponse:
            return "임베딩 결과가 비어있습니다."
        }
    }
}
