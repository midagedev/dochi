import Foundation

@MainActor
protocol SupabaseServiceProtocol {
    // Config
    var isConfigured: Bool { get }
    func configure(url: URL, anonKey: String)

    // Auth
    var authState: AuthState { get }
    func signInWithApple() async throws
    func signInWithEmail(email: String, password: String) async throws
    func signUpWithEmail(email: String, password: String) async throws
    func signOut() async throws
    func restoreSession() async

    // Workspaces
    func createWorkspace(name: String) async throws -> Workspace
    func joinWorkspace(inviteCode: String) async throws -> Workspace
    func leaveWorkspace(id: UUID) async throws
    func listWorkspaces() async throws -> [Workspace]
    func regenerateInviteCode(workspaceId: UUID) async throws -> String

    // Sync
    func syncContext() async throws
    func syncConversations() async throws

    // Leader Lock
    func acquireLock(resource: String, workspaceId: UUID) async throws -> Bool
    func releaseLock(resource: String, workspaceId: UUID) async throws
    func refreshLock(resource: String, workspaceId: UUID) async throws
}
