import Foundation
import os

// MARK: - Data Models

/// 트레이스 span의 상태.
enum TraceSpanStatus: String, Codable, Sendable {
    case running
    case ok
    case error
    case cancelled
}

/// 개별 span — 트레이스 내의 단일 작업 단위.
struct TraceSpan: Identifiable, Codable, Sendable {
    let id: UUID
    let traceId: UUID
    let parentSpanId: UUID?
    let name: String
    let startTime: Date
    var endTime: Date?
    var status: TraceSpanStatus
    var attributes: [String: String]

    /// span 소요 시간 (밀리초). 미종료 시 현재까지의 경과 시간.
    var durationMs: Double {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime) * 1000.0
    }

    init(
        id: UUID = UUID(),
        traceId: UUID,
        parentSpanId: UUID? = nil,
        name: String,
        startTime: Date = Date(),
        endTime: Date? = nil,
        status: TraceSpanStatus = .running,
        attributes: [String: String] = [:]
    ) {
        self.id = id
        self.traceId = traceId
        self.parentSpanId = parentSpanId
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.status = status
        self.attributes = attributes
    }
}

/// 요청 단위 트레이스 컨텍스트.
struct TraceContext: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let startTime: Date
    var endTime: Date?
    var metadata: [String: String]
    let rootSpanId: UUID

    /// 트레이스가 아직 활성 상태인지 여부.
    var isActive: Bool { endTime == nil }

    /// 트레이스 소요 시간 (밀리초).
    var durationMs: Double {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime) * 1000.0
    }

    init(
        id: UUID = UUID(),
        name: String,
        startTime: Date = Date(),
        endTime: Date? = nil,
        metadata: [String: String] = [:],
        rootSpanId: UUID
    ) {
        self.id = id
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.metadata = metadata
        self.rootSpanId = rootSpanId
    }
}

// MARK: - TraceContextManager

/// 요청 단위 traceId 관리 및 span 생성/종료.
@MainActor
@Observable
final class TraceContextManager: TraceContextProtocol {
    private var traces: [UUID: TraceContext] = [:]
    private var spansByTrace: [UUID: [TraceSpan]] = [:]
    private static let maxTraces = 200

    // MARK: - TraceContextProtocol

    func startTrace(name: String, metadata: [String: String]) -> TraceContext {
        let traceId = UUID()
        let rootSpanId = UUID()
        let rootSpan = TraceSpan(
            id: rootSpanId,
            traceId: traceId,
            name: name,
            attributes: metadata
        )
        let context = TraceContext(
            id: traceId,
            name: name,
            metadata: metadata,
            rootSpanId: rootSpanId
        )
        traces[traceId] = context
        spansByTrace[traceId] = [rootSpan]

        evictOldTraces()

        Log.app.debug("Trace started: \(name) [\(traceId.uuidString.prefix(8))]")
        return context
    }

    func startSpan(
        name: String,
        traceId: UUID,
        parentSpanId: UUID?,
        attributes: [String: String]
    ) -> TraceSpan {
        let span = TraceSpan(
            traceId: traceId,
            parentSpanId: parentSpanId,
            name: name,
            attributes: attributes
        )
        spansByTrace[traceId, default: []].append(span)

        Log.app.debug("Span started: \(name) in trace [\(traceId.uuidString.prefix(8))]")
        return span
    }

    func endSpan(_ span: TraceSpan, status: TraceSpanStatus) {
        guard var spans = spansByTrace[span.traceId],
              let index = spans.firstIndex(where: { $0.id == span.id }) else {
            Log.app.warning("Span not found: \(span.id.uuidString.prefix(8))")
            return
        }

        spans[index].endTime = Date()
        spans[index].status = status
        spansByTrace[span.traceId] = spans

        Log.app.debug("Span ended: \(span.name) [\(status.rawValue)] \(String(format: "%.1fms", spans[index].durationMs))")

        // 루트 span이 종료되면 트레이스도 종료
        if let trace = traces[span.traceId], span.id == trace.rootSpanId {
            var updatedTrace = trace
            updatedTrace.endTime = Date()
            traces[span.traceId] = updatedTrace
            Log.app.info("Trace completed: \(trace.name) [\(trace.id.uuidString.prefix(8))] \(String(format: "%.1fms", updatedTrace.durationMs))")
        }
    }

    func spans(for traceId: UUID) -> [TraceSpan] {
        spansByTrace[traceId] ?? []
    }

    var activeTraces: [TraceContext] {
        traces.values.filter(\.isActive).sorted { $0.startTime > $1.startTime }
    }

    var allTraces: [TraceContext] {
        traces.values.sorted { $0.startTime > $1.startTime }
    }

    // MARK: - Private

    private func evictOldTraces() {
        let completedTraces = traces.values
            .filter { !$0.isActive }
            .sorted { $0.startTime < $1.startTime }

        if traces.count > Self.maxTraces {
            let excess = traces.count - Self.maxTraces
            for trace in completedTraces.prefix(excess) {
                traces.removeValue(forKey: trace.id)
                spansByTrace.removeValue(forKey: trace.id)
            }
        }
    }
}
