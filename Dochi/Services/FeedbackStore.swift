import Foundation

/// 피드백 저장소 — 로컬 JSON 파일 기반 (I-4)
@MainActor
@Observable
final class FeedbackStore: FeedbackStoreProtocol {

    // MARK: - Constants

    static let maxEntries = 1000
    private static let saveDebounceInterval: TimeInterval = 2.0

    // MARK: - State

    private(set) var entries: [FeedbackEntry] = []
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    // MARK: - Init

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dochiDir = appSupport.appendingPathComponent("Dochi")
            self.fileURL = dochiDir.appendingPathComponent("feedback.json")
        }
        load()
    }

    // MARK: - Public Methods

    func add(_ entry: FeedbackEntry) {
        // Remove existing feedback for same message (toggle behavior)
        entries.removeAll { $0.messageId == entry.messageId }
        entries.append(entry)

        // FIFO: keep only last maxEntries
        if entries.count > Self.maxEntries {
            entries = Array(entries.suffix(Self.maxEntries))
        }

        scheduleSave()
        Log.storage.info("Feedback added: \(entry.rating.rawValue) for message \(entry.messageId)")
    }

    func remove(messageId: UUID) {
        entries.removeAll { $0.messageId == messageId }
        scheduleSave()
        Log.storage.info("Feedback removed for message \(messageId)")
    }

    func rating(for messageId: UUID) -> FeedbackRating? {
        entries.first(where: { $0.messageId == messageId })?.rating
    }

    func satisfactionRate(model: String? = nil, agent: String? = nil) -> Double {
        var filtered = entries
        if let model {
            filtered = filtered.filter { $0.model == model }
        }
        if let agent {
            filtered = filtered.filter { $0.agentName == agent }
        }
        guard !filtered.isEmpty else { return 0.0 }
        let positive = filtered.filter { $0.rating == .positive }.count
        return Double(positive) / Double(filtered.count)
    }

    func recentNegative(limit: Int = 10) -> [FeedbackEntry] {
        let negative = entries.filter { $0.rating == .negative }
        let sorted = negative.sorted { $0.timestamp > $1.timestamp }
        return Array(sorted.prefix(limit))
    }

    func modelBreakdown() -> [ModelSatisfaction] {
        let grouped = Dictionary(grouping: entries) { $0.model }
        return grouped.map { model, entries in
            let positive = entries.filter { $0.rating == .positive }.count
            let provider = entries.first?.provider ?? ""
            return ModelSatisfaction(
                model: model,
                provider: provider,
                totalCount: entries.count,
                positiveCount: positive
            )
        }.sorted { $0.totalCount > $1.totalCount }
    }

    func agentBreakdown() -> [AgentSatisfaction] {
        let grouped = Dictionary(grouping: entries) { $0.agentName }
        return grouped.map { agent, entries in
            let positive = entries.filter { $0.rating == .positive }.count
            return AgentSatisfaction(
                agentName: agent,
                totalCount: entries.count,
                positiveCount: positive
            )
        }.sorted { $0.totalCount > $1.totalCount }
    }

    func categoryDistribution() -> [CategoryCount] {
        let negative = entries.filter { $0.rating == .negative && $0.category != nil }
        let grouped = Dictionary(grouping: negative) { $0.category! }
        return grouped.map { category, entries in
            CategoryCount(category: category, count: entries.count)
        }.sorted { $0.count > $1.count }
    }

    // MARK: - File I/O

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            Log.storage.debug("Feedback file not found, starting empty")
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([FeedbackEntry].self, from: data)
            let count = entries.count
            Log.storage.info("Loaded \(count) feedback entries")
        } catch {
            Log.storage.error("Failed to load feedback: \(error.localizedDescription)")
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(Self.saveDebounceInterval))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    func save() {
        do {
            let dir = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
            let count = entries.count
            Log.storage.debug("Saved \(count) feedback entries")
        } catch {
            Log.storage.error("Failed to save feedback: \(error.localizedDescription)")
        }
    }
}
