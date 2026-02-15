import Foundation
import os

/// Persistent usage data store. Saves monthly JSON files to disk with debounced writes.
/// Storage path: `{baseURL}/usage/{yyyy-MM}.json`
@MainActor
@Observable
final class UsageStore: UsageStoreProtocol {

    private let baseURL: URL
    private var cache: [String: MonthlyUsageFile] = [:]
    private var dirtyMonths: Set<String> = []
    private var saveTask: Task<Void, Never>?
    private static let debounceInterval: TimeInterval = 5.0

    /// Date formatter for month keys (yyyy-MM).
    private static let monthFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()

    /// Date formatter for day keys (yyyy-MM-dd).
    private static let dayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()

    init(baseURL: URL) {
        self.baseURL = baseURL
        let usageDir = baseURL.appendingPathComponent("usage", isDirectory: true)
        try? FileManager.default.createDirectory(at: usageDir, withIntermediateDirectories: true)
    }

    // MARK: - UsageStoreProtocol

    func record(_ metrics: ExchangeMetrics) async {
        let monthKey = Self.monthFormatter.string(from: metrics.timestamp)
        let dayKey = Self.dayFormatter.string(from: metrics.timestamp)

        let inputTokens = metrics.inputTokens ?? 0
        let outputTokens = metrics.outputTokens ?? 0
        let cost = ModelPricingTable.estimateCost(
            model: metrics.model,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )

        let entry = UsageEntry(
            provider: metrics.provider,
            model: metrics.model,
            agentName: metrics.agentName,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            exchangeCount: 1,
            estimatedCostUSD: cost,
            timestamp: metrics.timestamp
        )

        var file = await loadMonth(monthKey)
        if let dayIndex = file.days.firstIndex(where: { $0.date == dayKey }) {
            file.days[dayIndex].entries.append(entry)
        } else {
            file.days.append(DailyUsageRecord(date: dayKey, entries: [entry]))
        }

        cache[monthKey] = file
        dirtyMonths.insert(monthKey)
        scheduleSave()

        Log.storage.debug("Usage recorded: \(metrics.model) \(inputTokens)+\(outputTokens) tokens, $\(String(format: "%.4f", cost))")
    }

    func dailyRecords(for month: String) async -> [DailyUsageRecord] {
        let file = await loadMonth(month)
        return file.days.sorted { $0.date < $1.date }
    }

    func monthlySummary(for month: String) async -> MonthlyUsageSummary {
        let file = await loadMonth(month)
        let totalExchanges = file.days.reduce(0) { $0 + $1.totalExchanges }
        let totalInput = file.days.reduce(0) { $0 + $1.totalInputTokens }
        let totalOutput = file.days.reduce(0) { $0 + $1.totalOutputTokens }
        let totalCost = file.days.reduce(0.0) { $0 + $1.totalCostUSD }

        return MonthlyUsageSummary(
            month: month,
            totalExchanges: totalExchanges,
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput,
            totalCostUSD: totalCost,
            days: file.days.sorted { $0.date < $1.date }
        )
    }

    func allMonths() async -> [String] {
        let usageDir = baseURL.appendingPathComponent("usage", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: usageDir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    func currentMonthCost() async -> Double {
        let monthKey = Self.monthFormatter.string(from: Date())
        let summary = await monthlySummary(for: monthKey)
        return summary.totalCostUSD
    }

    // MARK: - File I/O

    private func loadMonth(_ monthKey: String) async -> MonthlyUsageFile {
        if let cached = cache[monthKey] {
            return cached
        }

        let fileURL = usageFileURL(for: monthKey)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let empty = MonthlyUsageFile(days: [])
            cache[monthKey] = empty
            return empty
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let file = try decoder.decode(MonthlyUsageFile.self, from: data)
            cache[monthKey] = file
            return file
        } catch {
            Log.storage.error("Failed to load usage file \(monthKey): \(error.localizedDescription)")
            let empty = MonthlyUsageFile(days: [])
            cache[monthKey] = empty
            return empty
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.debounceInterval))
            guard !Task.isCancelled else { return }
            await self?.flushToDisk()
        }
    }

    /// Flush all dirty months to disk immediately (synchronous variant for app termination).
    nonisolated func flushToDiskSync() {
        MainActor.assumeIsolated {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            for monthKey in dirtyMonths {
                guard let file = cache[monthKey] else { continue }
                let fileURL = usageFileURL(for: monthKey)
                do {
                    let data = try encoder.encode(file)
                    try data.write(to: fileURL, options: .atomic)
                    Log.storage.debug("Usage file saved (sync): \(monthKey)")
                } catch {
                    Log.storage.error("Failed to save usage file (sync) \(monthKey): \(error.localizedDescription)")
                }
            }
            dirtyMonths.removeAll()
        }
    }

    /// Flush all dirty months to disk immediately.
    func flushToDisk() async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        for monthKey in dirtyMonths {
            guard let file = cache[monthKey] else { continue }
            let fileURL = usageFileURL(for: monthKey)
            do {
                let data = try encoder.encode(file)
                try data.write(to: fileURL, options: .atomic)
                Log.storage.debug("Usage file saved: \(monthKey)")
            } catch {
                Log.storage.error("Failed to save usage file \(monthKey): \(error.localizedDescription)")
            }
        }
        dirtyMonths.removeAll()
    }

    private func usageFileURL(for monthKey: String) -> URL {
        baseURL
            .appendingPathComponent("usage", isDirectory: true)
            .appendingPathComponent("\(monthKey).json")
    }
}
