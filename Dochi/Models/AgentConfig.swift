import Foundation

/// 에이전트 설정
/// agents/{name}/config.json 으로 저장
struct AgentConfig: Codable, Equatable {
    var name: String
    var wakeWord: String
    var description: String
}
