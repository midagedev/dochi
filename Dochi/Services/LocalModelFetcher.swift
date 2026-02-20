import Foundation

// MARK: - OllamaModelFetcher

/// Utility for fetching available models from a running Ollama instance.
enum OllamaModelFetcher {
    struct OpenAIModelListResponse: Decodable {
        let data: [OpenAIModel]
    }

    struct OpenAIModel: Decodable {
        let id: String
    }

    struct ModelListResponse: Decodable {
        let models: [ModelInfo]
    }

    struct ModelInfo: Decodable {
        let name: String
        let size: Int64?
        let digest: String?
        let details: ModelDetails?

        enum CodingKeys: String, CodingKey {
            case name, size, digest, details
        }
    }

    struct ModelDetails: Decodable {
        let parameterSize: String?
        let quantizationLevel: String?
        let family: String?

        enum CodingKeys: String, CodingKey {
            case parameterSize = "parameter_size"
            case quantizationLevel = "quantization_level"
            case family
        }
    }

    private static let retryDelaysNanoseconds: [UInt64] = [
        0,
        250_000_000,
        750_000_000,
    ]

    /// Fetch available models from Ollama API (`/v1/models` first, `/api/tags` fallback).
    static func fetchModels(baseURL: URL = URL(string: "http://localhost:11434")!) async -> [String] {
        if let openAIModels = await fetchOpenAICompatibleModels(baseURL: baseURL),
           !openAIModels.isEmpty {
            return openAIModels
        }

        guard let tagsResponse = await fetchTagList(baseURL: baseURL) else {
            return []
        }
        return tagsResponse.models.map(\.name)
    }

    /// Fetch available models with metadata. Discovery uses `/v1/models` and enriches via `/api/tags`.
    static func fetchModelInfos(baseURL: URL = URL(string: "http://localhost:11434")!) async -> [LocalModelInfo] {
        let discoveredModelNames = await fetchModels(baseURL: baseURL)
        let tagsResponse = await fetchTagList(baseURL: baseURL)
        let tagsByName = Dictionary(uniqueKeysWithValues: (tagsResponse?.models ?? []).map { ($0.name, $0) })

        let orderedNames = discoveredModelNames.isEmpty
            ? (tagsResponse?.models.map(\.name) ?? [])
            : discoveredModelNames

        return orderedNames.map { modelName in
            let metadata = tagsByName[modelName]
            let family = metadata?.details?.family
            return LocalModelInfo(
                name: modelName,
                size: metadata?.size ?? 0,
                parameterSize: metadata?.details?.parameterSize,
                quantization: metadata?.details?.quantizationLevel,
                family: family,
                supportsTools: detectToolSupport(modelName: modelName, family: family)
            )
        }
    }

    /// Detect whether a model likely supports tool/function calling.
    static func detectToolSupport(modelName: String, family: String?) -> Bool {
        ProviderCapabilityMatrix.supportsLocalToolCalling(
            model: modelName,
            familyHint: family
        )
    }

    /// Check if Ollama is running (with short retry/backoff).
    static func isAvailable(baseURL: URL = URL(string: "http://localhost:11434")!) async -> Bool {
        let modelsReachable = await isEndpointReachable(
            url: openAIModelsURL(baseURL: baseURL),
            timeout: 3
        )
        if modelsReachable {
            return true
        }
        return await isEndpointReachable(
            url: ollamaTagsURL(baseURL: baseURL),
            timeout: 3
        )
    }

