import Foundation

/// LLM adapter for Ollama (OpenAI-compatible API at localhost:11434).
/// Ollama doesn't require an API key and uses the same SSE format as OpenAI.
struct OllamaAdapter: LLMProviderAdapter {
    let provider: LLMProvider = .ollama

    private let base = OpenAIAdapter()

    /// Custom base URL from settings (defaults to http://localhost:11434).
    var baseURL: URL?

    func buildRequest(
        messages: [Message],
        systemPrompt: String,
        model: String,
        tools: [[String: Any]]?,
        apiKey: String
    ) throws -> URLRequest {
        let url = baseURL ?? provider.apiURL
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Ollama doesn't require Authorization header, but include if provided
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "model": model,
            "stream": true,
        ]

        var apiMessages: [[String: Any]] = []

        if !systemPrompt.isEmpty {
            apiMessages.append([
                "role": "system",
                "content": systemPrompt,
            ])
        }

        for msg in messages {
            apiMessages.append(OpenAIAdapter.convertMessage(msg))
        }

        body["messages"] = apiMessages

        if let tools, !tools.isEmpty {
            body["tools"] = tools
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func parseSSELine(_ line: String, accumulated: inout StreamAccumulator) -> LLMStreamEvent? {
        // Ollama uses OpenAI-compatible SSE format
        base.parseSSELine(line, accumulated: &accumulated)
    }
}

// MARK: - Ollama Model Discovery

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

    /// Response from /api/show endpoint for detailed model info.
    struct ShowResponse: Decodable {
        let modelInfo: [String: AnyCodableValue]?
        let details: ModelDetails?
        let parameters: String?

        enum CodingKeys: String, CodingKey {
            case modelInfo = "model_info"
            case details
            case parameters
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

// MARK: - AnyCodableValue (for flexible JSON decoding)

/// A type-erased Codable value for handling dynamic JSON structures.
enum AnyCodableValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}
