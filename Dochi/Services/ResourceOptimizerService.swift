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

    // MARK: - Dependencies

    private let baseURL: URL
    private let usageStore: UsageStoreProtocol?

    private let reserveBufferRatio = 0.08

    // MARK: - Init

    init(baseURL: URL? = nil, usageStore: UsageStoreProtocol? = nil) {
        let appSupport = baseURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dochi")
        self.baseURL = appSupport
        self.usageStore = usageStore
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
        let usedTokens = await tokensUsedByProvider(subscription.providerName, since: periodStart)

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

    private func tokensUsedByProvider(_ providerName: String, since startDate: Date) async -> Int {
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
}
