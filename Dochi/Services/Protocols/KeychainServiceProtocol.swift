import Foundation

/// API 키 저장소 프로토콜
protocol KeychainServiceProtocol {
    func save(account: String, value: String)
    func load(account: String) -> String?
    func delete(account: String)
}