    private static func fetchOpenAICompatibleModels(baseURL: URL) async -> [String]? {
        do {
            let data = try await requestDataWithRetry(
                url: openAIModelsURL(baseURL: baseURL),
                timeout: 5
            )
            let response = try JSONDecoder().decode(OpenAIModelListResponse.self, from: data)
            return response.data.map(\.id)
        } catch {
            Log.llm.debug("Ollama /v1/models fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func fetchTagList(baseURL: URL) async -> ModelListResponse? {
        do {
            let data = try await requestDataWithRetry(
                url: ollamaTagsURL(baseURL: baseURL),
                timeout: 5
            )
            return try JSONDecoder().decode(ModelListResponse.self, from: data)
        } catch {
            Log.llm.debug("Ollama /api/tags fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func requestDataWithRetry(url: URL, timeout: TimeInterval) async throws -> Data {
        var lastError: Error?

        for (index, delay) in retryDelaysNanoseconds.enumerated() {
            if delay > 0 {
                try await Task.sleep(nanoseconds: delay)
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = timeout

            do {
                let (data, rawResponse) = try await URLSession.shared.data(for: request)
                guard let response = rawResponse as? HTTPURLResponse,
                      (200...299).contains(response.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                return data
            } catch {
                lastError = error
                if index == retryDelaysNanoseconds.count - 1 {
                    throw error
                }
            }
        }

        throw lastError ?? URLError(.unknown)
    }

    private static func isEndpointReachable(url: URL, timeout: TimeInterval) async -> Bool {
        do {
            _ = try await requestDataWithRetry(url: url, timeout: timeout)
            return true
        } catch {
            return false
        }
    }

    private static func openAIModelsURL(baseURL: URL) -> URL {
        let normalized = normalizedBaseURL(baseURL)
        return normalized
            .appendingPathComponent("v1")
            .appendingPathComponent("models")
    }

    private static func ollamaTagsURL(baseURL: URL) -> URL {
        let normalized = normalizedBaseURL(baseURL)
        return normalized
            .appendingPathComponent("api")
            .appendingPathComponent("tags")
    }

    private static func normalizedBaseURL(_ baseURL: URL) -> URL {
        let trimmedPath = baseURL.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()

        if trimmedPath.hasSuffix("v1/chat/completions") {
            return baseURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }
        if trimmedPath.hasSuffix("v1/models") || trimmedPath.hasSuffix("api/tags") {
            return baseURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }
        if trimmedPath.hasSuffix("v1") || trimmedPath.hasSuffix("api") {
            return baseURL.deletingLastPathComponent()
        }
        return baseURL
    }
}

// MARK: - LMStudioModelFetcher

/// Utility for fetching available models from a running LM Studio instance.
enum LMStudioModelFetcher {
    struct ModelListResponse: Decodable {
        let data: [ModelInfo]
    }

    struct ModelInfo: Decodable {
        let id: String
        let object: String?

        enum CodingKeys: String, CodingKey {
            case id, object
        }
    }

    private static let retryDelaysNanoseconds: [UInt64] = [
        0,
        250_000_000,
        750_000_000,
    ]

    /// Fetch available models from LM Studio's OpenAI-compatible API.
    static func fetchModels(baseURL: URL = URL(string: "http://localhost:1234")!) async -> [String] {
        do {
            let data = try await requestDataWithRetry(
                url: modelsURL(baseURL: baseURL),
                timeout: 5
            )
            let response = try JSONDecoder().decode(ModelListResponse.self, from: data)
            return response.data.map(\.id)
        } catch {
            Log.llm.debug("LM Studio model fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetch available models with detailed info from LM Studio.
    static func fetchModelInfos(baseURL: URL = URL(string: "http://localhost:1234")!) async -> [LocalModelInfo] {
        let models = await fetchModels(baseURL: baseURL)
        return models.map { modelId in
            LocalModelInfo(
                name: modelId,
                size: 0, // LM Studio /v1/models doesn't expose file size
                parameterSize: nil,
                quantization: nil,
                family: nil,
                supportsTools: false // Conservative default; no reliable detection method
            )
        }
    }

    /// Check if LM Studio is running (with short retry/backoff).
    static func isAvailable(baseURL: URL = URL(string: "http://localhost:1234")!) async -> Bool {
        await isEndpointReachable(url: modelsURL(baseURL: baseURL), timeout: 3)
    }

    private static func requestDataWithRetry(url: URL, timeout: TimeInterval) async throws -> Data {
        var lastError: Error?

        for (index, delay) in retryDelaysNanoseconds.enumerated() {
            if delay > 0 {
                try await Task.sleep(nanoseconds: delay)
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = timeout

            do {
                let (data, rawResponse) = try await URLSession.shared.data(for: request)
                guard let response = rawResponse as? HTTPURLResponse,
                      (200...299).contains(response.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                return data
            } catch {
                lastError = error
                if index == retryDelaysNanoseconds.count - 1 {
                    throw error
                }
            }
        }

        throw lastError ?? URLError(.unknown)
    }

    private static func isEndpointReachable(url: URL, timeout: TimeInterval) async -> Bool {
        do {
            _ = try await requestDataWithRetry(url: url, timeout: timeout)
            return true
        } catch {
            return false
        }
    }

    private static func modelsURL(baseURL: URL) -> URL {
        let normalized = normalizedBaseURL(baseURL)
        return normalized
            .appendingPathComponent("v1")
            .appendingPathComponent("models")
    }

    private static func normalizedBaseURL(_ baseURL: URL) -> URL {
        let trimmedPath = baseURL.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()

        if trimmedPath.hasSuffix("v1/chat/completions") {
            return baseURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }
        if trimmedPath.hasSuffix("v1/models") {
            return baseURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }
        if trimmedPath.hasSuffix("v1") {
            return baseURL.deletingLastPathComponent()
        }
        return baseURL
    }
}
