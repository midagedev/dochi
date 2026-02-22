import CryptoKit
import Foundation
import os

/// 구독형 AI 서비스의 유휴 토큰을 감지하고 자동 작업에 배분하는 서비스.
@MainActor
@Observable
final class ResourceOptimizerService: ResourceOptimizerProtocol {
    // MARK: - State

    private(set) var subscriptions: [SubscriptionPlan] = []
    private(set) var autoTaskRecords: [AutoTaskRecord] = []

    private struct UsageCacheKey: Hashable {
        let source: SubscriptionUsageSource
        let provider: String
        let startDay: String
    }

    private struct UsageCacheEntry {
        let tokens: Int
        let updatedAt: Date
    }

    private var usageCache: [UsageCacheKey: UsageCacheEntry] = [:]

    // MARK: - Dependencies

    private let baseURL: URL
    private let usageStore: UsageStoreProtocol?
    private let claudeProjectsRoots: [URL]
    private let codexSessionsRoots: [URL]

    private let reserveBufferRatio = 0.08
    private let externalUsageCacheTTL: TimeInterval = 45

    // MARK: - Init

    init(
        baseURL: URL? = nil,
        usageStore: UsageStoreProtocol? = nil,
        claudeProjectsRoots: [URL]? = nil,
        codexSessionsRoots: [URL]? = nil
    ) {
        let appSupport = baseURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dochi")
        self.baseURL = appSupport
        self.usageStore = usageStore
        self.claudeProjectsRoots = claudeProjectsRoots ?? Self.defaultClaudeProjectsRoots()
        self.codexSessionsRoots = codexSessionsRoots ?? Self.defaultCodexSessionsRoots()
        loadFromDisk()
    }

    // MARK: - File Path

