import Foundation
@testable import Dochi

@MainActor
final class MockSupabaseService: SupabaseServiceProtocol {
    var authState: AuthState = .signedOut
    var onAuthStateChanged: ((AuthState) -> Void)?
    var selectedWorkspace: Workspace? { currentWorkspaceValue }

    var isConfigured: Bool = true
    var configuredURL: String?
    var configuredAnonKey: String?

    var workspaces: [Workspace] = []
    var currentWorkspaceValue: Workspace?

    // Tracking
    var signInWithAppleCalled = false
    var signOutCalled = false
    var createWorkspaceName: String?

    func configure(url: String, anonKey: String) {
        configuredURL = url
        configuredAnonKey = anonKey
    }

    func signInWithApple() async throws {
        signInWithAppleCalled = true
        let userId = UUID()
        authState = .signedIn(userId: userId, email: "test@example.com")
        onAuthStateChanged?(authState)
    }

    func signInWithEmail(email: String, password: String) async throws {
        let userId = UUID()
        authState = .signedIn(userId: userId, email: email)
        onAuthStateChanged?(authState)
    }

    func signUpWithEmail(email: String, password: String) async throws {
        let userId = UUID()
        authState = .signedIn(userId: userId, email: email)
        onAuthStateChanged?(authState)
    }

    func signOut() async throws {
        signOutCalled = true
        authState = .signedOut
        currentWorkspaceValue = nil
        onAuthStateChanged?(authState)
    }

    func restoreSession() async {
        // No-op in mock
    }

    func createWorkspace(name: String) async throws -> Workspace {
        createWorkspaceName = name
        let ws = Workspace(
            id: UUID(),
            name: name,
            inviteCode: "TEST1234",
            ownerId: UUID(),
            createdAt: Date()
        )
        workspaces.append(ws)
        currentWorkspaceValue = ws
        return ws
    }

    func joinWorkspace(inviteCode: String) async throws -> Workspace {
        guard let ws = workspaces.first(where: { $0.inviteCode == inviteCode }) else {
            throw SupabaseError.invalidInviteCode
        }
        currentWorkspaceValue = ws
        return ws
    }

    func leaveWorkspace(id: UUID) async throws {
        workspaces.removeAll { $0.id == id }
        if currentWorkspaceValue?.id == id {
            currentWorkspaceValue = nil
        }
    }

    func listWorkspaces() async throws -> [Workspace] {
        workspaces
    }

    func currentWorkspace() -> Workspace? {
        currentWorkspaceValue
    }

    func setCurrentWorkspace(_ workspace: Workspace?) {
        currentWorkspaceValue = workspace
    }

    func regenerateInviteCode(workspaceId: UUID) async throws -> String {
        "NEWCODE1"
    }
}
