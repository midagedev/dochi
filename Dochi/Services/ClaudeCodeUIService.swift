import Foundation
import os

@MainActor
final class ClaudeCodeUIService {
    struct APIError: LocalizedError { let message: String; var errorDescription: String? { message } }

    private let session: URLSession
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: config)
    }

    private func makeURL(_ path: String, query: [URLQueryItem]? = nil) throws -> URL {
        guard let base = URL(string: settings.claudeUIBaseURL) else { throw APIError(message: "Invalid base URL") }
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if let query { comps.queryItems = query }
        guard let url = comps.url else { throw APIError(message: "Invalid URL comps") }
        return url
    }

    private func request(_ method: String, _ path: String, query: [URLQueryItem]? = nil, json: Any? = nil) async throws -> (Data, HTTPURLResponse) {
        let url = try makeURL(path, query: query)
        var req = URLRequest(url: url)
        req.httpMethod = method
        if !settings.claudeUIToken.isEmpty { req.setValue("Bearer \(settings.claudeUIToken)", forHTTPHeaderField: "Authorization") }
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError(message: "No HTTP response") }
        return (data, http)
    }

    func health() async throws -> String {
        let (data, http) = try await request("GET", "/health")
        guard http.statusCode == 200 else { throw APIError(message: "Health HTTP \(http.statusCode)") }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func authStatus() async throws -> String {
        let (data, http) = try await request("GET", "/api/auth/status")
        guard http.statusCode == 200 else { throw APIError(message: "Auth HTTP \(http.statusCode)") }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MCP CLI wrappers
    func mcpList() async throws -> String {
        let (data, http) = try await request("GET", "/api/mcp/cli/list")
        guard http.statusCode == 200 else { throw APIError(message: "MCP list HTTP \(http.statusCode)") }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func mcpAddJSON(name: String, jsonConfig: Any, scope: String? = nil, projectPath: String? = nil) async throws -> String {
        var body: [String: Any] = ["name": name, "jsonConfig": jsonConfig]
        if let scope { body["scope"] = scope }
        if let projectPath { body["projectPath"] = projectPath }
        let (data, http) = try await request("POST", "/api/mcp/cli/add-json", json: body)
        guard http.statusCode == 200 else { throw APIError(message: "MCP add HTTP \(http.statusCode)") }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func mcpRemove(name: String, scope: String? = nil) async throws -> String {
        var items: [URLQueryItem] = []
        if let scope { items.append(URLQueryItem(name: "scope", value: scope)) }
        let (data, http) = try await request("DELETE", "/api/mcp/cli/remove/\(name)", query: items)
        guard http.statusCode == 200 else { throw APIError(message: "MCP remove HTTP \(http.statusCode)") }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // Projects & Sessions
    func listProjects() async throws -> [[String: Any]] {
        let (data, http) = try await request("GET", "/api/projects")
        guard http.statusCode == 200 else { throw APIError(message: "Projects HTTP \(http.statusCode)") }
        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        return json ?? []
    }

    func listSessions(projectName: String, limit: Int = 5, offset: Int = 0) async throws -> [String: Any] {
        let (data, http) = try await request("GET", "/api/projects/\(projectName)/sessions", query: [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "offset", value: String(offset))])
        guard http.statusCode == 200 else { throw APIError(message: "Sessions HTTP \(http.statusCode)") }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json ?? [:]
    }

    func renameProject(projectName: String, displayName: String) async throws {
        let body: [String: Any] = ["displayName": displayName]
        let (_, http) = try await request("PUT", "/api/projects/\(projectName)/rename", json: body)
        guard http.statusCode == 200 else { throw APIError(message: "Rename HTTP \(http.statusCode)") }
    }

    func deleteSession(projectName: String, sessionId: String) async throws {
        let (_, http) = try await request("DELETE", "/api/projects/\(projectName)/sessions/\(sessionId)")
        guard http.statusCode == 200 else { throw APIError(message: "Delete session HTTP \(http.statusCode)") }
    }

    func deleteProject(projectName: String, force: Bool = true) async throws {
        let (_, http) = try await request("DELETE", "/api/projects/\(projectName)", query: [URLQueryItem(name: "force", value: force ? "true" : "false")])
        guard http.statusCode == 200 else { throw APIError(message: "Delete project HTTP \(http.statusCode)") }
    }

    func addProject(path: String) async throws -> [String: Any] {
        let (data, http) = try await request("POST", "/api/projects/create", json: ["path": path])
        guard http.statusCode == 200 else { throw APIError(message: "Create project HTTP \(http.statusCode)") }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json ?? [:]
    }
}
