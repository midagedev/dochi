import Foundation
import os

enum ExternalUsageProvider: String, Sendable {
    case codex
    case claude
    case gemini
}

struct ExternalUsageProviderStatus: Sendable, Equatable {
    let code: String
    let message: String?
}

/// External tool usage monitor with provider-specific incremental scanners.
actor ExternalUsageMonitor {
    private struct MonitorCache: Codable, Sendable {
        var version: Int = 1
        var providers: [String: ProviderCache] = [:]
    }

    private struct ProviderCache: Codable, Sendable {
        var lastScanUnixMs: Int64 = 0
        var files: [String: FileUsage] = [:]
        var days: [String: Int] = [:]
        var lastUsageFraction: Double? = nil
        var lastStatus: String? = nil
        var lastMessage: String? = nil
    }

    private struct FileUsage: Codable, Sendable {
        var mtimeUnixMs: Int64
        var size: Int64
        var dayTokens: [String: Int]
        var parsedBytes: Int64?
        var lastTotals: CodexTotals?
        var sessionId: String?
        var fileIdentity: String?
    }

    private struct CodexTotals: Codable, Sendable {
        let input: Int
        let cached: Int
        let output: Int
    }

    private struct DayRange: Sendable {
        let sinceKey: String
        let untilKey: String
        let scanSinceKey: String
        let scanUntilKey: String

        init(since: Date, until: Date) {
            let calendar = Calendar.current
            self.sinceKey = Self.dayKey(from: since)
            self.untilKey = Self.dayKey(from: until)
            self.scanSinceKey = Self.dayKey(from: calendar.date(byAdding: .day, value: -1, to: since) ?? since)
            self.scanUntilKey = Self.dayKey(from: calendar.date(byAdding: .day, value: 1, to: until) ?? until)
        }

        static func dayKey(from date: Date) -> String {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            let year = components.year ?? 1970
            let month = components.month ?? 1
            let day = components.day ?? 1
            return String(format: "%04d-%02d-%02d", year, month, day)
        }

        static func parseDayKey(_ key: String) -> Date? {
            let parts = key.split(separator: "-")
            guard parts.count == 3 else { return nil }
            guard
                let year = Int(parts[0]),
                let month = Int(parts[1]),
                let day = Int(parts[2])
            else { return nil }

            var components = DateComponents()
            components.calendar = Calendar.current
            components.timeZone = TimeZone.current
            components.year = year
            components.month = month
            components.day = day
            components.hour = 12
            return components.date
        }

        static func isInRange(dayKey: String, since: String, until: String) -> Bool {
            dayKey >= since && dayKey <= until
        }
    }

    private struct CodexParseResult: Sendable {
        let dayTokens: [String: Int]
        let parsedBytes: Int64
        let lastTotals: CodexTotals?
        let sessionId: String?
    }

    private struct ClaudeParseResult: Sendable {
        let dayTokens: [String: Int]
        let parsedBytes: Int64
    }

    private struct CodexScanState {
        var seenSessionIds: Set<String> = []
        var seenFileIds: Set<String> = []
    }

    private enum GeminiAuthType: String, Sendable {
        case oauthPersonal = "oauth-personal"
        case apiKey = "api-key"
        case vertexAI = "vertex-ai"
        case unknown
    }

    private struct GeminiProbeError: Error, Sendable {
        let statusCode: String
        let message: String
    }

    private struct GeminiProbeResult: Sendable {
        let usedFraction: Double?
        let statusCode: String
        let message: String?
    }

    private struct GeminiCredentials: Sendable {
        var accessToken: String
        let refreshToken: String?
        let idToken: String?
        let expiryDate: Date?
        let credentialsURL: URL
    }

    private struct GeminiOAuthClientCredentials: Sendable {
        let clientId: String
        let clientSecret: String
    }

    private struct GeminiQuotaBucket: Decodable {
        let remainingFraction: Double?
        let modelId: String?
    }

    private struct GeminiQuotaResponse: Decodable {
        let buckets: [GeminiQuotaBucket]?
    }

    private struct JSONLLine: Sendable {
        let bytes: Data
        let wasTruncated: Bool
    }

    private static let codexFilenameDateRegex = try? NSRegularExpression(pattern: "(\\d{4}-\\d{2}-\\d{2})")

    private static let fallbackDateFormats = [
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss.SSS",
        "yyyy-MM-dd'T'HH:mm:ss",
    ]

    private static let geminiQuotaEndpoint = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")
    private static let geminiLoadCodeAssistEndpoint = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")
    private static let geminiRefreshEndpoint = URL(string: "https://oauth2.googleapis.com/token")

    private let codexSessionsRoots: [URL]
    private let claudeProjectsRoots: [URL]
    private let geminiConfigRoots: [URL]
    private let cacheURL: URL
    private let refreshMinIntervalSeconds: TimeInterval
    private let geminiDataLoader: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let geminiCommandRunner: @Sendable (_ executable: String, _ arguments: [String], _ timeout: TimeInterval) -> (output: String, exitCode: Int32)?

    private var cache: MonitorCache

    init(
        codexSessionsRoots: [URL],
        claudeProjectsRoots: [URL],
        geminiConfigRoots: [URL] = [],
        cacheURL: URL,
        refreshMinIntervalSeconds: TimeInterval = 60,
        geminiDataLoader: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil,
        geminiCommandRunner: (@Sendable (_ executable: String, _ arguments: [String], _ timeout: TimeInterval) -> (output: String, exitCode: Int32)?)? = nil
    ) {
        self.codexSessionsRoots = Self.uniqueStandardizedPaths(codexSessionsRoots)
        self.claudeProjectsRoots = Self.uniqueStandardizedPaths(claudeProjectsRoots)
        self.geminiConfigRoots = Self.uniqueStandardizedPaths(geminiConfigRoots)
        self.cacheURL = cacheURL
        self.refreshMinIntervalSeconds = max(0, refreshMinIntervalSeconds)
        self.geminiDataLoader = geminiDataLoader ?? { request in
            try await URLSession.shared.data(for: request)
        }
        self.geminiCommandRunner = geminiCommandRunner ?? { executable, arguments, timeout in
            Self.runProcess(executable: executable, arguments: arguments, timeout: timeout)
        }
        self.cache = Self.loadCache(at: cacheURL) ?? MonitorCache()
    }

    func tokensUsed(
        provider: ExternalUsageProvider,
        since startDate: Date,
        tokenLimit: Int? = nil,
        now: Date = Date()
    ) async -> Int {
        switch provider {
        case .codex:
            refreshCodex(since: startDate, now: now)
        case .claude:
            refreshClaude(since: startDate, now: now)
        case .gemini:
            await refreshGemini(since: startDate, now: now)
        }

        let key = provider.rawValue
        guard let providerCache = cache.providers[key] else { return 0 }
        if provider == .gemini {
            guard let fraction = providerCache.lastUsageFraction,
                  let tokenLimit,
                  tokenLimit > 0 else {
                return 0
            }
            return max(0, Int((Double(tokenLimit) * fraction).rounded()))
        }

        let range = DayRange(since: startDate, until: now)
        let sum = providerCache.days.reduce(0) { partial, entry in
            guard DayRange.isInRange(dayKey: entry.key, since: range.sinceKey, until: range.untilKey) else {
                return partial
            }
            return partial + max(0, entry.value)
        }
        return max(0, sum)
    }

    func status(provider: ExternalUsageProvider) -> ExternalUsageProviderStatus? {
        let key = provider.rawValue
        guard let providerCache = cache.providers[key], let code = providerCache.lastStatus else {
            return nil
        }
        return ExternalUsageProviderStatus(code: code, message: providerCache.lastMessage)
    }

    // MARK: - Refresh

    private func refreshCodex(since startDate: Date, now: Date) {
        let key = ExternalUsageProvider.codex.rawValue
        var providerCache = cache.providers[key] ?? ProviderCache()

        guard shouldRefresh(lastScanUnixMs: providerCache.lastScanUnixMs, now: now) else { return }

        let range = DayRange(since: startDate, until: now)
        let files = listCodexSessionFiles(range: range)
        let touchedPaths = Set(files.map(\.path))

        var state = CodexScanState()
        for fileURL in files {
            scanCodexFile(fileURL: fileURL, range: range, providerCache: &providerCache, state: &state)
        }

        for stalePath in providerCache.files.keys where !touchedPaths.contains(stalePath) {
            if let old = providerCache.files[stalePath] {
                applyDayTokens(providerCache: &providerCache, dayTokens: old.dayTokens, sign: -1)
            }
            providerCache.files.removeValue(forKey: stalePath)
        }

        pruneDays(providerCache: &providerCache, sinceKey: range.scanSinceKey, untilKey: range.scanUntilKey)
        providerCache.lastScanUnixMs = Int64(now.timeIntervalSince1970 * 1000)
        cache.providers[key] = providerCache
        saveCache()
    }

    private func refreshClaude(since startDate: Date, now: Date) {
        let key = ExternalUsageProvider.claude.rawValue
        var providerCache = cache.providers[key] ?? ProviderCache()

        guard shouldRefresh(lastScanUnixMs: providerCache.lastScanUnixMs, now: now) else { return }

        let range = DayRange(since: startDate, until: now)
        let modifiedAfter = DayRange.parseDayKey(range.scanSinceKey) ?? startDate
        let files = listClaudeProjectFiles(modifiedAfter: modifiedAfter)
        let touchedPaths = Set(files.map(\.path))

        for fileURL in files {
            scanClaudeFile(fileURL: fileURL, range: range, providerCache: &providerCache)
        }

        for stalePath in providerCache.files.keys where !touchedPaths.contains(stalePath) {
            if let old = providerCache.files[stalePath] {
                applyDayTokens(providerCache: &providerCache, dayTokens: old.dayTokens, sign: -1)
            }
            providerCache.files.removeValue(forKey: stalePath)
        }

        pruneDays(providerCache: &providerCache, sinceKey: range.scanSinceKey, untilKey: range.scanUntilKey)
        providerCache.lastScanUnixMs = Int64(now.timeIntervalSince1970 * 1000)
        cache.providers[key] = providerCache
        saveCache()
    }

    private func shouldRefresh(lastScanUnixMs: Int64, now: Date) -> Bool {
        if refreshMinIntervalSeconds == 0 { return true }
        if lastScanUnixMs == 0 { return true }
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let refreshMs = Int64(refreshMinIntervalSeconds * 1000)
        return (nowMs - lastScanUnixMs) > refreshMs
    }

    // MARK: - Gemini scan

    private func refreshGemini(since _: Date, now: Date) async {
        let key = ExternalUsageProvider.gemini.rawValue
        var providerCache = cache.providers[key] ?? ProviderCache()

        guard shouldRefresh(lastScanUnixMs: providerCache.lastScanUnixMs, now: now) else { return }

        let result = await fetchGeminiUsage(now: now)
        providerCache.lastStatus = result.statusCode
        providerCache.lastMessage = result.message
        providerCache.lastUsageFraction = result.usedFraction
        providerCache.files.removeAll(keepingCapacity: true)

        providerCache.lastScanUnixMs = Int64(now.timeIntervalSince1970 * 1000)
        cache.providers[key] = providerCache
        saveCache()
    }

    private func fetchGeminiUsage(now: Date) async -> GeminiProbeResult {
        let configRoot = resolvedGeminiConfigRoot()
        let authType = geminiAuthType(configRoot: configRoot)

        switch authType {
        case .apiKey:
            return GeminiProbeResult(
                usedFraction: nil,
                statusCode: "unsupported_auth_type",
                message: "Gemini auth type 'api-key' is not supported for usage monitoring."
            )
        case .vertexAI:
            return GeminiProbeResult(
                usedFraction: nil,
                statusCode: "unsupported_auth_type",
                message: "Gemini auth type 'vertex-ai' is not supported for usage monitoring."
            )
        case .oauthPersonal, .unknown:
            break
        }

        do {
            let usedFraction = try await fetchGeminiUsageViaAPI(configRoot: configRoot, now: now)
            return GeminiProbeResult(usedFraction: usedFraction, statusCode: "ok_api", message: nil)
        } catch let apiError as GeminiProbeError {
            let fallback = fetchGeminiUsageViaCLI()
            if let fallbackUsed = fallback.usedFraction {
                return GeminiProbeResult(usedFraction: fallbackUsed, statusCode: "ok_cli", message: fallback.message)
            }
            return GeminiProbeResult(
                usedFraction: nil,
                statusCode: fallback.statusCode == "not_logged_in" ? fallback.statusCode : apiError.statusCode,
                message: fallback.statusCode == "not_logged_in" ? fallback.message : apiError.message
            )
        } catch {
            let fallback = fetchGeminiUsageViaCLI()
            if let fallbackUsed = fallback.usedFraction {
                return GeminiProbeResult(usedFraction: fallbackUsed, statusCode: "ok_cli", message: fallback.message)
            }
            return GeminiProbeResult(
                usedFraction: nil,
                statusCode: fallback.statusCode == "not_logged_in" ? fallback.statusCode : "api_error",
                message: fallback.statusCode == "not_logged_in" ? fallback.message : error.localizedDescription
            )
        }
    }

    private func fetchGeminiUsageViaAPI(configRoot: URL, now: Date) async throws -> Double {
        var credentials = try loadGeminiCredentials(configRoot: configRoot)
        if let expiry = credentials.expiryDate, expiry <= now {
            credentials.accessToken = try await refreshGeminiAccessToken(
                configRoot: configRoot,
                refreshToken: credentials.refreshToken,
                credentialsURL: credentials.credentialsURL
            )
        }

        let projectId = await fetchGeminiProjectID(accessToken: credentials.accessToken)
        let quotaData = try await fetchGeminiQuotaData(accessToken: credentials.accessToken, projectID: projectId)
        return try parseGeminiUsedFraction(data: quotaData)
    }

    private func fetchGeminiQuotaData(accessToken: String, projectID: String?) async throws -> Data {
        guard let endpoint = Self.geminiQuotaEndpoint else {
            throw GeminiProbeError(statusCode: "api_error", message: "Gemini quota endpoint is invalid.")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let projectID, !projectID.isEmpty {
            request.httpBody = Data("{\"project\":\"\(projectID)\"}".utf8)
        } else {
            request.httpBody = Data("{}".utf8)
        }

        let (data, response) = try await geminiDataLoader(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiProbeError(statusCode: "api_error", message: "Gemini quota response is invalid.")
        }
        if httpResponse.statusCode == 401 {
            throw GeminiProbeError(statusCode: "not_logged_in", message: "Gemini OAuth token is invalid or expired.")
        }
        guard httpResponse.statusCode == 200 else {
            throw GeminiProbeError(
                statusCode: "api_error",
                message: "Gemini quota API returned HTTP \(httpResponse.statusCode)."
            )
        }
        return data
    }

    private func fetchGeminiProjectID(accessToken: String) async -> String? {
        guard let endpoint = Self.geminiLoadCodeAssistEndpoint else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 6
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{\"metadata\":{\"ideType\":\"GEMINI_CLI\",\"pluginType\":\"GEMINI\"}}".utf8)

        guard let (data, response) = try? await geminiDataLoader(request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return nil
        }

        if let project = object["cloudaicompanionProject"] as? String {
            let trimmed = project.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let project = object["cloudaicompanionProject"] as? [String: Any] {
            if let value = project["id"] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let value = project["projectId"] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private func parseGeminiUsedFraction(data: Data) throws -> Double {
        let response: GeminiQuotaResponse
        do {
            response = try JSONDecoder().decode(GeminiQuotaResponse.self, from: data)
        } catch {
            throw GeminiProbeError(statusCode: "parse_error", message: "Could not decode Gemini quota response.")
        }

        guard let buckets = response.buckets, !buckets.isEmpty else {
            throw GeminiProbeError(statusCode: "parse_error", message: "Gemini quota response has no buckets.")
        }

        var minRemainingByModel: [String: Double] = [:]
        for bucket in buckets {
            guard let modelID = bucket.modelId, !modelID.isEmpty, let remaining = bucket.remainingFraction else {
                continue
            }
            let clamped = min(1, max(0, remaining))
            if let existing = minRemainingByModel[modelID] {
                minRemainingByModel[modelID] = min(existing, clamped)
            } else {
                minRemainingByModel[modelID] = clamped
            }
        }

        guard let lowestRemaining = minRemainingByModel.values.min() else {
            throw GeminiProbeError(statusCode: "parse_error", message: "No usable Gemini model quota found.")
        }

        return min(1, max(0, 1 - lowestRemaining))
    }

    private func loadGeminiCredentials(configRoot: URL) throws -> GeminiCredentials {
        let credentialsURL = configRoot.appendingPathComponent("oauth_creds.json")
        guard let data = try? Data(contentsOf: credentialsURL) else {
            throw GeminiProbeError(statusCode: "not_logged_in", message: "Gemini oauth_creds.json not found.")
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw GeminiProbeError(statusCode: "parse_error", message: "Gemini oauth_creds.json is invalid.")
        }

        guard let accessToken = object["access_token"] as? String,
              !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw GeminiProbeError(statusCode: "not_logged_in", message: "Gemini access_token is missing.")
        }

        let refreshToken = (object["refresh_token"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let idToken = (object["id_token"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let expiryRaw = Self.parseDouble(object["expiry_date"])
        let expiryDate = expiryRaw.map { Date(timeIntervalSince1970: $0 / 1000) }

        return GeminiCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken?.isEmpty == true ? nil : refreshToken,
            idToken: idToken?.isEmpty == true ? nil : idToken,
            expiryDate: expiryDate,
            credentialsURL: credentialsURL
        )
    }

    private func refreshGeminiAccessToken(
        configRoot: URL,
        refreshToken: String?,
        credentialsURL: URL
    ) async throws -> String {
        guard let refreshToken, !refreshToken.isEmpty else {
            throw GeminiProbeError(statusCode: "not_logged_in", message: "Gemini refresh_token is missing.")
        }
        guard let oauthCreds = extractGeminiOAuthClientCredentials() else {
            throw GeminiProbeError(
                statusCode: "api_error",
                message: "Could not extract Gemini CLI OAuth client configuration."
            )
        }
        guard let endpoint = Self.geminiRefreshEndpoint else {
            throw GeminiProbeError(statusCode: "api_error", message: "Gemini refresh endpoint is invalid.")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let formItems = [
            ("client_id", oauthCreds.clientId),
            ("client_secret", oauthCreds.clientSecret),
            ("refresh_token", refreshToken),
            ("grant_type", "refresh_token"),
        ]
        request.httpBody = Self.formURLEncoded(formItems).data(using: .utf8)

        let (data, response) = try await geminiDataLoader(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiProbeError(statusCode: "api_error", message: "Gemini token refresh response is invalid.")
        }
        guard httpResponse.statusCode == 200 else {
            throw GeminiProbeError(
                statusCode: "not_logged_in",
                message: "Gemini token refresh failed with HTTP \(httpResponse.statusCode)."
            )
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let accessToken = object["access_token"] as? String,
              !accessToken.isEmpty
        else {
            throw GeminiProbeError(statusCode: "parse_error", message: "Gemini token refresh payload is invalid.")
        }

        updateGeminiCredentialsFile(
            configRoot: configRoot,
            credentialsURL: credentialsURL,
            refreshResponse: object
        )
        return accessToken
    }

    private func updateGeminiCredentialsFile(
        configRoot _: URL,
        credentialsURL: URL,
        refreshResponse: [String: Any]
    ) {
        guard let existing = try? Data(contentsOf: credentialsURL),
              var object = (try? JSONSerialization.jsonObject(with: existing)) as? [String: Any]
        else {
            return
        }

        if let accessToken = refreshResponse["access_token"] {
            object["access_token"] = accessToken
        }
        if let expiresIn = Self.parseDouble(refreshResponse["expires_in"]) {
            object["expiry_date"] = (Date().timeIntervalSince1970 + expiresIn) * 1000
        }
        if let idToken = refreshResponse["id_token"] {
            object["id_token"] = idToken
        }

        if let updated = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]) {
            try? updated.write(to: credentialsURL, options: .atomic)
        }
    }

    private func extractGeminiOAuthClientCredentials() -> GeminiOAuthClientCredentials? {
        guard let geminiBinary = resolveGeminiBinaryPath() else { return nil }
        let resolvedBinary = Self.resolveSymlinkPath(geminiBinary)
        let binDirectory = (resolvedBinary as NSString).deletingLastPathComponent
        let baseDirectory = (binDirectory as NSString).deletingLastPathComponent

        let oauthFile = "dist/src/code_assist/oauth2.js"
        let possiblePaths = [
            "\(baseDirectory)/libexec/lib/node_modules/@google/gemini-cli/node_modules/@google/gemini-cli-core/\(oauthFile)",
            "\(baseDirectory)/lib/node_modules/@google/gemini-cli/node_modules/@google/gemini-cli-core/\(oauthFile)",
            "\(baseDirectory)/share/gemini-cli/node_modules/@google/gemini-cli-core/\(oauthFile)",
            "\(baseDirectory)/../gemini-cli-core/\(oauthFile)",
            "\(baseDirectory)/node_modules/@google/gemini-cli-core/\(oauthFile)",
        ]

        for path in possiblePaths {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            if let parsed = Self.parseGeminiOAuthClientCredentials(from: content) {
                return parsed
            }
        }
        return nil
    }

    private func resolveGeminiBinaryPath() -> String? {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["GEMINI_CLI_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !override.isEmpty {
            let expanded = NSString(string: override).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return expanded
            }
        }

        if let pathValue = environment["PATH"] {
            for directory in pathValue.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(directory))
                    .appendingPathComponent("gemini").path
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        let commonPaths = ["/opt/homebrew/bin/gemini", "/usr/local/bin/gemini", "/usr/bin/gemini"]
        return commonPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    private func resolvedGeminiConfigRoot() -> URL {
        if let existing = geminiConfigRoots.first(where: {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("settings.json").path)
                || FileManager.default.fileExists(atPath: $0.appendingPathComponent("oauth_creds.json").path)
        }) {
            return existing
        }

        if let first = geminiConfigRoots.first {
            return first
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini", isDirectory: true)
    }

    private func geminiAuthType(configRoot: URL) -> GeminiAuthType {
        let settingsURL = configRoot.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let security = object["security"] as? [String: Any],
              let auth = security["auth"] as? [String: Any],
              let selectedType = auth["selectedType"] as? String
        else {
            return .unknown
        }

        return GeminiAuthType(rawValue: selectedType) ?? .unknown
    }

    private func fetchGeminiUsageViaCLI() -> GeminiProbeResult {
        guard let executable = resolveGeminiBinaryPath() else {
            return GeminiProbeResult(
                usedFraction: nil,
                statusCode: "cli_error",
                message: "Gemini CLI is not installed."
            )
        }

        let argumentCandidates = [
            ["--stats"],
            ["/stats"],
            ["stats"],
        ]

        for arguments in argumentCandidates {
            guard let runResult = geminiCommandRunner(executable, arguments, 8) else { continue }
            let output = runResult.output
            if let usedFraction = Self.parseGeminiStatsUsedFraction(output) {
                return GeminiProbeResult(usedFraction: usedFraction, statusCode: "ok_cli", message: nil)
            }
            if Self.looksGeminiNotLoggedIn(output) {
                return GeminiProbeResult(
                    usedFraction: nil,
                    statusCode: "not_logged_in",
                    message: "Gemini CLI is not logged in."
                )
            }
        }

        return GeminiProbeResult(
            usedFraction: nil,
            statusCode: "cli_error",
            message: "Gemini CLI /stats output could not be parsed."
        )
    }

    // MARK: - Codex scan

    private func scanCodexFile(
        fileURL: URL,
        range: DayRange,
        providerCache: inout ProviderCache,
        state: inout CodexScanState
    ) {
        let path = fileURL.path
        let attributes = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let mtimeUnixMs = Int64(modifiedAt * 1000)
        let fileIdentity = Self.fileIdentityString(fileURL: fileURL)

        func dropCachedFile(_ cached: FileUsage?) {
            if let cached {
                applyDayTokens(providerCache: &providerCache, dayTokens: cached.dayTokens, sign: -1)
            }
            providerCache.files.removeValue(forKey: path)
        }

        if let fileIdentity, state.seenFileIds.contains(fileIdentity) {
            dropCachedFile(providerCache.files[path])
            return
        }

        let cached = providerCache.files[path]
        if let cachedSessionId = cached?.sessionId, state.seenSessionIds.contains(cachedSessionId) {
            dropCachedFile(cached)
            return
        }

        let needsSessionIdRefresh = cached != nil && cached?.sessionId == nil
        if let cached,
           cached.mtimeUnixMs == mtimeUnixMs,
           cached.size == size,
           !needsSessionIdRefresh
        {
            if let cachedSessionId = cached.sessionId {
                state.seenSessionIds.insert(cachedSessionId)
            }
            if let fileIdentity {
                state.seenFileIds.insert(fileIdentity)
            }
            return
        }

        if let cached, cached.sessionId != nil {
            let startOffset = cached.parsedBytes ?? cached.size
            let canIncremental = size > cached.size && startOffset > 0 && startOffset <= size && cached.lastTotals != nil
            if canIncremental {
                let delta = parseCodexFile(
                    fileURL: fileURL,
                    range: range,
                    startOffset: startOffset,
                    initialTotals: cached.lastTotals
                )
                let sessionId = delta.sessionId ?? cached.sessionId
                if let sessionId, state.seenSessionIds.contains(sessionId) {
                    dropCachedFile(cached)
                    return
                }

                if !delta.dayTokens.isEmpty {
                    applyDayTokens(providerCache: &providerCache, dayTokens: delta.dayTokens, sign: 1)
                }

                var mergedDays = cached.dayTokens
                mergeDayTokens(existing: &mergedDays, delta: delta.dayTokens)
                providerCache.files[path] = FileUsage(
                    mtimeUnixMs: mtimeUnixMs,
                    size: size,
                    dayTokens: mergedDays,
                    parsedBytes: delta.parsedBytes,
                    lastTotals: delta.lastTotals,
                    sessionId: sessionId,
                    fileIdentity: fileIdentity
                )

                if let sessionId {
                    state.seenSessionIds.insert(sessionId)
                }
                if let fileIdentity {
                    state.seenFileIds.insert(fileIdentity)
                }
                return
            }
        }

        if let cached {
            applyDayTokens(providerCache: &providerCache, dayTokens: cached.dayTokens, sign: -1)
        }

        let parsed = parseCodexFile(fileURL: fileURL, range: range)
        let sessionId = parsed.sessionId ?? cached?.sessionId
        if let sessionId, state.seenSessionIds.contains(sessionId) {
            providerCache.files.removeValue(forKey: path)
            return
        }

        let usage = FileUsage(
            mtimeUnixMs: mtimeUnixMs,
            size: size,
            dayTokens: parsed.dayTokens,
            parsedBytes: parsed.parsedBytes,
            lastTotals: parsed.lastTotals,
            sessionId: sessionId,
            fileIdentity: fileIdentity
        )
        providerCache.files[path] = usage
        applyDayTokens(providerCache: &providerCache, dayTokens: usage.dayTokens, sign: 1)

        if let sessionId {
            state.seenSessionIds.insert(sessionId)
        }
        if let fileIdentity {
            state.seenFileIds.insert(fileIdentity)
        }
    }

    private func parseCodexFile(
        fileURL: URL,
        range: DayRange,
        startOffset: Int64 = 0,
        initialTotals: CodexTotals? = nil
    ) -> CodexParseResult {
        var previousTotals = initialTotals
        var sessionId: String?
        var dayTokens: [String: Int] = [:]

        let maxLineBytes = 256 * 1024
        let prefixBytes = 32 * 1024
        let parsedBytes = (try? Self.scanJSONL(
            fileURL: fileURL,
            offset: startOffset,
            maxLineBytes: maxLineBytes,
            prefixBytes: prefixBytes,
            onLine: { line in
                guard !line.bytes.isEmpty else { return }
                guard !line.wasTruncated else { return }
                guard
                    line.bytes.containsAscii(#""type":"event_msg""#)
                        || line.bytes.containsAscii(#""type":"turn_context""#)
                        || line.bytes.containsAscii(#""type":"session_meta""#)
                else { return }

                if line.bytes.containsAscii(#""type":"event_msg""#),
                   !line.bytes.containsAscii(#""token_count""#) {
                    return
                }

                guard let object = (try? JSONSerialization.jsonObject(with: line.bytes)) as? [String: Any],
                      let type = object["type"] as? String else {
                    return
                }

                if type == "session_meta" {
                    if sessionId == nil {
                        let payload = object["payload"] as? [String: Any]
                        sessionId = payload?["session_id"] as? String
                            ?? payload?["sessionId"] as? String
                            ?? payload?["id"] as? String
                            ?? object["session_id"] as? String
                            ?? object["sessionId"] as? String
                            ?? object["id"] as? String
                    }
                    return
                }

                guard let timestampText = object["timestamp"] as? String else { return }
                guard let dayKey = Self.dayKeyFromTimestamp(timestampText) else { return }

                guard type == "event_msg" else { return }
                guard let payload = object["payload"] as? [String: Any] else { return }
                guard (payload["type"] as? String) == "token_count" else { return }

                let info = payload["info"] as? [String: Any]
                let totalUsage = info?["total_token_usage"] as? [String: Any]
                let lastUsage = info?["last_token_usage"] as? [String: Any]

                var deltaInput = 0
                var deltaOutput = 0

                if let totalUsage {
                    let input = Self.parseInteger(totalUsage["input_tokens"]) ?? 0
                    let cached = Self.parseInteger(totalUsage["cached_input_tokens"] ?? totalUsage["cache_read_input_tokens"]) ?? 0
                    let output = Self.parseInteger(totalUsage["output_tokens"]) ?? 0

                    let previous = previousTotals
                    deltaInput = max(0, input - (previous?.input ?? 0))
                    deltaOutput = max(0, output - (previous?.output ?? 0))
                    previousTotals = CodexTotals(input: input, cached: cached, output: output)
                } else if let lastUsage {
                    deltaInput = max(0, Self.parseInteger(lastUsage["input_tokens"]) ?? 0)
                    deltaOutput = max(0, Self.parseInteger(lastUsage["output_tokens"]) ?? 0)
                } else {
                    return
                }

                let tokenDelta = deltaInput + deltaOutput
                guard tokenDelta > 0 else { return }
                if DayRange.isInRange(dayKey: dayKey, since: range.scanSinceKey, until: range.scanUntilKey) {
                    dayTokens[dayKey, default: 0] += tokenDelta
                }
            }
        )) ?? startOffset

        return CodexParseResult(
            dayTokens: dayTokens,
            parsedBytes: parsedBytes,
            lastTotals: previousTotals,
            sessionId: sessionId
        )
    }

    private func listCodexSessionFiles(range: DayRange) -> [URL] {
        let roots = expandedCodexRoots()
        var seen = Set<String>()
        var files: [URL] = []

        for root in roots {
            let byDate = listCodexSessionFilesByDatePartition(
                root: root,
                scanSinceKey: range.scanSinceKey,
                scanUntilKey: range.scanUntilKey
            )
            let flat = listCodexSessionFilesFlat(
                root: root,
                scanSinceKey: range.scanSinceKey,
                scanUntilKey: range.scanUntilKey
            )

            for fileURL in (byDate + flat) where seen.insert(fileURL.path).inserted {
                files.append(fileURL)
            }
        }

        return files.sorted(by: { $0.path < $1.path })
    }

    private func expandedCodexRoots() -> [URL] {
        var roots: [URL] = []
        for root in codexSessionsRoots {
            roots.append(root)
            if root.lastPathComponent == "sessions" {
                roots.append(
                    root.deletingLastPathComponent()
                        .appendingPathComponent("archived_sessions", isDirectory: true)
                )
            }
        }
        return Self.uniqueStandardizedPaths(roots)
    }

    private func listCodexSessionFilesByDatePartition(
        root: URL,
        scanSinceKey: String,
        scanUntilKey: String
    ) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        var files: [URL] = []
        let untilDate = DayRange.parseDayKey(scanUntilKey) ?? Date()
        var date = DayRange.parseDayKey(scanSinceKey) ?? untilDate

        while date <= untilDate {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            let year = String(format: "%04d", components.year ?? 1970)
            let month = String(format: "%02d", components.month ?? 1)
            let day = String(format: "%02d", components.day ?? 1)

            let dayDirectory = root
                .appendingPathComponent(year, isDirectory: true)
                .appendingPathComponent(month, isDirectory: true)
                .appendingPathComponent(day, isDirectory: true)

            if let items = try? FileManager.default.contentsOfDirectory(
                at: dayDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for item in items where item.pathExtension.lowercased() == "jsonl" {
                    files.append(item)
                }
            }

            date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? untilDate.addingTimeInterval(1)
        }

        return files
    }

    private func listCodexSessionFilesFlat(
        root: URL,
        scanSinceKey: String,
        scanUntilKey: String
    ) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [URL] = []
        for item in items where item.pathExtension.lowercased() == "jsonl" {
            if let dayKey = Self.dayKeyFromFilename(item.lastPathComponent),
               !DayRange.isInRange(dayKey: dayKey, since: scanSinceKey, until: scanUntilKey) {
                continue
            }
            files.append(item)
        }

        return files
    }

    // MARK: - Claude scan

    private func scanClaudeFile(
        fileURL: URL,
        range: DayRange,
        providerCache: inout ProviderCache
    ) {
        let path = fileURL.path
        let attributes = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let mtimeUnixMs = Int64(modifiedAt * 1000)

        if let cached = providerCache.files[path],
           cached.mtimeUnixMs == mtimeUnixMs,
           cached.size == size {
            return
        }

        // Accuracy first: streamed assistant chunks may replay the same message/request
        // pair across scan boundaries, so we reparse full Claude files when they change.
        if let cached = providerCache.files[path] {
            applyDayTokens(providerCache: &providerCache, dayTokens: cached.dayTokens, sign: -1)
        }

        let parsed = parseClaudeFile(fileURL: fileURL, range: range)
        let usage = FileUsage(
            mtimeUnixMs: mtimeUnixMs,
            size: size,
            dayTokens: parsed.dayTokens,
            parsedBytes: parsed.parsedBytes,
            lastTotals: nil,
            sessionId: nil,
            fileIdentity: nil
        )
        providerCache.files[path] = usage
        applyDayTokens(providerCache: &providerCache, dayTokens: usage.dayTokens, sign: 1)
    }

    private func parseClaudeFile(
        fileURL: URL,
        range: DayRange,
        startOffset: Int64 = 0
    ) -> ClaudeParseResult {
        var dayTokens: [String: Int] = [:]
        var seenKeys = Set<String>()

        let maxLineBytes = 512 * 1024
        let prefixBytes = maxLineBytes
        let parsedBytes = (try? Self.scanJSONL(
            fileURL: fileURL,
            offset: startOffset,
            maxLineBytes: maxLineBytes,
            prefixBytes: prefixBytes,
            onLine: { line in
                guard !line.bytes.isEmpty else { return }
                guard !line.wasTruncated else { return }
                guard line.bytes.containsAscii(#""type":"assistant""#) else { return }
                guard line.bytes.containsAscii(#""usage""#) else { return }

                guard let object = (try? JSONSerialization.jsonObject(with: line.bytes)) as? [String: Any],
                      let type = object["type"] as? String,
                      type == "assistant"
                else { return }

                guard let timestampText = object["timestamp"] as? String else { return }
                guard let dayKey = Self.dayKeyFromTimestamp(timestampText) else { return }
                guard DayRange.isInRange(dayKey: dayKey, since: range.scanSinceKey, until: range.scanUntilKey) else {
                    return
                }

                guard let message = object["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else {
                    return
                }

                let messageId = message["id"] as? String
                let requestId = object["requestId"] as? String
                if let messageId, let requestId {
                    let dedupeKey = "\(messageId):\(requestId)"
                    if seenKeys.contains(dedupeKey) { return }
                    seenKeys.insert(dedupeKey)
                }

                let input = max(0, Self.parseInteger(usage["input_tokens"]) ?? 0)
                let cacheCreate = max(0, Self.parseInteger(usage["cache_creation_input_tokens"]) ?? 0)
                let cacheRead = max(0, Self.parseInteger(usage["cache_read_input_tokens"]) ?? 0)
                let output = max(0, Self.parseInteger(usage["output_tokens"]) ?? 0)
                let total = input + cacheCreate + cacheRead + output
                guard total > 0 else { return }

                dayTokens[dayKey, default: 0] += total
            }
        )) ?? startOffset

        return ClaudeParseResult(dayTokens: dayTokens, parsedBytes: parsedBytes)
    }

    private func listClaudeProjectFiles(modifiedAfter: Date) -> [URL] {
        let fileManager = FileManager.default
        var files: [URL] = []
        var seen = Set<String>()

        for root in claudeProjectsRoots {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "jsonl" else { continue }
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                      values.isRegularFile == true else {
                    continue
                }
                let modifiedAt = values.contentModificationDate ?? .distantPast
                guard modifiedAt >= modifiedAfter else { continue }
                if seen.insert(url.path).inserted {
                    files.append(url)
                }
            }
        }

        return files.sorted(by: { $0.path < $1.path })
    }

    // MARK: - Cache mutations

    private func applyDayTokens(providerCache: inout ProviderCache, dayTokens: [String: Int], sign: Int) {
        for (dayKey, tokenCount) in dayTokens {
            let previous = providerCache.days[dayKey] ?? 0
            let next = max(0, previous + (sign * tokenCount))
            if next == 0 {
                providerCache.days.removeValue(forKey: dayKey)
            } else {
                providerCache.days[dayKey] = next
            }
        }
    }

    private func mergeDayTokens(existing: inout [String: Int], delta: [String: Int]) {
        for (dayKey, tokenCount) in delta {
            let previous = existing[dayKey] ?? 0
            let next = max(0, previous + tokenCount)
            if next == 0 {
                existing.removeValue(forKey: dayKey)
            } else {
                existing[dayKey] = next
            }
        }
    }

    private func pruneDays(providerCache: inout ProviderCache, sinceKey: String, untilKey: String) {
        for dayKey in providerCache.days.keys
            where !DayRange.isInRange(dayKey: dayKey, since: sinceKey, until: untilKey) {
            providerCache.days.removeValue(forKey: dayKey)
        }
    }

    // MARK: - Persistence

    private static func loadCache(at url: URL) -> MonitorCache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let decoded = try? JSONDecoder().decode(MonitorCache.self, from: data) else { return nil }
        guard decoded.version == 1 else { return nil }
        return decoded
    }

    private func saveCache() {
        let directory = cacheURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(cache)
            let temporaryURL = directory.appendingPathComponent(".tmp-\(UUID().uuidString).json")
            try data.write(to: temporaryURL, options: [.atomic])
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                _ = try FileManager.default.replaceItemAt(cacheURL, withItemAt: temporaryURL)
            } else {
                do {
                    try FileManager.default.moveItem(at: temporaryURL, to: cacheURL)
                } catch {
                    if FileManager.default.fileExists(atPath: cacheURL.path) {
                        _ = try FileManager.default.replaceItemAt(cacheURL, withItemAt: temporaryURL)
                    } else {
                        throw error
                    }
                }
            }
        } catch {
            Log.storage.warning("Failed to save external usage cache: \(error.localizedDescription)")
        }
    }

    // MARK: - JSONL helpers

    @discardableResult
    private static func scanJSONL(
        fileURL: URL,
        offset: Int64 = 0,
        maxLineBytes: Int,
        prefixBytes: Int,
        onLine: (JSONLLine) -> Void
    ) throws -> Int64 {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let startOffset = max(0, offset)
        if startOffset > 0 {
            try handle.seek(toOffset: UInt64(startOffset))
        }

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)

        var currentLine = Data()
        currentLine.reserveCapacity(4 * 1024)
        var lineBytes = 0
        var truncated = false
        var bytesRead: Int64 = 0

        func flushLine() {
            guard lineBytes > 0 else { return }
            onLine(JSONLLine(bytes: currentLine, wasTruncated: truncated))
            currentLine.removeAll(keepingCapacity: true)
            lineBytes = 0
            truncated = false
        }

        while true {
            let chunk = try handle.read(upToCount: 256 * 1024) ?? Data()
            if chunk.isEmpty {
                if !buffer.isEmpty {
                    lineBytes += buffer.count
                    if !truncated {
                        if lineBytes > maxLineBytes || lineBytes > prefixBytes {
                            truncated = true
                            currentLine.removeAll(keepingCapacity: true)
                        } else {
                            currentLine.append(buffer)
                        }
                    }
                    buffer.removeAll(keepingCapacity: true)
                }
                flushLine()
                break
            }

            bytesRead += Int64(chunk.count)
            buffer.append(chunk)

            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let linePart = buffer[..<newlineIndex]
                buffer.removeSubrange(...newlineIndex)

                lineBytes += linePart.count
                if !truncated {
                    if lineBytes > maxLineBytes || lineBytes > prefixBytes {
                        truncated = true
                        currentLine.removeAll(keepingCapacity: true)
                    } else {
                        currentLine.append(contentsOf: linePart)
                    }
                }
                flushLine()
            }
        }

        return startOffset + bytesRead
    }

    // MARK: - Parse helpers

    private static func parseInteger(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let integer = value as? Int { return integer }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let integer = Int(trimmed) { return integer }
            if let double = Double(trimmed) { return Int(double.rounded()) }
        }
        return nil
    }

    private static func parseDouble(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let double = value as? Double { return double }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(trimmed)
        }
        return nil
    }

    private static func parseGeminiOAuthClientCredentials(from content: String) -> GeminiOAuthClientCredentials? {
        let clientIDPattern = #"OAUTH_CLIENT_ID\s*=\s*['"]([\w\-\.]+)['"]\s*;"#
        let clientSecretPattern = #"OAUTH_CLIENT_SECRET\s*=\s*['"]([\w\-]+)['"]\s*;"#

        guard let clientIDRegex = try? NSRegularExpression(pattern: clientIDPattern),
              let clientSecretRegex = try? NSRegularExpression(pattern: clientSecretPattern)
        else {
            return nil
        }

        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let clientIDMatch = clientIDRegex.firstMatch(in: content, range: range),
              let clientIDRange = Range(clientIDMatch.range(at: 1), in: content),
              let clientSecretMatch = clientSecretRegex.firstMatch(in: content, range: range),
              let clientSecretRange = Range(clientSecretMatch.range(at: 1), in: content)
        else {
            return nil
        }

        return GeminiOAuthClientCredentials(
            clientId: String(content[clientIDRange]),
            clientSecret: String(content[clientSecretRange])
        )
    }

    private static func resolveSymlinkPath(_ path: String) -> String {
        let fileManager = FileManager.default
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: path) else {
            return path
        }
        if destination.hasPrefix("/") {
            return destination
        }
        let directory = (path as NSString).deletingLastPathComponent
        return (directory as NSString).appendingPathComponent(destination)
    }

    private static func formURLEncoded(_ pairs: [(String, String)]) -> String {
        pairs.map { key, value in
            let encodedKey = Self.urlEncodeFormComponent(key)
            let encodedValue = Self.urlEncodeFormComponent(value)
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
    }

    private static func urlEncodeFormComponent(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func parseGeminiStatsUsedFraction(_ rawText: String) -> Double? {
        let stripped = Self.stripANSICodes(rawText)
        let pattern = #"(gemini[-\w.]+)\s+[\d-]+\s+([0-9]+(?:\.[0-9]+)?)\s*%\s*\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        var minPercentLeft: Double?
        for line in stripped.split(whereSeparator: \.isNewline) {
            let cleanLine = String(line).replacingOccurrences(of: "│", with: " ")
            let range = NSRange(cleanLine.startIndex..<cleanLine.endIndex, in: cleanLine)
            guard let match = regex.firstMatch(in: cleanLine, range: range),
                  let percentRange = Range(match.range(at: 2), in: cleanLine),
                  let percentLeft = Double(cleanLine[percentRange])
            else {
                continue
            }

            if let current = minPercentLeft {
                minPercentLeft = min(current, percentLeft)
            } else {
                minPercentLeft = percentLeft
            }
        }

        guard let minPercentLeft else { return nil }
        let remaining = min(100, max(0, minPercentLeft))
        return min(1, max(0, 1 - (remaining / 100)))
    }

    private static func looksGeminiNotLoggedIn(_ text: String) -> Bool {
        let lower = stripANSICodes(text).lowercased()
        if lower.contains("login with google") { return true }
        if lower.contains("waiting for auth") { return true }
        if lower.contains("run 'gemini' in terminal to authenticate") { return true }
        return false
    }

    private static func stripANSICodes(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\u{001B}\[[0-9;]*[A-Za-z]"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func runProcess(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> (output: String, exitCode: Int32)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }

        do {
            try process.run()
        } catch {
            return nil
        }

        let waitResult = group.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            process.terminate()
            _ = group.wait(timeout: .now() + 1)
            return nil
        }

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let outputText = String(data: outputData + errorData, encoding: .utf8) ?? ""
        return (outputText, process.terminationStatus)
    }

    private static func dayKeyFromFilename(_ filename: String) -> String? {
        guard let regex = codexFilenameDateRegex else { return nil }
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        guard let match = regex.firstMatch(in: filename, range: range) else { return nil }
        guard let matchRange = Range(match.range(at: 1), in: filename) else { return nil }
        return String(filename[matchRange])
    }

    private static func fileIdentityString(fileURL: URL) -> String? {
        guard let values = try? fileURL.resourceValues(forKeys: [.fileResourceIdentifierKey]) else { return nil }
        guard let identifier = values.fileResourceIdentifier else { return nil }
        if let data = identifier as? Data {
            return data.base64EncodedString()
        }
        return String(describing: identifier)
    }

    private static func dayKeyFromTimestamp(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let unix = Double(trimmed), let date = parseUnixTimestamp(unix) {
            return DayRange.dayKey(from: date)
        }

        let fractionalISO = ISO8601DateFormatter()
        fractionalISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let basicISO = ISO8601DateFormatter()
        basicISO.formatOptions = [.withInternetDateTime]

        if let parsed = fractionalISO.date(from: trimmed)
            ?? basicISO.date(from: trimmed) {
            return DayRange.dayKey(from: parsed)
        }

        for format in fallbackDateFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let parsed = formatter.date(from: trimmed) {
                return DayRange.dayKey(from: parsed)
            }
        }

        if trimmed.count >= 10 {
            let prefix = String(trimmed.prefix(10))
            if prefix.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil {
                return prefix
            }
        }
        return nil
    }

    private static func parseUnixTimestamp(_ raw: Double) -> Date? {
        guard raw > 0 else { return nil }
        if raw > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: raw / 1000.0)
        }
        if raw > 1_000_000_000 {
            return Date(timeIntervalSince1970: raw)
        }
        return nil
    }

    private static func uniqueStandardizedPaths(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var output: [URL] = []
        for url in urls {
            let normalized = url.standardizedFileURL
            if seen.insert(normalized.path).inserted {
                output.append(normalized)
            }
        }
        return output
    }
}

private extension Data {
    func containsAscii(_ needle: String) -> Bool {
        guard let data = needle.data(using: .utf8) else { return false }
        return range(of: data) != nil
    }
}
