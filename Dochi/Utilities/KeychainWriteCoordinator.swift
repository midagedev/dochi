import Foundation

enum KeychainWriteCoordinator {
    @MainActor
    static func saveRequiredValue(
        _ value: String,
        account: String,
        keychain: KeychainServiceProtocol
    ) -> Result<Void, Error> {
        do {
            try keychain.save(account: account, value: value)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    @MainActor
    static func saveTrimmedToken(
        _ token: String,
        account: String,
        keychain: KeychainServiceProtocol
    ) -> Result<Bool, Error> {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        do {
            if trimmed.isEmpty {
                try keychain.delete(account: account)
                return .success(false)
            }
            try keychain.save(account: account, value: trimmed)
            return .success(true)
        } catch {
            return .failure(error)
        }
    }
}
