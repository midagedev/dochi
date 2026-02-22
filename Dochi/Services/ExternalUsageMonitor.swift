import Foundation
import os

enum ExternalUsageProvider: String, Sendable {
    case codex
    case claude
    case gemini
}

struct ExternalUsageRateWindow: Codable, Sendable, Equatable {
    let label: String
    let usedPercent: Double
    let windowMinutes: Int?
    let resetsAt: Date?
    let resetDescription: String?

    init(
        label: String,
        usedPercent: Double,
        windowMinutes: Int? = nil,
        resetsAt: Date? = nil,
        resetDescription: String? = nil
    ) {
        self.label = label
        self.usedPercent = min(100, max(0, usedPercent))
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
    }
}

struct ExternalUsageProviderStatus: Sendable, Equatable {
    let code: String
    let message: String?
    let lastCollectedAt: Date?
    let primaryWindow: ExternalUsageRateWindow?
    let secondaryWindow: ExternalUsageRateWindow?
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
        var primaryWindow: ExternalUsageRateWindow? = nil
        var secondaryWindow: ExternalUsageRateWindow? = nil
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
        let windowSample: ExternalRateWindowSample?
    }

    private struct ClaudeParseResult: Sendable {
        let dayTokens: [String: Int]
        let parsedBytes: Int64
    }

    private struct ClaudeWindowProbeResult: Sendable {
        let statusCode: String
        let message: String?
        let primaryWindow: ExternalUsageRateWindow?
        let secondaryWindow: ExternalUsageRateWindow?
    }

    private struct ExternalRateWindowSample: Sendable {
        let sourcePriority: Int
        let observedAtUnixMs: Int64
        let primaryWindow: ExternalUsageRateWindow?
        let secondaryWindow: ExternalUsageRateWindow?
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
        let primaryWindow: ExternalUsageRateWindow?
        let secondaryWindow: ExternalUsageRateWindow?
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
        let resetTime: String?
    }

    private struct GeminiQuotaResponse: Decodable {
        let buckets: [GeminiQuotaBucket]?
    }

    private struct GeminiQuotaParseResult: Sendable {
        let usedFraction: Double
        let primaryWindow: ExternalUsageRateWindow?
        let secondaryWindow: ExternalUsageRateWindow?
    }

    private struct GeminiStatsParseResult: Sendable {
        let usedFraction: Double
        let primaryWindow: ExternalUsageRateWindow?
        let secondaryWindow: ExternalUsageRateWindow?
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
    private let claudeCommandRunner: @Sendable (_ executable: String, _ arguments: [String], _ timeout: TimeInterval) -> (output: String, exitCode: Int32)?
    private let claudeCommandRunnerIsInjected: Bool
    private let geminiDataLoader: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let geminiCommandRunner: @Sendable (_ executable: String, _ arguments: [String], _ timeout: TimeInterval) -> (output: String, exitCode: Int32)?

    private var cache: MonitorCache

    init(
        codexSessionsRoots: [URL],
        claudeProjectsRoots: [URL],
        geminiConfigRoots: [URL] = [],
        cacheURL: URL,
        refreshMinIntervalSeconds: TimeInterval = 60,
        claudeCommandRunner: (@Sendable (_ executable: String, _ arguments: [String], _ timeout: TimeInterval) -> (output: String, exitCode: Int32)?)? = nil,
        geminiDataLoader: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil,
        geminiCommandRunner: (@Sendable (_ executable: String, _ arguments: [String], _ timeout: TimeInterval) -> (output: String, exitCode: Int32)?)? = nil
    ) {
        self.codexSessionsRoots = Self.uniqueStandardizedPaths(codexSessionsRoots)
        self.claudeProjectsRoots = Self.uniqueStandardizedPaths(claudeProjectsRoots)
        self.geminiConfigRoots = Self.uniqueStandardizedPaths(geminiConfigRoots)
        self.cacheURL = cacheURL
        self.refreshMinIntervalSeconds = max(0, refreshMinIntervalSeconds)
        self.claudeCommandRunnerIsInjected = claudeCommandRunner != nil
        self.claudeCommandRunner = claudeCommandRunner ?? { executable, arguments, timeout in
            Self.runProcess(executable: executable, arguments: arguments, timeout: timeout)
        }
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
        guard let providerCache = cache.providers[key] else {
            return nil
        }
        let lastCollectedAt: Date? = providerCache.lastScanUnixMs > 0
            ? Date(timeIntervalSince1970: Double(providerCache.lastScanUnixMs) / 1000.0)
            : nil
        guard let code = providerCache.lastStatus ?? (lastCollectedAt != nil ? "unknown" : nil) else {
            return nil
        }
        return ExternalUsageProviderStatus(
            code: code,
            message: providerCache.lastMessage,
            lastCollectedAt: lastCollectedAt,
            primaryWindow: providerCache.primaryWindow,
            secondaryWindow: providerCache.secondaryWindow
        )
    }

    // MARK: - Refresh

    private func refreshCodex(since startDate: Date, now: Date) {
        let key = ExternalUsageProvider.codex.rawValue
        var providerCache = cache.providers[key] ?? ProviderCache()

        guard shouldRefresh(lastScanUnixMs: providerCache.lastScanUnixMs, now: now) else { return }

        let range = DayRange(since: startDate, until: now)
        let files = listCodexSessionFiles(range: range)
        let touchedPaths = Set(files.map(\.path))
        let requiresWindowBackfill = providerCache.primaryWindow == nil && providerCache.secondaryWindow == nil

        var state = CodexScanState()
        var latestWindowSample: ExternalRateWindowSample?
        for fileURL in files {
            scanCodexFile(
                fileURL: fileURL,
                range: range,
                providerCache: &providerCache,
                state: &state,
                requiresWindowBackfill: requiresWindowBackfill,
                latestWindowSample: &latestWindowSample
            )
        }

        for stalePath in providerCache.files.keys where !touchedPaths.contains(stalePath) {
            if let old = providerCache.files[stalePath] {
                applyDayTokens(providerCache: &providerCache, dayTokens: old.dayTokens, sign: -1)
            }
            providerCache.files.removeValue(forKey: stalePath)
        }

        pruneDays(providerCache: &providerCache, sinceKey: range.scanSinceKey, untilKey: range.scanUntilKey)
        if let latestWindowSample {
            providerCache.primaryWindow = latestWindowSample.primaryWindow
            providerCache.secondaryWindow = latestWindowSample.secondaryWindow
        }
        providerCache.lastStatus = "ok_log_scan"
        providerCache.lastMessage = nil
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
        let windowProbe = probeClaudeUsageWindows(now: now)
        providerCache.primaryWindow = windowProbe.primaryWindow
        providerCache.secondaryWindow = windowProbe.secondaryWindow
        providerCache.lastStatus = windowProbe.statusCode
        providerCache.lastMessage = windowProbe.message
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
        providerCache.primaryWindow = result.primaryWindow
        providerCache.secondaryWindow = result.secondaryWindow
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
                message: "Gemini auth type 'api-key' is not supported for usage monitoring.",
                primaryWindow: nil,
                secondaryWindow: nil
            )
        case .vertexAI:
            return GeminiProbeResult(
                usedFraction: nil,
                statusCode: "unsupported_auth_type",
                message: "Gemini auth type 'vertex-ai' is not supported for usage monitoring.",
                primaryWindow: nil,
                secondaryWindow: nil
            )
        case .oauthPersonal, .unknown:
            break
        }

        do {
            let parsed = try await fetchGeminiUsageViaAPI(configRoot: configRoot, now: now)
            return GeminiProbeResult(
                usedFraction: parsed.usedFraction,
                statusCode: "ok_api",
                message: nil,
                primaryWindow: parsed.primaryWindow,
                secondaryWindow: parsed.secondaryWindow
            )
        } catch let apiError as GeminiProbeError {
            let fallback = fetchGeminiUsageViaCLI(now: now)
            if let fallbackUsed = fallback.usedFraction {
                return GeminiProbeResult(
                    usedFraction: fallbackUsed,
                    statusCode: "ok_cli",
                    message: fallback.message,
                    primaryWindow: fallback.primaryWindow,
                    secondaryWindow: fallback.secondaryWindow
                )
            }
            return GeminiProbeResult(
                usedFraction: nil,
                statusCode: fallback.statusCode == "not_logged_in" ? fallback.statusCode : apiError.statusCode,
                message: fallback.statusCode == "not_logged_in" ? fallback.message : apiError.message,
                primaryWindow: fallback.primaryWindow,
                secondaryWindow: fallback.secondaryWindow
            )
        } catch {
            let fallback = fetchGeminiUsageViaCLI(now: now)
            if let fallbackUsed = fallback.usedFraction {
                return GeminiProbeResult(
                    usedFraction: fallbackUsed,
                    statusCode: "ok_cli",
                    message: fallback.message,
                    primaryWindow: fallback.primaryWindow,
                    secondaryWindow: fallback.secondaryWindow
                )
            }
            return GeminiProbeResult(
                usedFraction: nil,
                statusCode: fallback.statusCode == "not_logged_in" ? fallback.statusCode : "api_error",
                message: fallback.statusCode == "not_logged_in" ? fallback.message : error.localizedDescription,
                primaryWindow: fallback.primaryWindow,
                secondaryWindow: fallback.secondaryWindow
            )
        }
    }

    private func fetchGeminiUsageViaAPI(configRoot: URL, now: Date) async throws -> GeminiQuotaParseResult {
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
        return try parseGeminiUsage(data: quotaData)
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

    private func parseGeminiUsage(data: Data) throws -> GeminiQuotaParseResult {
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
        var representativeBucketByModel: [String: GeminiQuotaBucket] = [:]
        for (index, bucket) in buckets.enumerated() {
            guard let remaining = bucket.remainingFraction else {
                continue
            }
            let modelIDRaw = bucket.modelId?.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelID = (modelIDRaw?.isEmpty == false ? modelIDRaw! : "bucket-\(index)")
            let clamped = min(1, max(0, remaining))
            if let existing = minRemainingByModel[modelID] {
                if clamped <= existing {
                    minRemainingByModel[modelID] = clamped
                    representativeBucketByModel[modelID] = bucket
                }
            } else {
                minRemainingByModel[modelID] = clamped
                representativeBucketByModel[modelID] = bucket
            }
        }

        guard let limitingModel = minRemainingByModel.min(by: { $0.value < $1.value }) else {
            throw GeminiProbeError(statusCode: "parse_error", message: "No usable Gemini model quota found.")
        }

        let usedFraction = min(1, max(0, 1 - limitingModel.value))
        let limitingBucket = representativeBucketByModel[limitingModel.key]
        let resetAt = Self.parseDateFlexible(limitingBucket?.resetTime)

        let primaryWindow = ExternalUsageRateWindow(
            label: "Gemini quota",
            usedPercent: usedFraction * 100,
            windowMinutes: nil,
            resetsAt: resetAt,
            resetDescription: nil
        )

        return GeminiQuotaParseResult(
            usedFraction: usedFraction,
            primaryWindow: primaryWindow,
            secondaryWindow: nil
        )
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

    private func fetchGeminiUsageViaCLI(now: Date) -> GeminiProbeResult {
        guard let executable = resolveGeminiBinaryPath() else {
            return GeminiProbeResult(
                usedFraction: nil,
                statusCode: "cli_error",
                message: "Gemini CLI is not installed.",
                primaryWindow: nil,
                secondaryWindow: nil
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
            if let parsed = Self.parseGeminiStats(output, now: now) {
                return GeminiProbeResult(
                    usedFraction: parsed.usedFraction,
                    statusCode: "ok_cli",
                    message: nil,
                    primaryWindow: parsed.primaryWindow,
                    secondaryWindow: parsed.secondaryWindow
                )
            }
            if Self.looksGeminiNotLoggedIn(output) {
                return GeminiProbeResult(
                    usedFraction: nil,
                    statusCode: "not_logged_in",
                    message: "Gemini CLI is not logged in.",
                    primaryWindow: nil,
                    secondaryWindow: nil
                )
            }
        }

        return GeminiProbeResult(
            usedFraction: nil,
            statusCode: "cli_error",
            message: "Gemini CLI /stats output could not be parsed.",
            primaryWindow: nil,
            secondaryWindow: nil
        )
    }

    // MARK: - Codex scan

    private func scanCodexFile(
        fileURL: URL,
        range: DayRange,
        providerCache: inout ProviderCache,
        state: inout CodexScanState,
        requiresWindowBackfill: Bool,
        latestWindowSample: inout ExternalRateWindowSample?
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
            if requiresWindowBackfill {
                let parsedForWindow = parseCodexFile(fileURL: fileURL, range: range)
                if let sample = parsedForWindow.windowSample {
                    latestWindowSample = Self.preferredWindowSample(current: latestWindowSample, candidate: sample)
                }
            }
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
                if let sample = delta.windowSample {
                    latestWindowSample = Self.preferredWindowSample(current: latestWindowSample, candidate: sample)
                }
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
        if let sample = parsed.windowSample {
            latestWindowSample = Self.preferredWindowSample(current: latestWindowSample, candidate: sample)
        }
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
        var latestWindowSample: ExternalRateWindowSample?

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

                guard type == "event_msg" else { return }
                guard let payload = object["payload"] as? [String: Any] else { return }
                guard (payload["type"] as? String) == "token_count" else { return }

                let timestampText = object["timestamp"] as? String
                if let rateLimits = payload["rate_limits"] as? [String: Any],
                   let sample = Self.parseCodexRateWindowSample(rateLimits: rateLimits, timestampText: timestampText) {
                    latestWindowSample = Self.preferredWindowSample(current: latestWindowSample, candidate: sample)
                }

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

                guard let timestampText, let dayKey = Self.dayKeyFromTimestamp(timestampText) else { return }
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
            sessionId: sessionId,
            windowSample: latestWindowSample
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

    // MARK: - Claude usage probe

    private func probeClaudeUsageWindows(now: Date) -> ClaudeWindowProbeResult {
        let scriptPath = "/usr/bin/script"
        guard claudeCommandRunnerIsInjected || FileManager.default.isExecutableFile(atPath: scriptPath) else {
            return ClaudeWindowProbeResult(
                statusCode: "window_probe_unavailable",
                message: "script 실행기가 없어 Claude 세션/주간 윈도우를 수집할 수 없습니다.",
                primaryWindow: nil,
                secondaryWindow: nil
            )
        }

        let timeout: TimeInterval = 24
        let claudeBinary = resolvedClaudeExecutable()

        let runResult: (output: String, exitCode: Int32)?
        if claudeCommandRunnerIsInjected {
            runResult = claudeCommandRunner(scriptPath, [claudeBinary], timeout + 4)
        } else {
            runResult = Self.runClaudeUsageScriptProbe(
                scriptExecutable: scriptPath,
                claudeBinary: claudeBinary,
                timeout: timeout + 4
            )
        }

        guard let runResult else {
            return ClaudeWindowProbeResult(
                statusCode: "window_probe_failed",
                message: "Claude CLI /usage 수집 실행에 실패했습니다.",
                primaryWindow: nil,
                secondaryWindow: nil
            )
        }

        let parsed = Self.parseClaudeUsageProbeOutput(runResult.output, now: now)
        if parsed.statusCode == "ok_log_scan_cli" {
            return parsed
        }

        if runResult.exitCode != 0 {
            let base = parsed.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = base?.isEmpty == false ? base! : "Claude CLI /usage 수집을 해석하지 못했습니다."
            return ClaudeWindowProbeResult(
                statusCode: parsed.statusCode,
                message: "\(detail) (exit \(runResult.exitCode))",
                primaryWindow: nil,
                secondaryWindow: nil
            )
        }
        return parsed
    }

    private static func runClaudeUsageScriptProbe(
        scriptExecutable: String,
        claudeBinary: String,
        timeout: TimeInterval
    ) -> (output: String, exitCode: Int32)? {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("dochi-claude-usage-\(UUID().uuidString)", isDirectory: true)
        let transcriptURL = tempRoot.appendingPathComponent("usage-transcript.log")

        do {
            try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        } catch {
            try? fileManager.removeItem(at: tempRoot)
            return nil
        }
        defer { try? fileManager.removeItem(at: tempRoot) }

        let escapedTranscript = shellSingleQuoted(transcriptURL.path)
        let escapedBinary = shellSingleQuoted(claudeBinary)
        let escapedScript = shellSingleQuoted(scriptExecutable)
        let command = """
        { printf '/usage\\r'; sleep 2; printf '\\r'; sleep 6; printf '\\033'; sleep 1; printf '/exit\\r'; sleep 1; } | \(escapedScript) -q \(escapedTranscript) \(escapedBinary) --allowed-tools ""
        """

        let shellResult = runProcess(
            executable: "/bin/zsh",
            arguments: ["-lc", command],
            timeout: timeout,
            captureOutputOnTimeout: true
        )

        let transcriptText: String = {
            guard let data = try? Data(contentsOf: transcriptURL) else { return "" }
            return String(decoding: data, as: UTF8.self)
        }()

        if shellResult == nil && transcriptText.isEmpty {
            return nil
        }

        let mergedOutput: String = {
            var chunks: [String] = []
            if let shellOutput = shellResult?.output.trimmingCharacters(in: .whitespacesAndNewlines),
               !shellOutput.isEmpty {
                chunks.append(shellOutput)
            }
            let transcriptTrimmed = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !transcriptTrimmed.isEmpty {
                chunks.append(transcriptTrimmed)
            }
            return chunks.joined(separator: "\n")
        }()

        return (
            output: mergedOutput,
            exitCode: shellResult?.exitCode ?? -1
        )
    }

    private func resolvedClaudeExecutable() -> String {
        let env = ProcessInfo.processInfo.environment
        if let custom = env["CLAUDE_CLI_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !custom.isEmpty {
            return custom
        }
        return "claude"
    }

    private static func parseClaudeUsageProbeOutput(_ rawText: String, now: Date) -> ClaudeWindowProbeResult {
        let clean = stripANSICodes(rawText)
            .replacingOccurrences(of: "\r", with: "\n")

        if looksClaudeNotLoggedIn(clean) {
            return ClaudeWindowProbeResult(
                statusCode: "not_logged_in",
                message: "Claude CLI 인증이 필요합니다. 터미널에서 claude login 후 다시 시도하세요.",
                primaryWindow: nil,
                secondaryWindow: nil
            )
        }

        if let usageError = parseClaudeUsageError(clean) {
            return ClaudeWindowProbeResult(
                statusCode: "window_probe_failed",
                message: usageError,
                primaryWindow: nil,
                secondaryWindow: nil
            )
        }

        let usagePanel = trimToLatestClaudeUsagePanel(clean)
        let lines = usagePanel.components(separatedBy: .newlines)

        let hasSessionLabel = lines.contains {
            lineContainsClaudeLabel(
                normalizedLine: normalizedForLabelSearch($0),
                normalizedLabel: normalizedForLabelSearch("Current session")
            )
        }
        let hasWeeklyLabel = lines.contains {
            lineContainsClaudeLabel(
                normalizedLine: normalizedForLabelSearch($0),
                normalizedLabel: normalizedForLabelSearch("Current week")
            )
        }
        let hasUsagePanelHint = lines.contains {
            let compact = compactForLabelSearch(normalizedForLabelSearch($0))
            return compact.contains("settingsusage") || compact.contains("esctocancel")
        }

        var sessionLeft = extractClaudePercent(
            labelCandidates: ["Current session"],
            lines: lines
        )
        var weeklyLeft = extractClaudePercent(
            labelCandidates: ["Current week (all models)", "Current week"],
            lines: lines
        )

        let orderedFallback = inferClaudeWindowsFromOrderedPercents(
            lines: lines,
            allowUnlabeledFallback: hasUsagePanelHint
        )
        var usedOrderedFallback = false
        if sessionLeft == nil, let inferredSession = orderedFallback.sessionLeft {
            sessionLeft = inferredSession
            usedOrderedFallback = true
        }
        if weeklyLeft == nil, let inferredWeekly = orderedFallback.weeklyLeft {
            weeklyLeft = inferredWeekly
            usedOrderedFallback = true
        }

        guard let sessionLeft else {
            if let weeklyBannerWindow = parseClaudeWeeklyBannerWindow(text: clean, now: now) {
                return ClaudeWindowProbeResult(
                    statusCode: "ok_log_scan_cli_partial",
                    message: "Claude CLI에서 /usage 패널 대신 주간 사용 배너를 감지해 주간 윈도우만 수집했습니다.",
                    primaryWindow: nil,
                    secondaryWindow: weeklyBannerWindow
                )
            }
            return ClaudeWindowProbeResult(
                statusCode: "window_probe_failed",
                message: "Claude /usage 출력에서 Current session 사용량을 찾지 못했습니다.",
                primaryWindow: nil,
                secondaryWindow: nil
            )
        }

        let sessionResetRaw = extractClaudeReset(
            labelCandidates: ["Current session"],
            lines: lines
        ) ?? orderedFallback.sessionReset
        let weeklyResetRaw = extractClaudeReset(
            labelCandidates: ["Current week (all models)", "Current week"],
            lines: lines
        ) ?? orderedFallback.weeklyReset

        let sessionReset = parseClaudeResetInfo(sessionResetRaw, now: now)
        let weeklyReset = parseClaudeResetInfo(weeklyResetRaw, now: now)

        let primaryWindow = ExternalUsageRateWindow(
            label: "Session",
            usedPercent: max(0, 100 - Double(sessionLeft)),
            windowMinutes: 300,
            resetsAt: sessionReset.resetsAt,
            resetDescription: sessionReset.resetDescription
        )

        let secondaryWindow: ExternalUsageRateWindow? = weeklyLeft.map { percentLeft in
            ExternalUsageRateWindow(
                label: "Weekly",
                usedPercent: max(0, 100 - Double(percentLeft)),
                windowMinutes: 10_080,
                resetsAt: weeklyReset.resetsAt,
                resetDescription: weeklyReset.resetDescription
            )
        }

        let incompleteLabels = !hasSessionLabel || (weeklyLeft != nil && !hasWeeklyLabel)
        if incompleteLabels || usedOrderedFallback {
            return ClaudeWindowProbeResult(
                statusCode: "ok_log_scan_cli_partial",
                message: "Claude /usage 라벨 인식이 불완전해 퍼센트 기반으로 윈도우를 복원했습니다.",
                primaryWindow: primaryWindow,
                secondaryWindow: secondaryWindow
            )
        }

        return ClaudeWindowProbeResult(
            statusCode: "ok_log_scan_cli",
            message: nil,
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow
        )
    }

    private static func trimToLatestClaudeUsagePanel(_ text: String) -> String {
        if let sessionRange = text.range(of: "Current session", options: [.caseInsensitive, .backwards]) {
            let prefix = text[..<sessionRange.lowerBound]
            let start = prefix.range(of: "Settings:", options: [.caseInsensitive, .backwards])?.lowerBound ?? text.startIndex
            return String(text[start...])
        }

        if let settingsRange = text.range(of: "Settings:", options: [.caseInsensitive, .backwards]) {
            return String(text[settingsRange.lowerBound...])
        }

        return text
    }

    private static func normalizedForLabelSearch(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func compactForLabelSearch(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]"#, with: "", options: .regularExpression)
    }

    private static func lineContainsClaudeLabel(
        normalizedLine: String,
        normalizedLabel: String
    ) -> Bool {
        if normalizedLine.contains(normalizedLabel) { return true }

        let compactLine = compactForLabelSearch(normalizedLine)
        let compactLabel = compactForLabelSearch(normalizedLabel)
        if !compactLabel.isEmpty, compactLine.contains(compactLabel) {
            return true
        }

        if compactLabel == "currentsession" {
            return compactLine.contains("session") &&
                (compactLine.contains("current") || compactLine.contains("curre"))
        }

        if compactLabel == "currentweek" {
            return compactLine.contains("week") &&
                (compactLine.contains("current") || compactLine.contains("curre"))
        }

        if compactLabel == "currentweekallmodels" {
            return compactLine.contains("week") &&
                (compactLine.contains("allmodels") || compactLine.contains("allmodel"))
        }

        return false
    }

    private static func inferClaudeWindowsFromOrderedPercents(
        lines: [String],
        allowUnlabeledFallback: Bool
    ) -> (sessionLeft: Int?, weeklyLeft: Int?, sessionReset: String?, weeklyReset: String?) {
        guard allowUnlabeledFallback else { return (nil, nil, nil, nil) }

        var indexedPercents: [(index: Int, leftPercent: Int)] = []
        for (index, line) in lines.enumerated() {
            guard let leftPercent = parseClaudePercentLeft(from: line) else { continue }
            let normalized = normalizedForLabelSearch(line)
            let compact = compactForLabelSearch(normalized)

            // Footer banner can leak into transcript after dismissing /usage.
            if compact.contains("weeklylimit"), !compact.contains("currentweek") {
                continue
            }

            if let last = indexedPercents.last,
               last.leftPercent == leftPercent,
               index - last.index <= 2 {
                continue
            }

            indexedPercents.append((index, leftPercent))
        }

        guard indexedPercents.indices.contains(0) else { return (nil, nil, nil, nil) }
        let sessionEntry = indexedPercents[0]
        let weeklyEntry = indexedPercents.indices.contains(1) ? indexedPercents[1] : nil

        func scanReset(after index: Int) -> String? {
            let upper = min(lines.count, index + 8)
            for candidate in lines[index..<upper] {
                if let reset = resetFromLine(candidate) {
                    return reset
                }
            }
            return nil
        }

        return (
            sessionLeft: sessionEntry.leftPercent,
            weeklyLeft: weeklyEntry?.leftPercent,
            sessionReset: scanReset(after: sessionEntry.index),
            weeklyReset: weeklyEntry.flatMap { scanReset(after: $0.index) }
        )
    }

    private static func extractClaudePercent(
        labelCandidates: [String],
        lines: [String]
    ) -> Int? {
        let normalizedLines = lines.map { normalizedForLabelSearch($0) }
        let normalizedLabels = labelCandidates.map { normalizedForLabelSearch($0) }

        for (index, normalizedLine) in normalizedLines.enumerated() {
            guard normalizedLabels.contains(where: {
                lineContainsClaudeLabel(normalizedLine: normalizedLine, normalizedLabel: $0)
            }) else { continue }
            let end = min(lines.count, index + 13)
            for candidate in lines[index..<end] {
                if let percentLeft = parseClaudePercentLeft(from: candidate) {
                    return percentLeft
                }
            }
        }
        return nil
    }

    private static func extractClaudeReset(
        labelCandidates: [String],
        lines: [String]
    ) -> String? {
        let normalizedLines = lines.map { normalizedForLabelSearch($0) }
        let normalizedLabels = labelCandidates.map { normalizedForLabelSearch($0) }

        for (index, normalizedLine) in normalizedLines.enumerated() {
            guard normalizedLabels.contains(where: {
                lineContainsClaudeLabel(normalizedLine: normalizedLine, normalizedLabel: $0)
            }) else { continue }
            let end = min(lines.count, index + 14)
            for candidate in lines[index..<end] {
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                let normalized = normalizedForLabelSearch(trimmed)
                if normalized.hasPrefix("current"),
                   !normalizedLabels.contains(where: {
                       lineContainsClaudeLabel(normalizedLine: normalized, normalizedLabel: $0)
                   }) {
                    break
                }
                if let reset = resetFromLine(candidate) {
                    return reset
                }
            }
        }
        return nil
    }

    private static func resetFromLine(_ line: String) -> String? {
        let trimmed = stripANSICodes(line).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let range = trimmed.range(of: #"(?i)res(?:et|es|e)?s?"#, options: .regularExpression) {
            let suffix = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let raw = suffix.isEmpty ? "Resets" : "Resets \(suffix)"
            let cleaned = cleanResetLine(raw)
            return cleaned.isEmpty ? nil : cleaned
        }

        if let shortDuration = firstRegexCapture(pattern: #"([0-9]+\s*[smhdw])"#, text: trimmed) {
            var fallback = "Resets \(shortDuration)"
            if let zoneRange = trimmed.range(of: #"\([^)]+\)"#, options: .regularExpression) {
                fallback += " \(trimmed[zoneRange])"
            }
            let cleaned = cleanResetLine(fallback)
            return cleaned.isEmpty ? nil : cleaned
        }

        return nil
    }

    private static func cleanResetLine(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " )"))
        let openCount = cleaned.filter { $0 == "(" }.count
        let closeCount = cleaned.filter { $0 == ")" }.count
        if openCount > closeCount {
            cleaned.append(")")
        }
        return cleaned
    }

    private static func parseClaudeResetInfo(_ rawReset: String?, now: Date) -> (resetsAt: Date?, resetDescription: String?) {
        guard let rawReset, !rawReset.isEmpty else { return (nil, nil) }
        let cleaned = cleanResetLine(rawReset)
        guard !cleaned.isEmpty else { return (nil, nil) }

        let normalized = cleaned
            .replacingOccurrences(of: #"(?i)^resets?:?\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return (nil, cleaned)
        }

        if let relativeMinutes = parseRelativeDurationMinutes(normalized) {
            return (now.addingTimeInterval(Double(relativeMinutes) * 60), cleaned)
        }

        if let absoluteDate = parseDateFlexible(normalized) ?? parseDateFlexible(cleaned) {
            return (absoluteDate, cleaned)
        }

        return (nil, cleaned)
    }

    private static func parseClaudeWeeklyBannerWindow(text: String, now: Date) -> ExternalUsageRateWindow? {
        let normalized = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        guard let usedPercent = parseClaudeWeeklyBannerUsedPercent(normalized) else { return nil }
        let resetRaw = parseClaudeWeeklyBannerReset(normalized)
        let resetInfo = parseClaudeResetInfo(resetRaw, now: now)

        return ExternalUsageRateWindow(
            label: "Weekly",
            usedPercent: usedPercent,
            windowMinutes: 10_080,
            resetsAt: resetInfo.resetsAt,
            resetDescription: resetInfo.resetDescription
        )
    }

    private static func parseClaudeWeeklyBannerUsedPercent(_ text: String) -> Double? {
        let compact = text.lowercased().filter { !$0.isWhitespace }

        let usedPattern = #"(?:you['’]?ve|youhave)used([0-9]{1,3}(?:\.[0-9]+)?)%ofyourweeklylimit"#
        if let usedMatch = firstRegexCapture(pattern: usedPattern, text: compact),
           let usedPercent = Double(usedMatch) {
            return max(0, min(100, usedPercent))
        }

        let remainingPattern =
            #"(?:you['’]?ve|youhave)([0-9]{1,3}(?:\.[0-9]+)?)%ofyourweeklylimit(?:left|remaining|available)"#
        if let remainingMatch = firstRegexCapture(pattern: remainingPattern, text: compact),
           let remainingPercent = Double(remainingMatch) {
            return max(0, min(100, 100 - remainingPercent))
        }
        return nil
    }

    private static func parseClaudeWeeklyBannerReset(_ text: String) -> String? {
        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let normalized = normalizedForLabelSearch(trimmed)
            let compact = normalized.replacingOccurrences(of: " ", with: "")
            guard normalized.contains("weekly limit") || compact.contains("weeklylimit") else { continue }

            if let resetRange = trimmed.range(of: "resets", options: .caseInsensitive) {
                var raw = String(trimmed[resetRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if raw.range(of: #"(?i)^resets[^\s]"#, options: .regularExpression) != nil {
                    raw = raw.replacingOccurrences(
                        of: #"(?i)^resets"#,
                        with: "Resets ",
                        options: .regularExpression
                    )
                }
                let cleaned = cleanResetLine(raw)
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }
        return nil
    }

    private static func firstRegexCapture(pattern: String, text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let value = String(text[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func parseRelativeDurationMinutes(_ text: String) -> Int? {
        let normalized = text.lowercased()
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)\s*([smhdw])"#, options: []) else {
            return nil
        }

        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let matches = regex.matches(in: normalized, range: range)
        guard !matches.isEmpty else { return nil }

        var totalMinutes = 0
        for match in matches {
            guard let amountRange = Range(match.range(at: 1), in: normalized),
                  let unitRange = Range(match.range(at: 2), in: normalized),
                  let amount = Int(normalized[amountRange]),
                  let unit = normalized[unitRange].first else {
                continue
            }

            switch unit {
            case "s":
                totalMinutes += max(1, Int((Double(amount) / 60.0).rounded(.up)))
            case "m":
                totalMinutes += amount
            case "h":
                totalMinutes += amount * 60
            case "d":
                totalMinutes += amount * 24 * 60
            case "w":
                totalMinutes += amount * 7 * 24 * 60
            default:
                continue
            }
        }

        return totalMinutes > 0 ? totalMinutes : nil
    }

    private static func parseClaudePercentLeft(from line: String) -> Int? {
        guard !isLikelyClaudeStatusContextLine(line) else { return nil }
        guard let regex = try? NSRegularExpression(pattern: #"([0-9]{1,3}(?:\.[0-9]+)?)\p{Zs}*%"#, options: []) else {
            return nil
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let valueRange = Range(match.range(at: 1), in: line),
              let raw = Double(line[valueRange]) else {
            return nil
        }

        let clamped = max(0, min(100, raw))
        let lower = line.lowercased()
        if lower.contains("used") || lower.contains("spent") || lower.contains("consumed") {
            return Int((100 - clamped).rounded())
        }
        if lower.contains("left") || lower.contains("remaining") || lower.contains("available") {
            return Int(clamped.rounded())
        }
        return Int(clamped.rounded())
    }

    private static func isLikelyClaudeStatusContextLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.contains("context") && lower.contains("%") { return true }
        if line.contains("|"),
           (lower.contains("opus") || lower.contains("sonnet") || lower.contains("haiku")) {
            return true
        }
        return false
    }

    private static func allClaudePercents(_ lines: [String]) -> [Int] {
        lines.compactMap { parseClaudePercentLeft(from: $0) }
    }

    private static func parseClaudeUsageError(_ text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("failed to load usage data") {
            return "Claude CLI가 사용량 데이터를 불러오지 못했습니다. claude를 직접 열어 /usage 동작을 확인하세요."
        }
        if lower.contains("unknown skill: usage") {
            return "Claude CLI에서 /usage 명령을 처리하지 못했습니다."
        }
        if lower.contains("token_expired") || lower.contains("token has expired") {
            return "Claude 인증이 만료되었습니다. 터미널에서 claude login 후 다시 시도하세요."
        }
        if lower.contains("authentication_error") {
            return "Claude 인증 오류로 /usage를 수집하지 못했습니다."
        }
        return nil
    }

    private static func looksClaudeNotLoggedIn(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("claude login") { return true }
        if lower.contains("not logged in") { return true }
        if lower.contains("login required") { return true }
        return false
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

    private static func preferredWindowSample(
        current: ExternalRateWindowSample?,
        candidate: ExternalRateWindowSample
    ) -> ExternalRateWindowSample {
        guard let current else { return candidate }
        let timestampDelta = abs(candidate.observedAtUnixMs - current.observedAtUnixMs)
        if timestampDelta <= 5_000, candidate.sourcePriority != current.sourcePriority {
            return candidate.sourcePriority > current.sourcePriority ? candidate : current
        }
        if candidate.observedAtUnixMs != current.observedAtUnixMs {
            return candidate.observedAtUnixMs > current.observedAtUnixMs ? candidate : current
        }
        if candidate.sourcePriority != current.sourcePriority {
            return candidate.sourcePriority > current.sourcePriority ? candidate : current
        }

        let currentScore = (current.primaryWindow != nil ? 1 : 0) + (current.secondaryWindow != nil ? 1 : 0)
        let candidateScore = (candidate.primaryWindow != nil ? 1 : 0) + (candidate.secondaryWindow != nil ? 1 : 0)
        return candidateScore >= currentScore ? candidate : current
    }

    private static func parseCodexRateWindowSample(
        rateLimits: [String: Any],
        timestampText: String?
    ) -> ExternalRateWindowSample? {
        let limitID = (rateLimits["limit_id"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        let sourcePriority: Int
        if limitID == "codex" {
            sourcePriority = 3
        } else if limitID.hasPrefix("codex_") {
            sourcePriority = 2
        } else if limitID.contains("codex") {
            sourcePriority = 1
        } else {
            sourcePriority = 0
        }

        let observedAtUnixMs: Int64
        if let timestampText, let observedDate = parseDateFlexible(timestampText) {
            observedAtUnixMs = Int64(observedDate.timeIntervalSince1970 * 1000)
        } else {
            observedAtUnixMs = 0
        }

        let primaryObject = rateLimits["primary"] as? [String: Any]
        let secondaryObject = rateLimits["secondary"] as? [String: Any]

        let primaryWindow = parseCodexRateWindow(
            from: primaryObject,
            fallbackLabel: "Primary",
            fallbackReset: nil
        )
        let secondaryWindow = parseCodexRateWindow(
            from: secondaryObject,
            fallbackLabel: "Secondary",
            fallbackReset: nil
        )

        guard primaryWindow != nil || secondaryWindow != nil else { return nil }
        return ExternalRateWindowSample(
            sourcePriority: sourcePriority,
            observedAtUnixMs: observedAtUnixMs,
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow
        )
    }

    private static func parseCodexRateWindow(
        from object: [String: Any]?,
        fallbackLabel: String,
        fallbackReset: String?
    ) -> ExternalUsageRateWindow? {
        guard let object else { return nil }
        guard let usedPercent = parseDouble(object["used_percent"] ?? object["usedPercent"]) else { return nil }

        let windowMinutes = parseInteger(object["window_minutes"] ?? object["windowMinutes"])
        let resetValue = object["resets_at"] ?? object["resetsAt"] ?? object["reset_time"] ?? object["resetTime"]
        let resetsAt = parseDateFlexible(resetValue)
        let label = codexWindowLabel(windowMinutes: windowMinutes, fallback: fallbackLabel)

        return ExternalUsageRateWindow(
            label: label,
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: resetsAt,
            resetDescription: fallbackReset
        )
    }

    private static func codexWindowLabel(windowMinutes: Int?, fallback: String) -> String {
        guard let windowMinutes, windowMinutes > 0 else { return fallback }
        if windowMinutes == 10_080 { return "Weekly" }
        if windowMinutes == 1_440 { return "Daily" }
        if windowMinutes == 300 { return "5h" }
        if windowMinutes % 1_440 == 0 {
            return "\(windowMinutes / 1_440)d"
        }
        if windowMinutes % 60 == 0 {
            return "\(windowMinutes / 60)h"
        }
        return "\(windowMinutes)m"
    }

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

    private static func shellSingleQuoted(_ value: String) -> String {
        if value.isEmpty { return "''" }
        return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func parseGeminiStats(_ rawText: String, now: Date) -> GeminiStatsParseResult? {
        let stripped = Self.stripANSICodes(rawText)
        let pattern = #"(gemini[-\w.]+)\s+[\d-]+\s+([0-9]+(?:\.[0-9]+)?)\s*%\s*\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        var bestUsedFraction: Double?
        var bestResetDescription: String?
        var bestWindowMinutes: Int?
        var bestResetAt: Date?

        for line in stripped.split(whereSeparator: \.isNewline) {
            let cleanLine = String(line).replacingOccurrences(of: "│", with: " ")
            let range = NSRange(cleanLine.startIndex..<cleanLine.endIndex, in: cleanLine)
            guard let match = regex.firstMatch(in: cleanLine, range: range),
                  let percentRange = Range(match.range(at: 2), in: cleanLine),
                  let percentLeft = Double(cleanLine[percentRange])
            else {
                continue
            }

            let resetDescription: String? = {
                guard let resetRange = Range(match.range(at: 3), in: cleanLine) else { return nil }
                let text = String(cleanLine[resetRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }()

            let remaining = min(100, max(0, percentLeft))
            let usedFraction = min(1, max(0, 1 - (remaining / 100)))

            if let currentBest = bestUsedFraction, usedFraction <= currentBest {
                continue
            }

            bestUsedFraction = usedFraction
            bestResetDescription = resetDescription
            if let resetDescription {
                bestWindowMinutes = parseGeminiResetDurationMinutes(resetDescription)
                if let minutes = bestWindowMinutes {
                    bestResetAt = now.addingTimeInterval(Double(minutes) * 60)
                } else {
                    bestResetAt = parseDateFlexible(resetDescription)
                }
            } else {
                bestWindowMinutes = nil
                bestResetAt = nil
            }
        }

        guard let bestUsedFraction else { return nil }
        let primaryWindow = ExternalUsageRateWindow(
            label: "Gemini quota",
            usedPercent: bestUsedFraction * 100,
            windowMinutes: bestWindowMinutes,
            resetsAt: bestResetAt,
            resetDescription: bestResetDescription
        )

        return GeminiStatsParseResult(
            usedFraction: bestUsedFraction,
            primaryWindow: primaryWindow,
            secondaryWindow: nil
        )
    }

    private static func parseGeminiResetDurationMinutes(_ text: String) -> Int? {
        let normalized = text.lowercased()
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)\s*([smhdw])"#, options: []) else {
            return nil
        }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        guard let match = regex.firstMatch(in: normalized, range: range),
              let amountRange = Range(match.range(at: 1), in: normalized),
              let unitRange = Range(match.range(at: 2), in: normalized),
              let amount = Int(normalized[amountRange]),
              let unit = normalized[unitRange].first
        else {
            return nil
        }

        switch unit {
        case "s":
            return max(1, Int((Double(amount) / 60.0).rounded(.up)))
        case "m":
            return amount
        case "h":
            return amount * 60
        case "d":
            return amount * 60 * 24
        case "w":
            return amount * 60 * 24 * 7
        default:
            return nil
        }
    }

    private static func looksGeminiNotLoggedIn(_ text: String) -> Bool {
        let lower = stripANSICodes(text).lowercased()
        if lower.contains("login with google") { return true }
        if lower.contains("waiting for auth") { return true }
        if lower.contains("run 'gemini' in terminal to authenticate") { return true }
        return false
    }

    private static func stripANSICodes(_ text: String) -> String {
        let withoutCSI = text.replacingOccurrences(
            of: #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
        let withoutOSC = withoutCSI.replacingOccurrences(
            of: #"\u{001B}\][^\u{0007}]*\u{0007}"#,
            with: "",
            options: .regularExpression
        )
        let withoutEscape = withoutOSC.replacingOccurrences(of: "\u{001B}", with: "")
        let withoutBareCSI = withoutEscape.replacingOccurrences(
            of: #"\[[0-9;?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
        return withoutBareCSI.replacingOccurrences(
            of: #"[\u{0000}-\u{0008}\u{000B}\u{000C}\u{000E}-\u{001F}\u{007F}]"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func runProcess(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        captureOutputOnTimeout: Bool = false
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
            if !captureOutputOnTimeout {
                return nil
            }
        }

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let outputText = String(data: outputData + errorData, encoding: .utf8) ?? ""
        let status: Int32
        if process.isRunning {
            status = -1
        } else {
            status = process.terminationStatus
        }
        return (outputText, status)
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
        if let parsed = parseDateFlexible(text) {
            return DayRange.dayKey(from: parsed)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 10 {
            let prefix = String(trimmed.prefix(10))
            if prefix.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil {
                return prefix
            }
        }
        return nil
    }

    private static func parseDateFlexible(_ value: Any?) -> Date? {
        if let date = value as? Date {
            return date
        }
        if let number = parseDouble(value), let date = parseUnixTimestamp(number) {
            return date
        }
        if let text = value as? String {
            return parseDateFlexible(text)
        }
        return nil
    }

    private static func parseDateFlexible(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let unix = Double(trimmed), let date = parseUnixTimestamp(unix) {
            return date
        }

        let fractionalISO = ISO8601DateFormatter()
        fractionalISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let basicISO = ISO8601DateFormatter()
        basicISO.formatOptions = [.withInternetDateTime]
        if let parsed = fractionalISO.date(from: trimmed)
            ?? basicISO.date(from: trimmed) {
            return parsed
        }

        for format in fallbackDateFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let parsed = formatter.date(from: trimmed) {
                return parsed
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
