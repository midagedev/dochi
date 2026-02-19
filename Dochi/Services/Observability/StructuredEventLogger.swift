import Foundation
import os

// MARK: - Event Types

/// 구조화 이벤트 타입.
enum StructuredEventType: String, Codable, Sendable {
    case sessionStart
    case sessionEnd
    case toolCall
    case toolResult
    case hookDecision
    case approvalRequest
    case approvalResolve
    case routingDecision
    case leaseAcquired
    case leaseExpired
}

/// 구조화 이벤트 — JSON 직렬화 가능한 로그 이벤트.
struct StructuredEvent: Identifiable, Codable, Sendable {
    let id: UUID
    let traceId: UUID?
    let sessionId: String?
    let eventType: StructuredEventType
    let payload: [String: String]
    let timestamp: Date

    init(
        id: UUID = UUID(),
        traceId: UUID? = nil,
        sessionId: String? = nil,
        eventType: StructuredEventType,
        payload: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.traceId = traceId
        self.sessionId = sessionId
        self.eventType = eventType
        self.payload = payload
        self.timestamp = timestamp
    }
}

// MARK: - StructuredEventLogger

/// 구조화 JSON 이벤트 로그 기록 및 조회.
@MainActor
@Observable
final class StructuredEventLogger: StructuredEventLoggerProtocol {
    private var events: [StructuredEvent] = []
    private var eventsByTrace: [UUID: [StructuredEvent]] = [:]
    private var eventsBySession: [String: [StructuredEvent]] = [:]

    private static let maxEvents = 5000

    // MARK: - StructuredEventLoggerProtocol

    func log(event: StructuredEvent) {
        events.append(event)

        if let traceId = event.traceId {
            eventsByTrace[traceId, default: []].append(event)
        }
        if let sessionId = event.sessionId {
            eventsBySession[sessionId, default: []].append(event)
        }

        evictOldEvents()

        Log.app.debug("Event logged: \(event.eventType.rawValue) trace=\(event.traceId?.uuidString.prefix(8) ?? "nil") session=\(event.sessionId ?? "nil")")
    }

    func events(for traceId: UUID) -> [StructuredEvent] {
        eventsByTrace[traceId] ?? []
    }

    func events(for sessionId: String) -> [StructuredEvent] {
        eventsBySession[sessionId] ?? []
    }

    var allEvents: [StructuredEvent] {
        events
    }

    func exportJSON(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(events)
        try data.write(to: url)
        Log.app.info("Exported \(self.events.count) events to \(url.path)")
    }

    // MARK: - Private

    private func evictOldEvents() {
        guard events.count > Self.maxEvents else { return }
        let excess = events.count - Self.maxEvents
        let removed = Array(events.prefix(excess))
        events.removeFirst(excess)

        // 인덱스에서도 제거
        for event in removed {
            if let traceId = event.traceId {
                eventsByTrace[traceId]?.removeAll { $0.id == event.id }
                if eventsByTrace[traceId]?.isEmpty == true {
                    eventsByTrace.removeValue(forKey: traceId)
                }
            }
            if let sessionId = event.sessionId {
                eventsBySession[sessionId]?.removeAll { $0.id == event.id }
                if eventsBySession[sessionId]?.isEmpty == true {
                    eventsBySession.removeValue(forKey: sessionId)
                }
            }
        }
    }
}