    private var filePath: URL {
        baseURL.appendingPathComponent("subscriptions.json")
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        do {
            let data = try Data(contentsOf: filePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let file = try decoder.decode(SubscriptionsFile.self, from: data)
            subscriptions = file.subscriptions
            autoTaskRecords = file.autoTaskRecords
            Log.storage.debug("Loaded \(self.subscriptions.count) subscriptions")
        } catch {
            if (error as NSError).domain == NSCocoaErrorDomain,
               (error as NSError).code == NSFileReadNoSuchFileError {
                Log.storage.debug("No subscriptions file found, starting fresh")
            } else {
                Log.storage.warning("Failed to load subscriptions: \(error.localizedDescription)")
            }
        }
    }

    private func saveToDisk() {
        do {
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
            let file = SubscriptionsFile(subscriptions: subscriptions, autoTaskRecords: autoTaskRecords)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(file)
            try data.write(to: filePath, options: .atomic)
            Log.storage.debug("Saved \(self.subscriptions.count) subscriptions")
        } catch {
            Log.storage.error("Failed to save subscriptions: \(error.localizedDescription)")
        }
    }

    // MARK: - Subscription CRUD

    func addSubscription(_ plan: SubscriptionPlan) async {
        subscriptions.append(plan)
        saveToDisk()
    }

    func updateSubscription(_ plan: SubscriptionPlan) async {
        if let index = subscriptions.firstIndex(where: { $0.id == plan.id }) {
            subscriptions[index] = plan
            saveToDisk()
        }
    }

    func deleteSubscription(id: UUID) async {
        subscriptions.removeAll { $0.id == id }
        autoTaskRecords.removeAll { $0.subscriptionId == id }
        saveToDisk()
    }

    // MARK: - Utilization

    func utilization(for subscription: SubscriptionPlan) async -> ResourceUtilization {
        let calendar = Calendar.current
        let now = Date()

        // 리셋일 기준 현재 기간 계산
        let resetDay = min(subscription.resetDayOfMonth, 28)
        var periodStart = calendar.date(bySetting: .day, value: resetDay, of: now) ?? now
        if periodStart > now {
            periodStart = calendar.date(byAdding: .month, value: -1, to: periodStart) ?? periodStart
        }
        let periodEnd = calendar.date(byAdding: .month, value: 1, to: periodStart) ?? now

        let daysInPeriod = max(1, calendar.dateComponents([.day], from: periodStart, to: periodEnd).day ?? 30)
        let daysRemaining = max(0, calendar.dateComponents([.day], from: now, to: periodEnd).day ?? 0)
        let elapsedDays = max(1, daysInPeriod - daysRemaining)

        // 현재 기간 사용 토큰 조회
        let usedTokens = await tokensUsed(for: subscription, since: periodStart)

        let usageRatio = subscription.monthlyTokenLimit.map { limit -> Double in
            guard limit > 0 else { return 0 }
            return Double(usedTokens) / Double(limit)
        } ?? 0

        let remainingRatio = Double(daysRemaining) / Double(daysInPeriod)
        let velocityTokensPerDay = Double(usedTokens) / Double(elapsedDays)
        let projectedUsageRatio = subscription.monthlyTokenLimit.map { limit -> Double in
            guard limit > 0 else { return 0 }
            let projectedUsed = Double(usedTokens) + (velocityTokensPerDay * Double(daysRemaining))
            return max(0, min(1.5, projectedUsed / Double(limit)))
        } ?? 0

        let riskLevel = calculateRiskLevel(
            usageRatio: usageRatio,
            remainingRatio: remainingRatio,
            projectedUsageRatio: projectedUsageRatio,
            reserveBufferRatio: reserveBufferRatio
        )

        return ResourceUtilization(
            subscription: subscription,
            usedTokens: usedTokens,
            daysInPeriod: daysInPeriod,
            daysRemaining: daysRemaining,
            velocityTokensPerDay: velocityTokensPerDay,
            projectedUsageRatio: projectedUsageRatio,
            reserveBufferRatio: reserveBufferRatio,
            riskLevel: riskLevel
        )
    }

    func allUtilizations() async -> [ResourceUtilization] {
        var results: [ResourceUtilization] = []
        for sub in subscriptions {
            let util = await utilization(for: sub)
            results.append(util)
        }
        return results
    }

    // MARK: - Risk Assessment

    func calculateRiskLevel(
        usageRatio: Double,
        remainingRatio: Double,
        projectedUsageRatio: Double?,
        reserveBufferRatio: Double
    ) -> WasteRiskLevel {
        let projected = max(0, min(1.5, projectedUsageRatio ?? usageRatio))
        let projectedRemaining = max(0, 1.0 - projected)
        let preservesBuffer = projectedRemaining <= reserveBufferRatio

        // 낭비 위험: 사용률 < 50% && 잔여 기간 < 15%
        if usageRatio < 0.5 && remainingRatio < 0.15 {
            return .wasteRisk
        }
        // 주의: 사용률 < 30% && 잔여 기간 < 30%
        if usageRatio < 0.3 && remainingRatio < 0.3 {
            return .caution
        }
        // 예측 기반 리스크: 현재 속도로 기간 종료 시 토큰이 과도하게 남는 경우.
        if !preservesBuffer && projected < 0.45 && remainingRatio < 0.25 {
            return .wasteRisk
        }
        if !preservesBuffer && projected < 0.6 && remainingRatio < 0.35 {
            return .caution
        }
        // 여유: 사용률 < 50% && 잔여 기간 > 50%
        if usageRatio < 0.5 && remainingRatio > 0.5 {
            return .comfortable
        }
        return .normal
    }

    // MARK: - Auto Tasks

    func queueAutoTask(
        type: AutoTaskType,
        subscriptionId: UUID,
        dedupeKey: String?,
        summary: String
    ) async {
        let record = AutoTaskRecord(
            taskType: type,
            subscriptionId: subscriptionId,
            dedupeKey: dedupeKey,
            summary: summary
        )
        autoTaskRecords.append(record)
        // FIFO: 최대 100건
        if autoTaskRecords.count > 100 {
            autoTaskRecords = Array(autoTaskRecords.suffix(100))
        }
        saveToDisk()
        Log.app.info("Queued auto task: \(type.displayName) for subscription \(subscriptionId)")
    }

    func evaluateAndQueueAutoTasks(
        enabledTypes: [AutoTaskType],
        onlyWasteRisk: Bool,
        gitInsights: [GitRepositoryInsight]?
    ) async -> Int {
        var taskTypes: [AutoTaskType] = []
        for type in enabledTypes where !taskTypes.contains(type) {
            taskTypes.append(type)
        }
        guard !taskTypes.isEmpty else { return 0 }

        let includesGitScan = taskTypes.contains(.gitScanReview)
        let gitCandidates: [GitScanCandidate]
        if includesGitScan {
            let paths = (gitInsights ?? []).map(\.path)
            gitCandidates = await Task.detached(priority: .utility) {
                Self.collectGitScanCandidates(from: paths)
            }.value
            if gitCandidates.isEmpty {
                Log.app.debug("Git scan auto task: no eligible repository candidates")
            }
        } else {
            gitCandidates = []
        }

        let utilizations = await allUtilizations()
        let now = Date()
        var queuedCount = 0

        for util in utilizations {
            guard shouldQueueTasks(for: util, onlyWasteRisk: onlyWasteRisk) else { continue }
            for taskType in taskTypes {
                if taskType == .gitScanReview {
                    guard let candidate = gitCandidates.first else { continue }
                    guard shouldQueueAutoTask(
                        type: taskType,
                        subscriptionId: util.subscription.id,
                        now: now,
                        dedupeKey: candidate.dedupeKey
                    ) else { continue }
                    await queueAutoTask(
                        type: taskType,
                        subscriptionId: util.subscription.id,
                        dedupeKey: candidate.dedupeKey,
                        summary: candidate.summary
                    )
                    queuedCount += 1
                    continue
                }

                guard shouldQueueAutoTask(
                    type: taskType,
                    subscriptionId: util.subscription.id,
                    now: now,
                    dedupeKey: nil
                ) else { continue }
                await queueAutoTask(
                    type: taskType,
                    subscriptionId: util.subscription.id,
                    dedupeKey: nil,
                    summary: ""
                )
                queuedCount += 1
            }
        }

        if queuedCount > 0 {
            Log.app.info("Resource auto-task pipeline queued \(queuedCount) task(s)")
        }
        return queuedCount
    }

    private func shouldQueueTasks(for util: ResourceUtilization, onlyWasteRisk: Bool) -> Bool {
        guard let limit = util.subscription.monthlyTokenLimit, limit > 0 else { return false }
        guard util.usedTokens < limit else { return false }
        if onlyWasteRisk && util.riskLevel != .wasteRisk {
            return false
        }
        return true
    }

    private func shouldQueueAutoTask(
        type: AutoTaskType,
        subscriptionId: UUID,
        now: Date,
        dedupeKey: String?
    ) -> Bool {
        if let dedupeKey, !dedupeKey.isEmpty {
            return !autoTaskRecords.contains {
                $0.subscriptionId == subscriptionId
                    && $0.taskType == type
                    && $0.dedupeKey == dedupeKey
            }
        }

        guard let lastRecord = autoTaskRecords.last(where: {
            $0.subscriptionId == subscriptionId && $0.taskType == type
        }) else {
            return true
        }
        return !Calendar.current.isDate(lastRecord.executedAt, inSameDayAs: now)
    }

    private struct GitScanCandidate: Sendable {
        let dedupeKey: String
        let summary: String
        let changedFiles: Int
        let changedLines: Int
    }

    private struct UntrackedFileCandidate: Sendable {
        let path: String
        let addedLines: Int
        let isBinary: Bool
    }

    nonisolated private static func collectGitScanCandidates(from rawPaths: [String]) -> [GitScanCandidate] {
        let inputPaths: [String]
        if rawPaths.isEmpty {
            inputPaths = GitRepositoryInsightScanner
                .discover(searchPaths: nil, limit: 5)
                .map(\.path)
        } else {
            inputPaths = rawPaths
        }

        var uniquePaths: [String] = []
        var seen = Set<String>()
        for rawPath in inputPaths {
            let normalized = URL(fileURLWithPath: NSString(string: rawPath).expandingTildeInPath)
                .standardizedFileURL.path
            if seen.insert(normalized).inserted {
                uniquePaths.append(normalized)
            }
        }

        var candidates: [GitScanCandidate] = []
        for path in uniquePaths {
            guard let candidate = buildGitScanCandidate(repoPath: path) else { continue }
            candidates.append(candidate)
        }

        return candidates.sorted { lhs, rhs in
            if lhs.changedFiles != rhs.changedFiles {
                return lhs.changedFiles > rhs.changedFiles
            }
            return lhs.changedLines > rhs.changedLines
        }
    }

    nonisolated private static func buildGitScanCandidate(repoPath: String) -> GitScanCandidate? {
        let maxGitScanChangedFiles = 150
        let maxGitScanChangedLines = 4000

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: repoPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        guard let trackedNumStatOutput = runGitSync(repoPath: repoPath, args: ["diff", "--numstat", "HEAD"]) else {
            return nil
        }

        guard let untrackedFiles = collectUntrackedFileCandidates(repoPath: repoPath) else {
            return nil
        }

        let trackedRows = trackedNumStatOutput
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !trackedRows.isEmpty || !untrackedFiles.isEmpty else { return nil }

        var changedFiles = 0
        var changedLines = 0
        var addedTotal = 0
        var deletedTotal = 0
        var hasBinary = false
        var fingerprintParts: [String] = []

        for row in trackedRows {
            let columns = row.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard columns.count >= 3 else { continue }

            let addedRaw = columns[0]
            let deletedRaw = columns[1]
            let path = columns[2]

            if addedRaw == "-" || deletedRaw == "-" {
                hasBinary = true
                break
            }

            let added = Int(addedRaw) ?? 0
            let deleted = Int(deletedRaw) ?? 0
            changedFiles += 1
            changedLines += added + deleted
            addedTotal += added
            deletedTotal += deleted
            fingerprintParts.append("\(path):\(added):\(deleted)")

            if changedFiles > maxGitScanChangedFiles || changedLines > maxGitScanChangedLines {
                return nil
            }
        }

        for untracked in untrackedFiles {
            if untracked.isBinary {
                hasBinary = true
                break
            }

            changedFiles += 1
            changedLines += untracked.addedLines
            addedTotal += untracked.addedLines
            fingerprintParts.append("untracked:\(untracked.path):\(untracked.addedLines)")

            if changedFiles > maxGitScanChangedFiles || changedLines > maxGitScanChangedLines {
                return nil
            }
        }

        guard !hasBinary else { return nil }
        guard changedFiles > 0, changedLines > 0 else { return nil }

        let head = runGitSync(repoPath: repoPath, args: ["rev-parse", "--verify", "HEAD"]) ?? "unknown"
        let fingerprint = ([head] + fingerprintParts.sorted()).joined(separator: "|")
        let fingerprintHash = shortSHA256(fingerprint)
        let dayKey = dayString(Date())
        let dedupeKey = "\(dayKey)|\(String(head.prefix(12)))|\(fingerprintHash)"

        let repoName = URL(fileURLWithPath: repoPath).lastPathComponent
        let summary = "Git 스캔 후보 \(repoName): \(changedFiles) files, +\(addedTotal)/-\(deletedTotal)"

        return GitScanCandidate(
            dedupeKey: dedupeKey,
            summary: summary,
            changedFiles: changedFiles,
            changedLines: changedLines
        )
    }

    nonisolated private static func collectUntrackedFileCandidates(repoPath: String) -> [UntrackedFileCandidate]? {
        guard let output = runGitSync(
            repoPath: repoPath,
            args: ["ls-files", "--others", "--exclude-standard"]
        ) else {
            return nil
        }

        let paths = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !paths.isEmpty else { return [] }

        var files: [UntrackedFileCandidate] = []
        let repoURL = URL(fileURLWithPath: repoPath)
        for relativePath in paths {
            let fileURL = repoURL.appendingPathComponent(relativePath)

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }

            guard let data = try? Data(contentsOf: fileURL) else {
                continue
            }

            if data.contains(0) {
                files.append(
                    UntrackedFileCandidate(path: relativePath, addedLines: 0, isBinary: true)
                )
                continue
            }

            guard let content = String(data: data, encoding: .utf8) else {
                files.append(
                    UntrackedFileCandidate(path: relativePath, addedLines: 0, isBinary: true)
                )
                continue
            }

            let lineCount = max(1, lineCountForText(content))
            files.append(
                UntrackedFileCandidate(path: relativePath, addedLines: lineCount, isBinary: false)
            )
        }

        return files
    }

