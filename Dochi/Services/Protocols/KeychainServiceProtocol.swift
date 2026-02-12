import Foundation

@MainActor
protocol KeychainServiceProtocol {
    func save(account: String, value: String) throws
    func load(account: String) -> String?
    func delete(account: String) throws
}
