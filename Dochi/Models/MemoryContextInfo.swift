import Foundation

/// UX-8: 어시스턴트 메시지에 첨부되는 메모리 참조 정보
struct MemoryContextInfo: Codable, Sendable, Equatable {
    let systemPromptLength: Int
    let agentPersonaLength: Int
    let workspaceMemoryLength: Int
    let agentMemoryLength: Int
    let personalMemoryLength: Int

    var totalLength: Int {
        systemPromptLength + agentPersonaLength + workspaceMemoryLength + agentMemoryLength + personalMemoryLength
    }

    /// 대략적인 토큰 수 추정 (한국어 기준 ~2자/토큰)
    var estimatedTokens: Int {
        totalLength / 2
    }

    var hasAnyMemory: Bool {
        totalLength > 0
    }

    /// 사용된 계층 수
    var activeLayerCount: Int {
        [systemPromptLength, agentPersonaLength, workspaceMemoryLength, agentMemoryLength, personalMemoryLength]
            .filter { $0 > 0 }
            .count
    }

    struct LayerInfo: Identifiable {
        let id: String
        let name: String
        let icon: String
        let charCount: Int

        var isActive: Bool { charCount > 0 }
    }

    var layers: [LayerInfo] {
        [
            LayerInfo(id: "system", name: "시스템 프롬프트", icon: "doc.text", charCount: systemPromptLength),
            LayerInfo(id: "persona", name: "에이전트 페르소나", icon: "person.text.rectangle", charCount: agentPersonaLength),
            LayerInfo(id: "workspace", name: "워크스페이스 메모리", icon: "square.grid.2x2", charCount: workspaceMemoryLength),
            LayerInfo(id: "agent", name: "에이전트 메모리", icon: "brain", charCount: agentMemoryLength),
            LayerInfo(id: "personal", name: "개인 메모리", icon: "person", charCount: personalMemoryLength),
        ]
    }
}
