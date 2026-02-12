import Foundation

enum AuthState: Sendable {
    case signedOut
    case signingIn
    case signedIn(userId: UUID, email: String?)

    var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }

    var userId: UUID? {
        if case .signedIn(let id, _) = self { return id }
        return nil
    }
}
