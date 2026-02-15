import Foundation
import os

// MARK: - K-3: Interest Discovery Service Protocol

@MainActor
protocol InterestDiscoveryServiceProtocol: AnyObject {
    var profile: InterestProfile { get }
    var currentAggressiveness: DiscoveryAggressiveness { get }

    func loadProfile(userId: String)
    func saveProfile(userId: String)

    func addInterest(_ entry: InterestEntry)
    func updateInterest(id: UUID, topic: String?, tags: [String]?)
    func confirmInterest(id: UUID)
    func restoreInterest(id: UUID)
    func removeInterest(id: UUID)

    func analyzeMessage(_ content: String, conversationId: UUID)
    func buildDiscoverySystemPromptAddition() -> String?

    func checkExpirations()
    func syncToMemory(contextService: ContextServiceProtocol, userId: String)
}

// MARK: - Implementation

@MainActor
@Observable
final class InterestDiscoveryService: InterestDiscoveryServiceProtocol {
    // internal(set) for test access to mutate profile directly
    var profile = InterestProfile()

    private let settings: AppSettings
    private let baseURL: URL

    private static let interestSignals = ["관심", "궁금", "배워", "해볼까", "좋아", "재미"]
    private static let emotionSignals = ["재미있", "어렵", "좋다", "신기하"]

    /// Keyword frequency tracker per conversation for inferred interest detection
    private var keywordCounts: [String: Int] = [:]

    init(settings: AppSettings) {
        self.settings = settings
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.baseURL = appSupport.appendingPathComponent("Dochi").appendingPathComponent("interests")
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        Log.app.info("InterestDiscoveryService initialized")
    }

    // MARK: - Aggressiveness

    var currentAggressiveness: DiscoveryAggressiveness {
        switch profile.discoveryMode {
        case .eager: return .eager
        case .passive: return .passive
        case .manual: return .passive
        case .auto:
            let confirmedCount = profile.interests.filter { $0.status == .confirmed }.count
            if confirmedCount <= 2 { return .eager }
            if confirmedCount <= 5 { return .active }
            return .passive
        }
    }

    // MARK: - Persistence

    func loadProfile(userId: String) {
        let fileURL = baseURL.appendingPathComponent("\(userId).json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            profile = InterestProfile()
            Log.storage.debug("No interest profile found for \(userId), using empty")
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            profile = try decoder.decode(InterestProfile.self, from: data)
            Log.storage.info("Loaded interest profile for \(userId): \(self.profile.interests.count) interests")
        } catch {
            Log.storage.error("Failed to load interest profile: \(error.localizedDescription)")
            profile = InterestProfile()
        }
    }

