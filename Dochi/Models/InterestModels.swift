import Foundation

// MARK: - K-3: Interest Discovery Models

enum InterestStatus: String, Codable, Sendable {
    case confirmed
    case inferred
    case expired
}

struct InterestEntry: Identifiable, Codable, Sendable {
    let id: UUID
    var topic: String
    var status: InterestStatus
    var confidence: Double
    var source: String
    var firstSeen: Date
    var lastSeen: Date
    var tags: [String]

    init(
        id: UUID = UUID(),
        topic: String,
        status: InterestStatus = .inferred,
        confidence: Double = 0.5,
        source: String = "",
        firstSeen: Date = Date(),
        lastSeen: Date = Date(),
        tags: [String] = []
    ) {
        self.id = id
        self.topic = topic
        self.status = status
        self.confidence = confidence
        self.source = source
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.tags = tags
    }
}

struct InterestProfile: Codable, Sendable {
    var interests: [InterestEntry]
    var lastDiscoveryDate: Date?
    var discoveryMode: DiscoveryMode

    init(
        interests: [InterestEntry] = [],
        lastDiscoveryDate: Date? = nil,
        discoveryMode: DiscoveryMode = .auto
    ) {
        self.interests = interests
        self.lastDiscoveryDate = lastDiscoveryDate
        self.discoveryMode = discoveryMode
    }
}

enum DiscoveryMode: String, Codable, Sendable, CaseIterable {
    case auto
    case eager
    case passive
    case manual

    var displayName: String {
        switch self {
        case .auto: return "자동"
        case .eager: return "적극"
        case .passive: return "수동"
        case .manual: return "비활성"
        }
    }
}

enum DiscoveryAggressiveness: Sendable, Equatable {
    case eager    // 0~2 confirmed
    case active   // 3~5 confirmed
    case passive  // 6+ confirmed

    var displayName: String {
        switch self {
        case .eager: return "적극"
        case .active: return "보통"
        case .passive: return "수동"
        }
    }

    var displayColor: String {
        switch self {
        case .eager: return "orange"
        case .active: return "blue"
        case .passive: return "green"
        }
    }
}
