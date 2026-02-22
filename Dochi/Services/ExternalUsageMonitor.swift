import Foundation
import os

enum ExternalUsageProvider: String, Sendable {
    case codex
    case claude
    case gemini
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

    private let codexSessionsRoots: [URL]
    private let claudeProjectsRoots: [URL]
    private let cacheURL: URL
    private let refreshMinIntervalSeconds: TimeInterval

    private var cache: MonitorCache

    init(
        codexSessionsRoots: [URL],
        claudeProjectsRoots: [URL],
        cacheURL: URL,
        refreshMinIntervalSeconds: TimeInterval = 60
    ) {
        self.codexSessionsRoots = Self.uniqueStandardizedPaths(codexSessionsRoots)
        self.claudeProjectsRoots = Self.uniqueStandardizedPaths(claudeProjectsRoots)
        self.cacheURL = cacheURL
        self.refreshMinIntervalSeconds = max(0, refreshMinIntervalSeconds)
        self.cache = Self.loadCache(at: cacheURL) ?? MonitorCache()
    }

    func tokensUsed(provider: ExternalUsageProvider, since startDate: Date, now: Date = Date()) -> Int {
        switch provider {
        case .codex:
            refreshCodex(since: startDate, now: now)
        case .claude:
            refreshClaude(since: startDate, now: now)
        case .gemini:
            return 0
        }

        let key = provider.rawValue
        guard let providerCache = cache.providers[key] else { return 0 }
        let range = DayRange(since: startDate, until: now)
        let sum = providerCache.days.reduce(0) { partial, entry in
            guard DayRange.isInRange(dayKey: entry.key, since: range.sinceKey, until: range.untilKey) else {
                return partial
            }
            return partial + max(0, entry.value)
        }
        return max(0, sum)
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