    func saveProfile(userId: String) {
        let fileURL = baseURL.appendingPathComponent("\(userId).json")
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(profile)
            try data.write(to: fileURL, options: .atomic)
            Log.storage.debug("Saved interest profile for \(userId)")
        } catch {
            Log.storage.error("Failed to save interest profile: \(error.localizedDescription)")
        }
    }

    // MARK: - CRUD

    func addInterest(_ entry: InterestEntry) {
        if let existingIndex = profile.interests.firstIndex(where: {
            $0.topic.lowercased() == entry.topic.lowercased()
        }) {
            profile.interests[existingIndex].lastSeen = Date()
            if entry.confidence > profile.interests[existingIndex].confidence {
                profile.interests[existingIndex].confidence = entry.confidence
            }
            Log.app.debug("Updated existing interest: \(entry.topic)")
        } else {
            profile.interests.append(entry)
            Log.app.info("Added new interest: \(entry.topic) (\(entry.status.rawValue))")
        }
    }

    func updateInterest(id: UUID, topic: String?, tags: [String]?) {
        guard let index = profile.interests.firstIndex(where: { $0.id == id }) else { return }
        if let topic { profile.interests[index].topic = topic }
        if let tags { profile.interests[index].tags = tags }
    }

    func confirmInterest(id: UUID) {
        guard let index = profile.interests.firstIndex(where: { $0.id == id }) else { return }
        profile.interests[index].status = .confirmed
        profile.interests[index].confidence = 1.0
        profile.interests[index].lastSeen = Date()
        Log.app.info("Confirmed interest: \(self.profile.interests[index].topic)")
    }

    func restoreInterest(id: UUID) {
        guard let index = profile.interests.firstIndex(where: { $0.id == id }) else { return }
        profile.interests[index].status = .confirmed
        profile.interests[index].confidence = 1.0
        profile.interests[index].lastSeen = Date()
        Log.app.info("Restored interest: \(self.profile.interests[index].topic)")
    }

    func removeInterest(id: UUID) {
        profile.interests.removeAll { $0.id == id }
    }

    // MARK: - Message Analysis

    func analyzeMessage(_ content: String, conversationId: UUID) {
        guard settings.interestDiscoveryEnabled else { return }
        guard profile.discoveryMode != .manual else { return }

        let lowered = content.lowercased()

        // Extract potential topic keywords (nouns near interest signals)
        for signal in Self.interestSignals {
            if lowered.contains(signal) {
                let words = extractTopicWords(from: content, near: signal)
                for word in words {
                    let count = (keywordCounts[word] ?? 0) + 1
                    keywordCounts[word] = count

                    if count >= settings.interestMinDetectionCount {
                        let alreadyExists = profile.interests.contains {
                            $0.topic.lowercased().contains(word.lowercased())
                        }
                        if !alreadyExists {
                            let entry = InterestEntry(
                                topic: word,
                                status: .inferred,
                                confidence: min(0.3 + Double(count) * 0.15, 0.9),
                                source: "conversation:\(conversationId.uuidString)",
                                tags: []
                            )
                            addInterest(entry)
                        }
                    }
                }
            }
        }
    }

    /// Extract topic words near an interest signal keyword
    private func extractTopicWords(from content: String, near signal: String) -> [String] {
        let words = content.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && $0.count >= 2 }

        guard let signalIndex = words.firstIndex(where: { $0.lowercased().contains(signal) }) else {
            return []
        }

        let windowStart = max(0, signalIndex - 3)
        let windowEnd = min(words.count, signalIndex + 4)
        let nearby = words[windowStart..<windowEnd]

        // Filter out common words and the signal itself
        let stopWords: Set<String> = [
            "이", "그", "저", "것", "거", "좀", "요", "네", "뭐", "어떤",
            "있", "없", "하", "되", "수", "등", "때", "중", "위", "더",
            signal
        ]
        return nearby.filter { word in
            !stopWords.contains(where: { word.lowercased().contains($0) }) && word.count >= 2
        }
    }

    // MARK: - System Prompt Addition

    func buildDiscoverySystemPromptAddition() -> String? {
        guard settings.interestDiscoveryEnabled else { return nil }
        guard settings.interestIncludeInPrompt else { return nil }

        var parts: [String] = []

        // List known interests
        let confirmed = profile.interests.filter { $0.status == .confirmed }
        let inferred = profile.interests.filter { $0.status == .inferred }

        if !confirmed.isEmpty || !inferred.isEmpty {
            var lines = ["## 사용자 관심사"]
            for entry in confirmed {
                lines.append("- [확인됨] \(entry.topic)")
            }
            for entry in inferred {
                let pct = Int(entry.confidence * 100)
                lines.append("- [추정] \(entry.topic) (신뢰도 \(pct)%)")
            }
            parts.append(lines.joined(separator: "\n"))
        }

        // Discovery instructions based on aggressiveness
        let aggressiveness = currentAggressiveness
        switch aggressiveness {
        case .eager:
            parts.append("""
            ## 관심사 발굴 지시
            사용자의 개인 컨텍스트가 부족합니다. 대화 중에 자연스럽게 다음을 파악하세요:
            - 주로 하는 작업이나 직업
            - 자주 쓰는 도구나 언어
            - 요즘 관심있는 주제
            직접적인 설문 형태가 아니라 대화 흐름에 녹여서 물어보세요.
            """)
        case .active:
            parts.append("""
            ## 관심사 발굴 지시
            사용자가 새로운 주제에 관심을 보이면, 구체적인 관심 분야를 자연스럽게 파악하세요.
            """)
        case .passive:
            break
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    // MARK: - Expiration

    func checkExpirations() {
        let expirationDays = settings.interestExpirationDays
        let cutoff = Calendar.current.date(byAdding: .day, value: -expirationDays, to: Date()) ?? Date()

        for i in profile.interests.indices {
            if profile.interests[i].status != .expired &&
               profile.interests[i].lastSeen < cutoff {
                profile.interests[i].status = .expired
                Log.app.info("Interest expired: \(self.profile.interests[i].topic)")
            }
        }
    }

    // MARK: - Memory Sync

    func syncToMemory(contextService: ContextServiceProtocol, userId: String) {
        let confirmed = profile.interests.filter { $0.status == .confirmed }
        let inferred = profile.interests.filter { $0.status == .inferred }

        guard !confirmed.isEmpty || !inferred.isEmpty else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"

        var lines = ["## 관심사"]
        for entry in confirmed {
            lines.append("- [확인됨] \(entry.topic) (\(formatter.string(from: entry.firstSeen)) ~)")
        }
        for entry in inferred {
            let pct = Int(entry.confidence * 100)
            let dateStr = formatter.string(from: entry.lastSeen)
            lines.append("- [추정] \(entry.topic) (신뢰도 \(pct)%, \(dateStr) 대화에서 언급)")
        }

        let interestSection = lines.joined(separator: "\n")

        // Load existing memory and replace/append interest section
        var memory = contextService.loadUserMemory(userId: userId) ?? ""

        if let range = memory.range(of: "## 관심사") {
            // Find end of section (next ## header or end of file)
            let afterSection = memory[range.lowerBound...]
            if let nextHeader = afterSection.dropFirst(5).range(of: "\n## ") {
                let sectionEnd = memory.index(nextHeader.lowerBound, offsetBy: 1)
                memory.replaceSubrange(range.lowerBound..<sectionEnd, with: interestSection)
            } else {
                memory.replaceSubrange(range.lowerBound..., with: interestSection)
            }
        } else {
            if !memory.isEmpty { memory += "\n\n" }
            memory += interestSection
        }

        contextService.saveUserMemory(userId: userId, content: memory)
        Log.app.debug("Synced interests to memory for \(userId)")
    }
}
