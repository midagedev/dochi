import Foundation

enum AuthState: Equatable {
    case signedOut
    case signedIn(userId: UUID, email: String?)
}

@MainActor
protocol SupabaseServiceProtocol: AnyObject {
    // MARK: - Configuration

    var isConfigured: Bool { get }
    func configure(url: String, anonKey: String)

    // MARK: - Auth

    var authState: AuthState { get }
    var onAuthStateChanged: ((AuthState) -> Void)? { get set }
    var selectedWorkspace: Workspace? { get }

    func signInWithApple() async throws
    func signInWithEmail(email: String, password: String) async throws
    func signUpWithEmail(email: String, password: String) async throws
    func signOut() async throws
    func restoreSession() async

    // MARK: - Workspaces

    func createWorkspace(name: String) async throws -> Workspace
    func joinWorkspace(inviteCode: String) async throws -> Workspace
    func leaveWorkspace(id: UUID) async throws
    func listWorkspaces() async throws -> [Workspace]
    func currentWorkspace() -> Workspace?
    func setCurrentWorkspace(_ workspace: Workspace?)
    func regenerateInviteCode(workspaceId: UUID) async throws -> String
}
