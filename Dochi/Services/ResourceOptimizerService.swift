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
    private(set) var latestSubscriptionUsageSnapshot: SubscriptionUsageSnapshot?

    private struct UsageCacheKey: Hashable {
        let subscriptionID: UUID
        let source: SubscriptionUsageSource
        let provider: String
        let startDay: String
    }

    private struct UsageCacheEntry {
        let tokens: Int
        let updatedAt: Date
    }

    private struct MonitoringSnapshotCacheEntry {
        let snapshot: SubscriptionMonitoringSnapshot
        let updatedAt: Date
    }

    private var usageCache: [UsageCacheKey: UsageCacheEntry] = [:]
    private var monitoringSnapshotCache: [UUID: MonitoringSnapshotCacheEntry] = [:]

    // MARK: - Dependencies

    private let baseURL: URL
    private let usageStore: UsageStoreProtocol?
    private let claudeProjectsRoots: [URL]
    private let codexSessionsRoots: [URL]
    private let geminiConfigRoots: [URL]
    private let externalUsageMonitor: ExternalUsageMonitor

    private let reserveBufferRatio = 0.08
    private let externalUsageCacheTTL: TimeInterval = 45

    // MARK: - Init

    init(
        baseURL: URL? = nil,
        usageStore: UsageStoreProtocol? = nil,
        claudeProjectsRoots: [URL]? = nil,
        codexSessionsRoots: [URL]? = nil,
        geminiConfigRoots: [URL]? = nil
    ) {
        let appSupport = baseURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dochi")
        let resolvedClaudeRoots = claudeProjectsRoots ?? Self.defaultClaudeProjectsRoots()
        let resolvedCodexRoots = codexSessionsRoots ?? Self.defaultCodexSessionsRoots()
        let resolvedGeminiRoots = geminiConfigRoots ?? Self.defaultGeminiConfigRoots()
        self.baseURL = appSupport
        self.usageStore = usageStore
        self.claudeProjectsRoots = resolvedClaudeRoots
        self.codexSessionsRoots = resolvedCodexRoots
        self.geminiConfigRoots = resolvedGeminiRoots
        self.externalUsageMonitor = ExternalUsageMonitor(
            codexSessionsRoots: resolvedCodexRoots,
            claudeProjectsRoots: resolvedClaudeRoots,
            geminiConfigRoots: resolvedGeminiRoots,
            cacheURL: appSupport.appendingPathComponent("external-usage-cache-v1.json")
        )
        loadFromDisk()
        loadSubscriptionUsageSnapshotFromDisk()
    }

    // MARK: - File Path

    private var filePath: URL {
        baseURL.appendingPathComponent("subscriptions.json")
    }

    private var subscriptionUsageSnapshotPath: URL {
        baseURL.appendingPathComponent("subscription-usage-snapshot.json")
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

    private func loadSubscriptionUsageSnapshotFromDisk() {
        do {
            let data = try Data(contentsOf: subscriptionUsageSnapshotPath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(SubscriptionUsageSnapshot.self, from: data)
            let liveIDs = Set(subscriptions.map(\.id))
            let snapshotIDs = Set(snapshot.utilizations.map { $0.subscription.id })
            guard liveIDs == snapshotIDs else {
                latestSubscriptionUsageSnapshot = nil
                return
            }
            latestSubscriptionUsageSnapshot = snapshot
        } catch {
            if (error as NSError).domain != NSCocoaErrorDomain
                || (error as NSError).code != NSFileReadNoSuchFileError {
                Log.storage.warning(
                    "Failed to load subscription usage snapshot: \(error.localizedDescription)"
                )
            }
        }
    }

    private func saveSubscriptionUsageSnapshotToDisk(_ snapshot: SubscriptionUsageSnapshot) {
        do {
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: subscriptionUsageSnapshotPath, options: .atomic)
        } catch {
            Log.storage.warning(
                "Failed to save subscription usage snapshot: \(error.localizedDescription)"
            )
        }
    }

    private func invalidateSubscriptionUsageSnapshot() {
        latestSubscriptionUsageSnapshot = nil
        do {
            if FileManager.default.fileExists(atPath: subscriptionUsageSnapshotPath.path) {
                try FileManager.default.removeItem(at: subscriptionUsageSnapshotPath)
            }
        } catch {
            Log.storage.warning(
                "Failed to remove stale subscription usage snapshot: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Subscription CRUD

    func addSubscription(_ plan: SubscriptionPlan) async {
        subscriptions.append(plan)
        monitoringSnapshotCache.removeValue(forKey: plan.id)
        invalidateSubscriptionUsageSnapshot()
        saveToDisk()
    }

    func updateSubscription(_ plan: SubscriptionPlan) async {
        if let index = subscriptions.firstIndex(where: { $0.id == plan.id }) {
            subscriptions[index] = plan
            usageCache = usageCache.filter { $0.key.subscriptionID != plan.id }
            monitoringSnapshotCache.removeValue(forKey: plan.id)
            invalidateSubscriptionUsageSnapshot()
            saveToDisk()
        }
    }

    func deleteSubscription(id: UUID) async {
        subscriptions.removeAll { $0.id == id }
        autoTaskRecords.removeAll { $0.subscriptionId == id }
        usageCache = usageCache.filter { $0.key.subscriptionID != id }
        monitoringSnapshotCache.removeValue(forKey: id)
        invalidateSubscriptionUsageSnapshot()
        saveToDisk()
    }

    func bootstrapDefaultExternalSubscriptionsIfNeeded() async -> Int {
        var addedCount = 0

        if shouldAutoRegisterProvider(.codex) {
            let hint = await bootstrapPlanHint(for: .codex)
            subscriptions.append(
                SubscriptionPlan(
                    providerName: "Codex",
                    planName: hint.planName,
                    usageSource: .externalToolLogs,
                    monthlyTokenLimit: hint.monthlyTokenLimit,
                    resetDayOfMonth: 1,
                    monthlyCostUSD: 0
                )
            )
            addedCount += 1
        }

        if shouldAutoRegisterProvider(.claude) {
            let hint = await bootstrapPlanHint(for: .claude)
            subscriptions.append(
                SubscriptionPlan(
                    providerName: "Claude",
                    planName: hint.planName,
                    usageSource: .externalToolLogs,
                    monthlyTokenLimit: hint.monthlyTokenLimit,
                    resetDayOfMonth: 1,
                    monthlyCostUSD: 0
                )
            )
            addedCount += 1
        }

        if shouldAutoRegisterProvider(.gemini) {
            let hint = await bootstrapPlanHint(for: .gemini)
            subscriptions.append(
                SubscriptionPlan(
                    providerName: "Gemini",
                    planName: hint.planName,
                    usageSource: .externalToolLogs,
                    monthlyTokenLimit: hint.monthlyTokenLimit,
                    resetDayOfMonth: 1,
                    monthlyCostUSD: 0
                )
            )
            addedCount += 1
        }

        if addedCount > 0 {
            usageCache.removeAll()
            monitoringSnapshotCache.removeAll()
            invalidateSubscriptionUsageSnapshot()
            saveToDisk()
            Log.app.info("Bootstrapped \(addedCount) external subscriptions")
        }

        return addedCount
    }

    func refreshSubscriptionUsageSnapshot(force: Bool) async -> SubscriptionUsageSnapshot {
        let liveIDs = Set(subscriptions.map(\.id))
        if !force, let cached = latestSubscriptionUsageSnapshot {
            let snapshotIDs = Set(cached.utilizations.map { $0.subscription.id })
            if liveIDs == snapshotIDs {
                return cached
            }
        }

        let utilizations = await allUtilizations()
        let monitoring = await monitoringSnapshots(for: utilizations.map(\.subscription))
        let snapshot = SubscriptionUsageSnapshot(
            capturedAt: Date(),
            utilizations: utilizations,
            monitoringSnapshots: monitoring
        )
        latestSubscriptionUsageSnapshot = snapshot
        saveSubscriptionUsageSnapshotToDisk(snapshot)
        return snapshot
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

    func monitoringSnapshot(for subscription: SubscriptionPlan) async -> SubscriptionMonitoringSnapshot {
        if let cached = monitoringSnapshotCache[subscription.id],
           Date().timeIntervalSince(cached.updatedAt) < externalUsageCacheTTL {
            return cached.snapshot
        }

        let snapshot: SubscriptionMonitoringSnapshot
        switch subscription.usageSource {
        case .externalToolLogs:
            snapshot = await externalMonitoringSnapshot(for: subscription)
        case .dochiUsageStore:
            let latestMap = await latestUsageStoreDatesByProvider(
                normalizedProviders: [normalizedProviderKey(subscription.providerName)]
            )
            snapshot = usageStoreMonitoringSnapshot(
                for: subscription,
                latestDate: latestMap[normalizedProviderKey(subscription.providerName)]
            )
        }

        monitoringSnapshotCache[subscription.id] = MonitoringSnapshotCacheEntry(
            snapshot: snapshot,
            updatedAt: Date()
        )
        return snapshot
    }

    func monitoringSnapshots(for subscriptions: [SubscriptionPlan]) async -> [UUID: SubscriptionMonitoringSnapshot] {
        var results: [UUID: SubscriptionMonitoringSnapshot] = [:]
        let now = Date()

        let dochiSubscriptions = subscriptions.filter { $0.usageSource == .dochiUsageStore }
        let providerKeys = Set(dochiSubscriptions.map { normalizedProviderKey($0.providerName) })
        let latestStoreDates = await latestUsageStoreDatesByProvider(normalizedProviders: providerKeys)

        for subscription in subscriptions {
            if let cached = monitoringSnapshotCache[subscription.id],
               now.timeIntervalSince(cached.updatedAt) < externalUsageCacheTTL {
                results[subscription.id] = cached.snapshot
                continue
            }

            let snapshot: SubscriptionMonitoringSnapshot
            switch subscription.usageSource {
            case .externalToolLogs:
                snapshot = await externalMonitoringSnapshot(for: subscription)
            case .dochiUsageStore:
                snapshot = usageStoreMonitoringSnapshot(
                    for: subscription,
                    latestDate: latestStoreDates[normalizedProviderKey(subscription.providerName)]
                )
            }

            monitoringSnapshotCache[subscription.id] = MonitoringSnapshotCacheEntry(
                snapshot: snapshot,
                updatedAt: now
            )
            results[subscription.id] = snapshot
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

        let utilizationSnapshot = await refreshSubscriptionUsageSnapshot(force: false)
        let utilizations = utilizationSnapshot.utilizations.filter {
            $0.subscription.usageSource == .externalToolLogs
        }
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

    // MARK: - Monitoring Snapshot Query

    private func externalMonitoringSnapshot(for subscription: SubscriptionPlan) async -> SubscriptionMonitoringSnapshot {
        let providerKind = Self.externalProviderKind(from: subscription.providerName)
        guard let externalProvider = Self.externalUsageProvider(from: providerKind) else {
            return SubscriptionMonitoringSnapshot(
                subscriptionID: subscription.id,
                source: subscription.usageSource,
                provider: subscription.providerName,
                statusCode: "unsupported_provider",
                statusMessage: "현재 프로바이더는 외부 로그/API 모니터링 대상이 아닙니다.",
                lastCollectedAt: nil
            )
        }

        var status = await externalUsageMonitor.status(provider: externalProvider)
        if status == nil {
            _ = await warmUpExternalProviderStatus(for: subscription, provider: externalProvider)
            status = await externalUsageMonitor.status(provider: externalProvider)
        }

        guard let status else {
            let message = externalProvider == .gemini
                ? "Gemini 수집 이력이 아직 없습니다. 인증 상태를 확인하세요."
                : "로그 수집 이력이 아직 없습니다."
            return SubscriptionMonitoringSnapshot(
                subscriptionID: subscription.id,
                source: subscription.usageSource,
                provider: subscription.providerName,
                statusCode: "no_data",
                statusMessage: message,
                lastCollectedAt: nil
            )
        }

        return SubscriptionMonitoringSnapshot(
            subscriptionID: subscription.id,
            source: subscription.usageSource,
            provider: subscription.providerName,
            statusCode: status.code,
            statusMessage: status.message,
            lastCollectedAt: status.lastCollectedAt,
            primaryWindow: Self.monitoringWindowSnapshot(from: status.primaryWindow),
            secondaryWindow: Self.monitoringWindowSnapshot(from: status.secondaryWindow)
        )
    }

    nonisolated private static func monitoringWindowSnapshot(
        from window: ExternalUsageRateWindow?
    ) -> MonitoringUsageWindowSnapshot? {
        guard let window else { return nil }
        return MonitoringUsageWindowSnapshot(
            label: window.label,
            usedPercent: window.usedPercent,
            windowMinutes: window.windowMinutes,
            resetsAt: window.resetsAt,
            resetDescription: window.resetDescription
        )
    }

    private func warmUpExternalProviderStatus(
        for subscription: SubscriptionPlan,
        provider: ExternalUsageProvider
    ) async -> Int {
        let since = Calendar.current.date(byAdding: .day, value: -35, to: Date()) ?? Date()
        switch provider {
        case .gemini:
            return await externalUsageMonitor.tokensUsed(
                provider: provider,
                since: since,
                tokenLimit: subscription.monthlyTokenLimit
            )
        case .codex, .claude:
            return await externalUsageMonitor.tokensUsed(provider: provider, since: since)
        }
    }

    private func usageStoreMonitoringSnapshot(
        for subscription: SubscriptionPlan,
        latestDate: Date?
    ) -> SubscriptionMonitoringSnapshot {
        guard usageStore != nil else {
            return SubscriptionMonitoringSnapshot(
                subscriptionID: subscription.id,
                source: subscription.usageSource,
                provider: subscription.providerName,
                statusCode: "no_data",
                statusMessage: "UsageStore가 초기화되지 않았습니다.",
                lastCollectedAt: nil
            )
        }
        guard let latestDate else {
            return SubscriptionMonitoringSnapshot(
                subscriptionID: subscription.id,
                source: subscription.usageSource,
                provider: subscription.providerName,
                statusCode: "no_data",
                statusMessage: "해당 프로바이더의 UsageStore 기록이 아직 없습니다.",
                lastCollectedAt: nil
            )
        }
        return SubscriptionMonitoringSnapshot(
            subscriptionID: subscription.id,
            source: subscription.usageSource,
            provider: subscription.providerName,
            statusCode: "ok_store",
            statusMessage: nil,
            lastCollectedAt: latestDate
        )
    }

    private func latestUsageStoreDatesByProvider(normalizedProviders: Set<String>) async -> [String: Date] {
        guard let store = usageStore else { return [:] }
        guard !normalizedProviders.isEmpty else { return [:] }

        var latestMap: [String: Date] = [:]
        for normalizedProvider in normalizedProviders {
            if let latest = await store.latestRecordDay(for: normalizedProvider) {
                latestMap[normalizedProvider] = latest
            }
        }

        return latestMap
    }

    // MARK: - Token Usage Query

    private func tokensUsed(for subscription: SubscriptionPlan, since startDate: Date) async -> Int {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        let key = UsageCacheKey(
            subscriptionID: subscription.id,
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
            tokens = await tokensUsedByExternalToolLogs(subscription, since: startDate)
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

    private func tokensUsedByExternalToolLogs(_ subscription: SubscriptionPlan, since startDate: Date) async -> Int {
        let provider = Self.externalProviderKind(from: subscription.providerName)
        switch provider {
        case .claude:
            return await externalUsageMonitor.tokensUsed(provider: .claude, since: startDate)
        case .codex:
            return await externalUsageMonitor.tokensUsed(provider: .codex, since: startDate)
        case .gemini:
            return await externalUsageMonitor.tokensUsed(
                provider: .gemini,
                since: startDate,
                tokenLimit: subscription.monthlyTokenLimit
            )
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
        case gemini
        case unknown
    }

    private struct BootstrapPlanHint {
        let planName: String
        let monthlyTokenLimit: Int?
    }

    private enum GeminiAuthTypeHint {
        case oauthPersonal
        case apiKey
        case vertexAI
        case unknown
    }

    private struct GeminiAuthProbeResult {
        let authType: GeminiAuthTypeHint
        let hasSettingsFile: Bool
        let hasOAuthCredentials: Bool
    }

    nonisolated private static func defaultClaudeProjectsRoots() -> [URL] {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser

        var rawRoots: [URL] = []
        if let custom = env["CLAUDE_CONFIG_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !custom.isEmpty {
            for component in custom.split(separator: ",") {
                let raw = String(component).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { continue }
                let expanded = NSString(string: raw).expandingTildeInPath
                let url = URL(fileURLWithPath: expanded)
                if url.lastPathComponent == "projects" {
                    rawRoots.append(url)
                } else {
                    rawRoots.append(url.appendingPathComponent("projects", isDirectory: true))
                }
            }
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

    nonisolated private static func defaultGeminiConfigRoots() -> [URL] {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser

        var rawRoots: [URL] = []
        if let custom = env["GEMINI_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !custom.isEmpty {
            let expanded = NSString(string: custom).expandingTildeInPath
            rawRoots.append(URL(fileURLWithPath: expanded))
        }
        rawRoots.append(home.appendingPathComponent(".gemini", isDirectory: true))
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
        if normalized.contains("gemini") {
            return .gemini
        }
        if normalized.contains("codex")
            || normalized.contains("chatgpt")
            || normalized.contains("openai") {
            return .codex
        }
        return .unknown
    }

    nonisolated private static func externalUsageProvider(from kind: ExternalProviderKind) -> ExternalUsageProvider? {
        switch kind {
        case .claude:
            return .claude
        case .codex:
            return .codex
        case .gemini:
            return .gemini
        case .unknown:
            return nil
        }
    }

    private func shouldAutoRegisterProvider(_ kind: ExternalProviderKind) -> Bool {
        if hasExistingSubscription(for: kind) { return false }

        switch kind {
        case .codex:
            return hasAnyFile(in: codexSessionsRoots, withExtensions: ["jsonl"])
        case .claude:
            return hasAnyFile(in: claudeProjectsRoots, withExtensions: ["jsonl"])
        case .gemini:
            return shouldAutoRegisterGeminiSubscription()
        case .unknown:
            return false
        }
    }

    private func bootstrapPlanHint(for kind: ExternalProviderKind) async -> BootstrapPlanHint {
        switch kind {
        case .codex:
            let planType = detectCodexPlanType()
            return BootstrapPlanHint(
                planName: codexPlanName(from: planType),
                monthlyTokenLimit: await estimatedMonthlyTokenLimit(for: .codex, codexPlanType: planType)
            )
        case .claude:
            return BootstrapPlanHint(
                planName: "Auto Detected",
                monthlyTokenLimit: await estimatedMonthlyTokenLimit(for: .claude, codexPlanType: nil)
            )
        case .gemini:
            let auth = probeGeminiAuth()
            return BootstrapPlanHint(
                planName: geminiPlanName(for: auth.authType),
                monthlyTokenLimit: nil
            )
        case .unknown:
            return BootstrapPlanHint(planName: "Auto Detected", monthlyTokenLimit: nil)
        }
    }

    private func estimatedMonthlyTokenLimit(
        for kind: ExternalProviderKind,
        codexPlanType: String?
    ) async -> Int? {
        if let dynamic = await estimatedMonthlyTokenLimitFromRecentUsage(for: kind) {
            return dynamic
        }
        guard kind == .codex else { return nil }
        switch codexPlanType {
        case "free", "free_workspace":
            return 1_000_000
        case "plus":
            return 3_000_000
        default:
            return nil
        }
    }

    private func estimatedMonthlyTokenLimitFromRecentUsage(for kind: ExternalProviderKind) async -> Int? {
        guard let provider = Self.externalUsageProvider(from: kind), provider != .gemini else {
            return nil
        }
        let now = Date()
        let since = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let usedTokens = await externalUsageMonitor.tokensUsed(
            provider: provider,
            since: since,
            now: now
        )
        guard usedTokens > 0 else { return nil }

        let conservativeEstimate = Int((Double(usedTokens) * 1.8).rounded())
        let floor = 300_000
        let cap = 200_000_000
        let clamped = min(cap, max(floor, conservativeEstimate))
        return ((clamped + 49_999) / 50_000) * 50_000
    }

    private func shouldAutoRegisterGeminiSubscription() -> Bool {
        let auth = probeGeminiAuth()
        switch auth.authType {
        case .oauthPersonal:
            return true
        case .apiKey, .vertexAI:
            // API key / Vertex AI는 종량제 축에서 다루고 구독제 자동 등록은 제외.
            return false
        case .unknown:
            return auth.hasSettingsFile || auth.hasOAuthCredentials
        }
    }

    private func probeGeminiAuth() -> GeminiAuthProbeResult {
        let fileManager = FileManager.default
        var hasSettingsFile = false
        var hasOAuthCredentials = false
        var detectedType: GeminiAuthTypeHint = .unknown

        for root in geminiConfigRoots {
            let settingsURL = root.appendingPathComponent("settings.json")
            if fileManager.fileExists(atPath: settingsURL.path) {
                hasSettingsFile = true
                if detectedType == .unknown,
                   let parsedType = parseGeminiAuthType(fromSettingsURL: settingsURL) {
                    detectedType = parsedType
                }
            }

            let credentialsURL = root.appendingPathComponent("oauth_creds.json")
            if fileManager.fileExists(atPath: credentialsURL.path) {
                hasOAuthCredentials = true
            }
        }

        if detectedType == .unknown, hasOAuthCredentials {
            detectedType = .oauthPersonal
        }

        return GeminiAuthProbeResult(
            authType: detectedType,
            hasSettingsFile: hasSettingsFile,
            hasOAuthCredentials: hasOAuthCredentials
        )
    }

    private func parseGeminiAuthType(fromSettingsURL url: URL) -> GeminiAuthTypeHint? {
        guard
            let data = try? Data(contentsOf: url),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return nil
        }

        let selectedType =
            (object["selectedAuthType"] as? String)
            ?? jsonString(in: object, path: ["security", "auth", "selectedType"])
            ?? jsonString(in: object, path: ["security", "auth", "selectedAuthType"])
        guard let selectedType else { return nil }
        return geminiAuthTypeHint(from: selectedType)
    }

    private func geminiAuthTypeHint(from raw: String) -> GeminiAuthTypeHint {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "oauth-personal":
            return .oauthPersonal
        case "api-key":
            return .apiKey
        case "vertex-ai":
            return .vertexAI
        default:
            return .unknown
        }
    }

    private func geminiPlanName(for authType: GeminiAuthTypeHint) -> String {
        switch authType {
        case .oauthPersonal:
            return "Gemini Personal (Auto)"
        case .apiKey:
            return "Gemini API Key (Metered)"
        case .vertexAI:
            return "Gemini Vertex AI (Metered)"
        case .unknown:
            return "Auto Detected"
        }
    }

    private func codexPlanName(from rawPlanType: String?) -> String {
        guard let rawPlanType, !rawPlanType.isEmpty else { return "Auto Detected" }
        switch rawPlanType {
        case "pro":
            return "ChatGPT Pro (Auto)"
        case "plus":
            return "ChatGPT Plus (Auto)"
        case "free":
            return "ChatGPT Free (Auto)"
        case "free_workspace":
            return "ChatGPT Free Workspace (Auto)"
        case "team":
            return "ChatGPT Team (Auto)"
        case "enterprise":
            return "ChatGPT Enterprise (Auto)"
        default:
            return "ChatGPT \(humanizedPlanFragment(rawPlanType)) (Auto)"
        }
    }

    private func detectCodexPlanType() -> String? {
        for authURL in codexAuthCandidateURLs() {
            guard
                let data = try? Data(contentsOf: authURL),
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else {
                continue
            }

            if let direct = extractCodexPlanType(from: object) {
                return direct
            }

            guard let tokens = object["tokens"] as? [String: Any] else { continue }
            for key in ["id_token", "access_token"] {
                guard let token = tokens[key] as? String,
                      let claims = decodeJWTClaims(token),
                      let planType = extractCodexPlanType(from: claims) else {
                    continue
                }
                return planType
            }
        }
        return nil
    }

    private func codexAuthCandidateURLs() -> [URL] {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates: [URL] = []

        if let codexHome = env["CODEX_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !codexHome.isEmpty {
            let expanded = NSString(string: codexHome).expandingTildeInPath
            candidates.append(URL(fileURLWithPath: expanded).appendingPathComponent("auth.json"))
        }

        for root in codexSessionsRoots {
            let normalized = root.standardizedFileURL
            candidates.append(normalized.appendingPathComponent("auth.json"))
            if normalized.lastPathComponent == "sessions" {
                candidates.append(normalized.deletingLastPathComponent().appendingPathComponent("auth.json"))
            } else {
                candidates.append(normalized.deletingLastPathComponent().appendingPathComponent("auth.json"))
            }
        }

        candidates.append(home.appendingPathComponent(".codex/auth.json"))
        return Self.uniqueStandardizedPaths(candidates)
    }

    private func extractCodexPlanType(from object: [String: Any]) -> String? {
        if let direct = normalizedPlanTypeString(object["chatgpt_plan_type"]) {
            return direct
        }
        if let direct = normalizedPlanTypeString(object["plan_type"]) {
            return direct
        }
        if let auth = object["https://api.openai.com/auth"] as? [String: Any],
           let nested = normalizedPlanTypeString(auth["chatgpt_plan_type"]) {
            return nested
        }
        return nil
    }

    private func normalizedPlanTypeString(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func decodeJWTClaims(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return nil }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard
            let data = Data(base64Encoded: payload),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return nil
        }
        return object
    }

    private func humanizedPlanFragment(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { token in token.capitalized }
            .joined(separator: " ")
    }

    private func jsonString(in object: [String: Any], path: [String]) -> String? {
        var current: Any = object
        for key in path {
            guard let dictionary = current as? [String: Any],
                  let next = dictionary[key] else {
                return nil
            }
            current = next
        }
        return current as? String
    }

    private func hasExistingSubscription(for kind: ExternalProviderKind) -> Bool {
        subscriptions.contains { subscription in
            subscription.usageSource == .externalToolLogs
                && Self.externalProviderKind(from: subscription.providerName) == kind
        }
    }

    private func hasAnyFile(in roots: [URL], withExtensions extensions: Set<String>) -> Bool {
        let fileManager = FileManager.default
        for root in roots {
            guard fileManager.fileExists(atPath: root.path) else { continue }
            if let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                for case let fileURL as URL in enumerator {
                    let ext = fileURL.pathExtension.lowercased()
                    if extensions.contains(ext) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func hasGeminiConfigArtifacts() -> Bool {
        let auth = probeGeminiAuth()
        return auth.hasSettingsFile || auth.hasOAuthCredentials
    }
}
