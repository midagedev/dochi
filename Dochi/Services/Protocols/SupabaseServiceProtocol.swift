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

    // Devices
    func registerDevice(name: String, workspaceIds: [UUID]) async throws -> Device
    func updateDeviceHeartbeat(deviceId: UUID) async throws
    func updateDeviceWorkspaces(deviceId: UUID, workspaceIds: [UUID]) async throws
    func listDevices() async throws -> [Device]
    func removeDevice(id: UUID) async throws

    // Sync (legacy)
    func syncContext() async throws
    func syncConversations() async throws

    // Sync (G-3 enhanced)
    func pushEntities(type: SyncEntityType, payload: Data) async throws
    func pullEntities(type: SyncEntityType, since: Date?) async throws -> Data?
    func fetchRemoteTimestamps(type: SyncEntityType) async throws -> [String: Date]

    // Leader Lock
    func acquireLock(resource: String, workspaceId: UUID) async throws -> Bool
    func releaseLock(resource: String, workspaceId: UUID) async throws
    func refreshLock(resource: String, workspaceId: UUID) async throws
}
