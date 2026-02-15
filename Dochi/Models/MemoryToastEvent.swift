import Foundation

/// UX-8: 메모리 저장/업데이트 시 표시할 토스트 이벤트
struct MemoryToastEvent: Identifiable, Sendable {
    let id: UUID
    let scope: Scope
    let action: Action
    let contentPreview: String
    let timestamp: Date

    enum Scope: String, Sendable {
        case workspace = "워크스페이스"
        case personal = "개인"
        case agent = "에이전트"
    }

    enum Action: String, Sendable {
        case saved = "저장됨"
        case updated = "업데이트됨"
    }

    init(id: UUID = UUID(), scope: Scope, action: Action, contentPreview: String, timestamp: Date = Date()) {
        self.id = id
        self.scope = scope
        self.action = action
        self.contentPreview = String(contentPreview.prefix(80))
        self.timestamp = timestamp
    }

    var displayMessage: String {
        "\(scope.rawValue) 메모리에 \(action.rawValue)"
    }
}
