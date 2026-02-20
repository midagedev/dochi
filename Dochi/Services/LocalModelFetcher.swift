import Foundation

// MARK: - OllamaModelFetcher

/// Utility for fetching available models from a running Ollama instance.
enum OllamaModelFetcher {
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

    /// Known model families that support tool/function calling in Ollama.
    private static let toolSupportedFamilies: Set<String> = [
        "llama", "mistral", "mixtral", "qwen", "qwen2", "qwen2.5",
        "command-r", "firefunction", "hermes", "nous-hermes",
    ]

    /// Known model name patterns that indicate tool support.
    private static let toolSupportedPatterns: [String] = [
        "llama3", "llama3.1", "llama3.2", "llama3.3",
        "mistral", "mixtral",
        "qwen2", "qwen2.5",
        "command-r",
        "firefunction",
        "hermes",
    ]

    /// Fetch available models from Ollama API.
    static func fetchModels(baseURL: URL = URL(string: "http://localhost:11434")!) async -> [String] {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(ModelListResponse.self, from: data)
            return response.models.map(\.name)
        } catch {
            Log.llm.debug("Ollama model fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetch available models with detailed metadata from Ollama API.
    static func fetchModelInfos(baseURL: URL = URL(string: "http://localhost:11434")!) async -> [LocalModelInfo] {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(ModelListResponse.self, from: data)
            return response.models.map { model in
                let family = model.details?.family
                let supportsTools = detectToolSupport(modelName: model.name, family: family)
                return LocalModelInfo(
                    name: model.name,
                    size: model.size ?? 0,
                    parameterSize: model.details?.parameterSize,
                    quantization: model.details?.quantizationLevel,
                    family: family,
                    supportsTools: supportsTools
                )
            }
        } catch {
            Log.llm.debug("Ollama model info fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Detect whether a model likely supports tool/function calling.
    static func detectToolSupport(modelName: String, family: String?) -> Bool {
        // Check family
        if let family, toolSupportedFamilies.contains(family.lowercased()) {
            return true
        }

        // Check model name patterns
        let lowerName = modelName.lowercased()
        return toolSupportedPatterns.contains { lowerName.contains($0) }
    }

    /// Check if Ollama is running.
    static func isAvailable(baseURL: URL = URL(string: "http://localhost:11434")!) async -> Bool {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
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

    /// Fetch available models from LM Studio's OpenAI-compatible API.
    static func fetchModels(baseURL: URL = URL(string: "http://localhost:1234")!) async -> [String] {
        let url = baseURL.appendingPathComponent("v1/models")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
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

    /// Check if LM Studio is running.
    static func isAvailable(baseURL: URL = URL(string: "http://localhost:1234")!) async -> Bool {
        let url = baseURL.appendingPathComponent("v1/models")
        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
