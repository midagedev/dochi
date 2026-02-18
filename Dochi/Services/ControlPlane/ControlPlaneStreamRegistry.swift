import Foundation

struct ControlPlaneStreamEventRecord: Sendable {
    let sequence: Int
    let type: String
    let timestamp: String
    let correlationId: String
    let text: String?
    let toolName: String?
    let category: String?
    let level: String?
    let message: String?
}

struct ControlPlaneChatReadSnapshot: Sendable {
    let streamId: String
    let correlationId: String
    let done: Bool
    let errorMessage: String?
    let events: [ControlPlaneStreamEventRecord]
}

struct ControlPlaneLogTailState: Sendable {
    let tailId: String
    let correlationId: String
    let category: String?
    let level: String?
    let contains: String?
    let cursorDate: Date
}

struct ControlPlaneLogTailReadSnapshot: Sendable {
    let tailId: String
    let correlationId: String
    let events: [ControlPlaneStreamEventRecord]
}

actor ControlPlaneStreamRegistry {
    private struct ChatSession: Sendable {
        let streamId: String
        let correlationId: String
        var events: [ControlPlaneStreamEventRecord] = []
        var cursor: Int = 0
        var nextSequence: Int = 1
        var done: Bool = false
        var errorMessage: String?
        var task: Task<Void, Never>?
    }

    private struct LogTailSession: Sendable {
        let tailId: String
        let correlationId: String
        let category: String?
        let level: String?
        let contains: String?
        var cursorDate: Date
        var nextSequence: Int = 1
    }

    private var chatSessions: [String: ChatSession] = [:]
    private var logTailSessions: [String: LogTailSession] = [:]

    func createChatSession(correlationId: String) -> String {
        let streamId = UUID().uuidString
        chatSessions[streamId] = ChatSession(streamId: streamId, correlationId: correlationId)
        return streamId
    }

    func attachChatTask(streamId: String, task: Task<Void, Never>) {
        guard var session = chatSessions[streamId] else { return }
        session.task = task
        chatSessions[streamId] = session
    }

    func appendChatEvent(
        streamId: String,
        type: String,
        timestamp: String,
        text: String? = nil,
        toolName: String? = nil
    ) {
        guard var session = chatSessions[streamId] else { return }
        let event = ControlPlaneStreamEventRecord(
            sequence: session.nextSequence,
            type: type,
            timestamp: timestamp,
            correlationId: session.correlationId,
            text: text,
            toolName: toolName,
            category: nil,
            level: nil,
            message: nil
        )
        session.nextSequence += 1
        session.events.append(event)
        chatSessions[streamId] = session
    }

    func finishChat(streamId: String, errorMessage: String?) {
        guard var session = chatSessions[streamId] else { return }
        session.done = true
        session.errorMessage = errorMessage
        chatSessions[streamId] = session
    }

    func readChat(streamId: String, limit: Int) -> ControlPlaneChatReadSnapshot? {
        guard var session = chatSessions[streamId] else { return nil }

        let safeLimit = max(1, min(500, limit))
        let start = session.cursor
        let end = min(session.events.count, start + safeLimit)
        let chunk: [ControlPlaneStreamEventRecord]

        if start < end {
            chunk = Array(session.events[start..<end])
            session.cursor = end
            chatSessions[streamId] = session
        } else {
            chunk = []
        }

        let isDrained = session.cursor >= session.events.count
        return ControlPlaneChatReadSnapshot(
            streamId: streamId,
            correlationId: session.correlationId,
            done: session.done && isDrained,
            errorMessage: session.errorMessage,
            events: chunk
        )
    }

    func closeChat(streamId: String) -> Bool {
        guard let session = chatSessions.removeValue(forKey: streamId) else { return false }
        session.task?.cancel()
        return true
    }

    func createLogTailSession(
        correlationId: String,
        category: String?,
        level: String?,
        contains: String?,
        startAt: Date
    ) -> String {
        let tailId = UUID().uuidString
        logTailSessions[tailId] = LogTailSession(
            tailId: tailId,
            correlationId: correlationId,
            category: category,
            level: level,
            contains: contains,
            cursorDate: startAt
        )
        return tailId
    }

    func logTailState(tailId: String) -> ControlPlaneLogTailState? {
        guard let session = logTailSessions[tailId] else { return nil }
        return ControlPlaneLogTailState(
            tailId: session.tailId,
            correlationId: session.correlationId,
            category: session.category,
            level: session.level,
            contains: session.contains,
            cursorDate: session.cursorDate
        )
    }

    func consumeLogTailEntries(
        tailId: String,
        entries: [DochiLogLine],
        limit: Int
    ) -> ControlPlaneLogTailReadSnapshot? {
        guard var session = logTailSessions[tailId] else { return nil }

        let safeLimit = max(1, min(500, limit))
        let sorted = entries.sorted { $0.date < $1.date }
        let filtered = sorted.filter { $0.date > session.cursorDate }
        let bounded = filtered.count > safeLimit ? Array(filtered.suffix(safeLimit)) : filtered

        var events: [ControlPlaneStreamEventRecord] = []
        events.reserveCapacity(bounded.count)

        for entry in bounded {
            let event = ControlPlaneStreamEventRecord(
                sequence: session.nextSequence,
                type: "log",
                timestamp: isoTimestamp(entry.date),
                correlationId: session.correlationId,
                text: nil,
                toolName: nil,
                category: entry.category,
                level: entry.level,
                message: entry.message
            )
            session.nextSequence += 1
            events.append(event)
        }

        if let last = bounded.last?.date {
            session.cursorDate = last
        }
        logTailSessions[tailId] = session

        return ControlPlaneLogTailReadSnapshot(
            tailId: tailId,
            correlationId: session.correlationId,
            events: events
        )
    }

    func closeLogTail(tailId: String) -> Bool {
        logTailSessions.removeValue(forKey: tailId) != nil
    }

    private func isoTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