    nonisolated private static func runGitSync(repoPath: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    nonisolated private static func shortSHA256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(12))
    }

    nonisolated private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    nonisolated private static func lineCountForText(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var count = 0
        for char in text where char == "\n" {
            count += 1
        }
        return text.hasSuffix("\n") ? count : count + 1
    }

    // MARK: - Token Usage Query

    private func tokensUsed(for subscription: SubscriptionPlan, since startDate: Date) async -> Int {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        let key = UsageCacheKey(
            source: subscription.usageSource,
            provider: normalizedProviderKey(subscription.providerName),
            startDay: dayFormatter.string(from: startDate)
        )
        if let cached = usageCache[key],
           Date().timeIntervalSince(cached.updatedAt) < externalUsageCacheTTL {
            return cached.tokens
        }

        let tokens: Int
        switch subscription.usageSource {
        case .dochiUsageStore:
            tokens = await tokensUsedByUsageStore(subscription.providerName, since: startDate)
        case .externalToolLogs:
            tokens = await tokensUsedByExternalToolLogs(subscription.providerName, since: startDate)
        }
        usageCache[key] = UsageCacheEntry(tokens: tokens, updatedAt: Date())
        return tokens
    }

    private func tokensUsedByUsageStore(_ providerName: String, since startDate: Date) async -> Int {
        guard let store = usageStore else { return 0 }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")

        let startStr = dayFormatter.string(from: startDate)
        let providerLower = providerName.lowercased()

        // 현재 월과 이전 월 (리셋일에 따라 월 경계를 넘을 수 있음)
        let months = await store.allMonths()
        var totalTokens = 0

        for month in months {
            let records = await store.dailyRecords(for: month)
            for day in records {
                guard day.date >= startStr else { continue }
                for entry in day.entries {
                    if entry.provider.lowercased() == providerLower {
                        totalTokens += entry.inputTokens + entry.outputTokens
                    }
                }
            }
        }

        return totalTokens
    }

    private func tokensUsedByExternalToolLogs(_ providerName: String, since startDate: Date) async -> Int {
        let provider = Self.externalProviderKind(from: providerName)
        switch provider {
        case .claude:
            let roots = claudeProjectsRoots
            return await Task.detached(priority: .utility) {
                Self.scanJSONLTokenUsage(roots: roots, since: startDate)
            }.value
        case .codex:
            let roots = codexSessionsRoots
            return await Task.detached(priority: .utility) {
                Self.scanJSONLTokenUsage(roots: roots, since: startDate)
            }.value
        case .unknown:
            return 0
        }
    }

    private func normalizedProviderKey(_ providerName: String) -> String {
        providerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private enum ExternalProviderKind {
        case claude
        case codex
        case unknown
    }

    private struct ParsedTokenUsage: Hashable {
        let input: Int
        let output: Int
        let total: Int
    }

    nonisolated private static func defaultClaudeProjectsRoots() -> [URL] {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser

        var rawRoots: [URL] = []
        if let custom = env["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            let expanded = NSString(string: custom).expandingTildeInPath
            rawRoots.append(URL(fileURLWithPath: expanded).appendingPathComponent("projects", isDirectory: true))
        }
        rawRoots.append(home.appendingPathComponent(".claude/projects", isDirectory: true))
        rawRoots.append(home.appendingPathComponent(".config/claude/projects", isDirectory: true))
        return uniqueStandardizedPaths(rawRoots)
    }

    nonisolated private static func defaultCodexSessionsRoots() -> [URL] {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser

        var rawRoots: [URL] = []
        if let custom = env["CODEX_HOME"], !custom.isEmpty {
            let expanded = NSString(string: custom).expandingTildeInPath
            rawRoots.append(URL(fileURLWithPath: expanded).appendingPathComponent("sessions", isDirectory: true))
        }
        rawRoots.append(home.appendingPathComponent(".codex/sessions", isDirectory: true))
        return uniqueStandardizedPaths(rawRoots)
    }

    nonisolated private static func uniqueStandardizedPaths(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var unique: [URL] = []
        for url in urls {
            let normalized = url.standardizedFileURL
            let key = normalized.path
            if seen.insert(key).inserted {
                unique.append(normalized)
            }
        }
        return unique
    }

    nonisolated private static func externalProviderKind(from providerName: String) -> ExternalProviderKind {
        let normalized = providerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("claude") || normalized.contains("anthropic") {
            return .claude
        }
        if normalized.contains("codex")
            || normalized.contains("chatgpt")
            || normalized.contains("openai") {
            return .codex
        }
        return .unknown
    }

    nonisolated private static func scanJSONLTokenUsage(roots: [URL], since startDate: Date) -> Int {
        guard !roots.isEmpty else { return 0 }

        let candidateFiles = collectJSONLFiles(roots: roots, modifiedAfter: startDate.addingTimeInterval(-2 * 24 * 60 * 60))
        guard !candidateFiles.isEmpty else { return 0 }

        var total = 0
        for file in candidateFiles {
            total += parseJSONLFile(
                at: file.url,
                fileModifiedAt: file.modifiedAt,
                since: startDate
            )
        }
        return max(0, total)
    }

    nonisolated private static func collectJSONLFiles(
        roots: [URL],
        modifiedAfter: Date
    ) -> [(url: URL, modifiedAt: Date)] {
        let fm = FileManager.default
        var files: [(url: URL, modifiedAt: Date)] = []

        for root in roots {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl" else { continue }
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                      values.isRegularFile == true else { continue }
                let modifiedAt = values.contentModificationDate ?? .distantPast
                guard modifiedAt >= modifiedAfter else { continue }
                files.append((url: url, modifiedAt: modifiedAt))
            }
        }

        return files
            .sorted(by: { $0.modifiedAt > $1.modifiedAt })
            .prefix(180)
            .map { $0 }
    }

    nonisolated private static func parseJSONLFile(
        at fileURL: URL,
        fileModifiedAt: Date,
        since startDate: Date
    ) -> Int {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return 0
        }
        defer { try? handle.close() }

        var buffer = Data()
        var total = 0

        while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            buffer.append(chunk)

            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                total += parseJSONLLine(
                    lineData,
                    fileModifiedAt: fileModifiedAt,
                    since: startDate
                )
            }
        }

        if !buffer.isEmpty {
            total += parseJSONLLine(
                buffer,
                fileModifiedAt: fileModifiedAt,
                since: startDate
            )
        }

        return total
    }

    nonisolated private static func parseJSONLLine(
        _ lineData: Data,
        fileModifiedAt: Date,
        since startDate: Date
    ) -> Int {
        guard !lineData.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: lineData) else {
            return 0
        }

        let eventDate = extractEventDate(from: json) ?? fileModifiedAt
        guard eventDate >= startDate else { return 0 }

        var usages = Set<ParsedTokenUsage>()
        collectParsedTokenUsages(from: json, into: &usages, depth: 0)
        guard !usages.isEmpty else { return 0 }

        return usages.reduce(0) { partial, usage in
            let candidate = usage.total > 0 ? usage.total : (usage.input + usage.output)
            return partial + max(0, candidate)
        }
    }

    nonisolated private static func collectParsedTokenUsages(
        from value: Any,
        into results: inout Set<ParsedTokenUsage>,
        depth: Int
    ) {
        guard depth <= 12 else { return }

        if let dictionary = value as? [String: Any] {
            if let parsed = parseTokenUsage(from: dictionary) {
                results.insert(parsed)
            }
            for child in dictionary.values {
                collectParsedTokenUsages(from: child, into: &results, depth: depth + 1)
            }
            return
        }

        if let array = value as? [Any] {
            for child in array {
                collectParsedTokenUsages(from: child, into: &results, depth: depth + 1)
            }
        }
    }

    nonisolated private static func parseTokenUsage(from dictionary: [String: Any]) -> ParsedTokenUsage? {
        var input = 0
        var output = 0
        var total = 0
        var found = false

        for (key, value) in dictionary {
            let normalized = normalizeUsageKey(key)
            if inputTokenKeys.contains(normalized) {
                input += parseInteger(value) ?? 0
                found = true
                continue
            }
            if outputTokenKeys.contains(normalized) {
                output += parseInteger(value) ?? 0
                found = true
                continue
            }
            if totalTokenKeys.contains(normalized) {
                total += parseInteger(value) ?? 0
                found = true
            }
        }

        guard found else { return nil }
        return ParsedTokenUsage(
            input: max(0, input),
            output: max(0, output),
            total: max(0, total)
        )
    }

    nonisolated private static func extractEventDate(from value: Any) -> Date? {
        extractEventDate(from: value, depth: 0)
    }

    nonisolated private static func extractEventDate(from value: Any, depth: Int) -> Date? {
        guard depth <= 8 else { return nil }

        if let dictionary = value as? [String: Any] {
            for (key, rawValue) in dictionary {
                let normalized = normalizeUsageKey(key)
                if timestampKeys.contains(normalized),
                   let parsed = parseDate(rawValue) {
                    return parsed
                }
            }
            for child in dictionary.values {
                if let parsed = extractEventDate(from: child, depth: depth + 1) {
                    return parsed
                }
            }
            return nil
        }

        if let array = value as? [Any] {
            for child in array {
                if let parsed = extractEventDate(from: child, depth: depth + 1) {
                    return parsed
                }
            }
        }

        return nil
    }

    nonisolated private static func parseInteger(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let intValue = Int(trimmed) {
                return intValue
            }
            if let doubleValue = Double(trimmed) {
                return Int(doubleValue.rounded())
            }
            return nil
        }
        if let dictionary = value as? [String: Any] {
            for key in ["total", "count", "value"] {
                if let parsed = parseInteger(dictionary[key]) {
                    return parsed
                }
            }
            return nil
        }
        return nil
    }

    nonisolated private static func parseDate(_ value: Any?) -> Date? {
        guard let value else { return nil }
        if let number = value as? NSNumber {
            return parseUnixTimestamp(number.doubleValue)
        }
        if let intValue = value as? Int {
            return parseUnixTimestamp(Double(intValue))
        }
        if let doubleValue = value as? Double {
            return parseUnixTimestamp(doubleValue)
        }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let unix = Double(trimmed) {
                return parseUnixTimestamp(unix)
            }
            if let parsed = parseISO8601Date(trimmed) {
                return parsed
            }
            if let parsed = parseFallbackDate(trimmed) {
                return parsed
            }
        }
        return nil
    }

    nonisolated private static func parseUnixTimestamp(_ raw: Double) -> Date? {
        guard raw > 0 else { return nil }
        if raw > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: raw / 1000.0)
        }
        if raw > 1_000_000_000 {
            return Date(timeIntervalSince1970: raw)
        }
        return nil
    }

    nonisolated private static func normalizeUsageKey(_ key: String) -> String {
        let lower = key.lowercased()
        let scalars = lower.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    nonisolated private static let inputTokenKeys: Set<String> = [
        "inputtokens",
        "inputtokencount",
        "prompttokens",
        "prompttokencount",
        "cachecreationinputtokens",
        "cachereadinputtokens",
    ]

    nonisolated private static let outputTokenKeys: Set<String> = [
        "outputtokens",
        "outputtokencount",
        "completiontokens",
        "completiontokencount",
    ]

    nonisolated private static let totalTokenKeys: Set<String> = [
        "totaltokens",
        "totaltokencount",
        "tokencount",
    ]

    nonisolated private static let timestampKeys: Set<String> = [
        "timestamp",
        "createdat",
        "createdtime",
        "eventtime",
        "time",
        "datetime",
        "updatedat",
        "modified",
    ]

    nonisolated private static let fallbackDateFormats: [String] = {
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
        ]
        return formats
    }()

    nonisolated private static func parseISO8601Date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractional.date(from: value) {
            return parsed
        }

        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: value)
    }

    nonisolated private static func parseFallbackDate(_ value: String) -> Date? {
        for format in fallbackDateFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let parsed = formatter.date(from: value) {
                return parsed
            }
        }
        return nil
    }
}
