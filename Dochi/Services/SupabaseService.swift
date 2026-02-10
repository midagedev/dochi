import Foundation
import Supabase
import Auth
import AuthenticationServices
import os

@MainActor
final class SupabaseService: ObservableObject, SupabaseServiceProtocol {
    @Published private(set) var authState: AuthState = .signedOut
    var onAuthStateChanged: ((AuthState) -> Void)?

    /// Supabase 클라이언트 (CloudContextService 등에서 DB 접근용). nil when config is missing.
    let client: SupabaseClient?
    private let keychainService: KeychainServiceProtocol
    private let defaults: UserDefaults

    @Published private(set) var selectedWorkspace: Workspace?

    private enum KeychainKeys {
        static let supabaseURL = "supabase_url"
        static let supabaseAnonKey = "supabase_anon_key"
    }

    private enum DefaultsKeys {
        static let currentWorkspaceId = "cloud.currentWorkspaceId"
    }

    init(keychainService: KeychainServiceProtocol = KeychainService(), defaults: UserDefaults = .standard) {
        self.keychainService = keychainService
        self.defaults = defaults

        let url = keychainService.load(account: KeychainKeys.supabaseURL)
            ?? SupabaseService.bundledURL()
        let anonKey = keychainService.load(account: KeychainKeys.supabaseAnonKey)
            ?? SupabaseService.bundledAnonKey()

        guard let supabaseURL = URL(string: url ?? ""),
              let key = anonKey, !key.isEmpty else {
            Log.cloud.warning("Supabase 설정이 없습니다 — 클라우드 기능 비활성")
            self.client = nil
            return
        }

        // Use keychain with proper access control to avoid password prompts
        let sessionStorage = KeychainSessionStorage()
        self.client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: key,
            options: .init(
                auth: .init(storage: sessionStorage)
            )
        )
        Log.cloud.info("Supabase 클라이언트 초기화 완료")
    }

    /// Reads URL from SupabaseConfig.plist (bundled, .gitignored)
    private static func bundledURL() -> String? {
        guard let path = Bundle.main.path(forResource: "SupabaseConfig", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) else { return nil }
        return dict["SUPABASE_URL"] as? String
    }

    /// Reads anon key from SupabaseConfig.plist (bundled, .gitignored)
    private static func bundledAnonKey() -> String? {
        guard let path = Bundle.main.path(forResource: "SupabaseConfig", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) else { return nil }
        return dict["SUPABASE_ANON_KEY"] as? String
    }

    // MARK: - Configuration

    func configure(url: String, anonKey: String) {
        keychainService.save(account: KeychainKeys.supabaseURL, value: url)
        keychainService.save(account: KeychainKeys.supabaseAnonKey, value: anonKey)
        Log.cloud.info("Supabase 설정 저장 완료 — 앱 재시작 필요")
    }

    var isConfigured: Bool {
        client != nil
    }

    // MARK: - Auth

    func restoreSession() async {
        guard let client else { return }
        do {
            let session = try await client.auth.session
            let user = session.user
            let email = user.email
            authState = .signedIn(userId: user.id, email: email)
            onAuthStateChanged?(authState)
            Log.cloud.info("세션 복원 성공: \(email ?? "이메일 없음", privacy: .public)")
            await restoreCurrentWorkspace()
        } catch {
            authState = .signedOut
            onAuthStateChanged?(authState)
            Log.cloud.debug("세션 복원 없음: \(error, privacy: .public)")
        }
    }

    func signInWithApple() async throws {
        guard let client else { throw SupabaseError.configurationMissing }
        let helper = AppleSignInHelper()
        let credential = try await helper.performSignIn()

        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            throw SupabaseError.appleSignInFailed
        }

        let session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken)
        )
        let user = session.user
        authState = .signedIn(userId: user.id, email: user.email)
        onAuthStateChanged?(authState)
        Log.cloud.info("Apple 로그인 성공: \(user.email ?? "이메일 없음", privacy: .public)")
    }

    func signInWithEmail(email: String, password: String) async throws {
        guard let client else { throw SupabaseError.configurationMissing }
        let session = try await client.auth.signIn(email: email, password: password)
        let user = session.user
        authState = .signedIn(userId: user.id, email: user.email)
        onAuthStateChanged?(authState)
        Log.cloud.info("이메일 로그인 성공: \(email, privacy: .public)")
    }

    func signUpWithEmail(email: String, password: String) async throws {
        guard let client else { throw SupabaseError.configurationMissing }
        let result = try await client.auth.signUp(email: email, password: password)
        if let session = result.session {
            let user = session.user
            authState = .signedIn(userId: user.id, email: user.email)
            onAuthStateChanged?(authState)
            Log.cloud.info("이메일 가입 성공: \(email, privacy: .public)")
        } else {
            Log.cloud.info("이메일 가입 — 확인 메일 발송됨: \(email, privacy: .public)")
        }
    }

    func signOut() async throws {
        guard let client else { throw SupabaseError.configurationMissing }
        try await client.auth.signOut()
        authState = .signedOut
        selectedWorkspace = nil
        defaults.removeObject(forKey: DefaultsKeys.currentWorkspaceId)
        onAuthStateChanged?(authState)
        Log.cloud.info("로그아웃 완료")
    }

    // MARK: - Workspaces

    func createWorkspace(name: String) async throws -> Workspace {
        guard let client else { throw SupabaseError.configurationMissing }
        guard case .signedIn(let userId, _) = authState else {
            throw SupabaseError.notAuthenticated
        }

        let inviteCode = generateInviteCode()
        let now = Date()

        struct InsertWorkspace: Encodable {
            let name: String
            let invite_code: String
            let owner_id: UUID
            let created_at: Date
        }

        let workspace: Workspace = try await client.from("workspaces")
            .insert(InsertWorkspace(name: name, invite_code: inviteCode, owner_id: userId, created_at: now))
            .select()
            .single()
            .execute()
            .value

        // Auto-add creator as owner member
        struct InsertMember: Encodable {
            let workspace_id: UUID
            let user_id: UUID
            let role: String
        }

        try await client.from("workspace_members")
            .insert(InsertMember(workspace_id: workspace.id, user_id: userId, role: "owner"))
            .execute()

        setCurrentWorkspace(workspace)
        Log.cloud.info("워크스페이스 생성: \(name, privacy: .public)")
        return workspace
    }

    func joinWorkspace(inviteCode: String) async throws -> Workspace {
        guard let client else { throw SupabaseError.configurationMissing }
        guard case .signedIn = authState else {
            throw SupabaseError.notAuthenticated
        }

        // Use SECURITY DEFINER function to join without exposing workspace data via RLS
        let wsIdString: String = try await client.rpc(
            "join_workspace_by_invite",
            params: ["code": inviteCode]
        ).execute().value

        guard let wsId = UUID(uuidString: wsIdString) else {
            throw SupabaseError.invalidInviteCode
        }

        let workspace: Workspace = try await client.from("workspaces")
            .select()
            .eq("id", value: wsId)
            .single()
            .execute()
            .value

        setCurrentWorkspace(workspace)
        Log.cloud.info("워크스페이스 참가: \(workspace.name, privacy: .public)")
        return workspace
    }

    func leaveWorkspace(id: UUID) async throws {
        guard let client else { throw SupabaseError.configurationMissing }
        guard case .signedIn(let userId, _) = authState else {
            throw SupabaseError.notAuthenticated
        }

        try await client.from("workspace_members")
            .delete()
            .eq("workspace_id", value: id)
            .eq("user_id", value: userId)
            .execute()

        if selectedWorkspace?.id == id {
            setCurrentWorkspace(nil)
        }

        Log.cloud.info("워크스페이스 탈퇴: \(id, privacy: .public)")
    }

    func listWorkspaces() async throws -> [Workspace] {
        guard let client else { throw SupabaseError.configurationMissing }
        guard case .signedIn(let userId, _) = authState else {
            throw SupabaseError.notAuthenticated
        }

        // Get workspace IDs the user belongs to
        struct MemberRow: Decodable {
            let workspace_id: UUID
        }

        let memberRows: [MemberRow] = try await client.from("workspace_members")
            .select("workspace_id")
            .eq("user_id", value: userId)
            .execute()
            .value

        if memberRows.isEmpty { return [] }

        let workspaceIds = memberRows.map(\.workspace_id)

        let workspaces: [Workspace] = try await client.from("workspaces")
            .select()
            .in("id", values: workspaceIds)
            .execute()
            .value

        return workspaces
    }

    func currentWorkspace() -> Workspace? {
        selectedWorkspace
    }

    func setCurrentWorkspace(_ workspace: Workspace?) {
        selectedWorkspace = workspace
        if let id = workspace?.id {
            defaults.set(id.uuidString, forKey: DefaultsKeys.currentWorkspaceId)
        } else {
            defaults.removeObject(forKey: DefaultsKeys.currentWorkspaceId)
        }
    }

    func regenerateInviteCode(workspaceId: UUID) async throws -> String {
        guard let client else { throw SupabaseError.configurationMissing }
        let newCode = generateInviteCode()

        struct UpdateCode: Encodable {
            let invite_code: String
        }

        try await client.from("workspaces")
            .update(UpdateCode(invite_code: newCode))
            .eq("id", value: workspaceId)
            .execute()

        if selectedWorkspace?.id == workspaceId {
            selectedWorkspace?.inviteCode = newCode
        }

        Log.cloud.info("초대 코드 재생성: \(workspaceId, privacy: .public)")
        return newCode
    }

    // MARK: - Helpers

    private func generateInviteCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<8).map { _ in chars.randomElement()! })
    }

    private func restoreCurrentWorkspace() async {
        guard let client,
              let idString = defaults.string(forKey: DefaultsKeys.currentWorkspaceId),
              let id = UUID(uuidString: idString) else { return }

        do {
            let workspace: Workspace = try await client.from("workspaces")
                .select()
                .eq("id", value: id)
                .single()
                .execute()
                .value
            selectedWorkspace = workspace
            Log.cloud.info("현재 워크스페이스 복원: \(workspace.name, privacy: .public)")
        } catch {
            Log.cloud.warning("워크스페이스 복원 실패: \(error, privacy: .public)")
            defaults.removeObject(forKey: DefaultsKeys.currentWorkspaceId)
        }
    }

    // MARK: - Telegram Mapping

    /// 현재 로그인 사용자/워크스페이스 기준으로 텔레그램 사용자 매핑을 보장
    /// - Creates a row in `telegram_accounts` if not exists: (user_id, workspace_id, telegram_user_id, username)
    func ensureTelegramMapping(telegramUserId: Int64, username: String?) async {
        guard let client else { return }
        guard case .signedIn(let userId, _) = authState, let wsId = selectedWorkspace?.id else { return }

        struct Row: Codable {
            let user_id: UUID
            let workspace_id: UUID
            let telegram_user_id: Int64
            let username: String?
            let created_at: Date?
            let updated_at: Date?
        }

        do {
            // Exists?
            let existing: [Row] = try await client
                .from("telegram_accounts")
                .select()
                .eq("telegram_user_id", value: Int(telegramUserId))
                .eq("workspace_id", value: wsId)
                .limit(1)
                .execute()
                .value

            if existing.isEmpty {
                struct Insert: Encodable { let user_id: UUID; let workspace_id: UUID; let telegram_user_id: Int64; let username: String? }
                try await client
                    .from("telegram_accounts")
                    .insert(Insert(user_id: userId, workspace_id: wsId, telegram_user_id: telegramUserId, username: username))
                    .execute()
                Log.cloud.info("텔레그램 매핑 추가: tg=\(telegramUserId), ws=\(wsId.uuidString, privacy: .public)")
            } else if existing.first?.username != username, let username {
                struct Update: Encodable { let username: String }
                try await client
                    .from("telegram_accounts")
                    .update(Update(username: username))
                    .eq("telegram_user_id", value: Int(telegramUserId))
                    .eq("workspace_id", value: wsId)
                    .execute()
            }
        } catch {
            Log.cloud.warning("텔레그램 매핑 처리 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 텔레그램 사용자에 매핑된 워크스페이스 조회 (여러 개일 경우 최근 업데이트 우선)
    func resolveWorkspaceForTelegramUser(telegramUserId: Int64) async -> UUID? {
        guard let client else { return nil }
        do {
            struct Row: Decodable { let workspace_id: UUID; let updated_at: Date? }
            let rows: [Row] = try await client
                .from("telegram_accounts")
                .select("workspace_id, updated_at")
                .eq("telegram_user_id", value: Int(telegramUserId))
                .order("updated_at", ascending: false)
                .limit(1)
                .execute()
                .value
            return rows.first?.workspace_id
        } catch {
            Log.cloud.warning("텔레그램 매핑 조회 실패: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Leader Lock (Best-effort)

    /// Acquire a leader lock for a resource within the selected workspace.
    /// Returns true on success or if cloud is not configured; false if held by another.
    func acquireLeaderLock(resource: String, ttlSeconds: Int = 60) async -> Bool {
        guard let client else { return true }
        guard case .signedIn(let userId, _) = authState, let wsId = selectedWorkspace?.id else { return true }
        struct LockRow: Codable { let resource: String; let workspace_id: UUID; let holder_user_id: UUID; let expires_at: Date }
        do {
            // Fetch existing lock
            let existing: [LockRow] = try await client
                .from("leader_locks")
                .select()
                .eq("resource", value: resource)
                .eq("workspace_id", value: wsId)
                .limit(1)
                .execute()
                .value
            let now = Date()
            let exp = Date(timeIntervalSinceNow: TimeInterval(ttlSeconds))
            if let row = existing.first {
                if row.expires_at <= now || row.holder_user_id == userId {
                    struct Update: Encodable { let holder_user_id: UUID; let expires_at: Date }
                    try await client
                        .from("leader_locks")
                        .update(Update(holder_user_id: userId, expires_at: exp))
                        .eq("resource", value: resource)
                        .eq("workspace_id", value: wsId)
                        .execute()
                    return true
                } else {
                    return false
                }
            } else {
                struct Insert: Encodable { let resource: String; let workspace_id: UUID; let holder_user_id: UUID; let expires_at: Date }
                try await client
                    .from("leader_locks")
                    .insert(Insert(resource: resource, workspace_id: wsId, holder_user_id: userId, expires_at: exp))
                    .execute()
                return true
            }
        } catch {
            Log.cloud.warning("리더 락 획득 실패(무시): \(error.localizedDescription, privacy: .public)")
            return true // fail-open
        }
    }

    /// Refresh a leader lock (if we hold it). Best-effort; errors ignored.
    func refreshLeaderLock(resource: String, ttlSeconds: Int = 60) async {
        guard let client else { return }
        guard case .signedIn(let userId, _) = authState, let wsId = selectedWorkspace?.id else { return }
        do {
            let exp = Date(timeIntervalSinceNow: TimeInterval(ttlSeconds))
            struct Update: Encodable { let holder_user_id: UUID; let expires_at: Date }
            try await client
                .from("leader_locks")
                .update(Update(holder_user_id: userId, expires_at: exp))
                .eq("resource", value: resource)
                .eq("workspace_id", value: wsId)
                .eq("holder_user_id", value: userId)
                .execute()
        } catch {
            Log.cloud.warning("리더 락 갱신 실패(무시): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Release a leader lock if held by current user. Best-effort.
    func releaseLeaderLock(resource: String) async {
        guard let client else { return }
        guard case .signedIn(let userId, _) = authState, let wsId = selectedWorkspace?.id else { return }
        do {
            try await client
                .from("leader_locks")
                .delete()
                .eq("resource", value: resource)
                .eq("workspace_id", value: wsId)
                .eq("holder_user_id", value: userId)
                .execute()
        } catch {
            Log.cloud.warning("리더 락 해제 실패(무시): \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Errors

enum SupabaseError: LocalizedError {
    case notAuthenticated
    case appleSignInFailed
    case invalidInviteCode
    case configurationMissing

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "로그인이 필요합니다"
        case .appleSignInFailed: "Apple 로그인에 실패했습니다"
        case .invalidInviteCode: "유효하지 않은 초대 코드입니다"
        case .configurationMissing: "Supabase 설정이 필요합니다"
        }
    }
}

// MARK: - Apple Sign In Helper

final class AppleSignInHelper: NSObject, ASAuthorizationControllerDelegate {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    func performSignIn() async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.email, .fullName]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: SupabaseError.appleSignInFailed)
            return
        }
        continuation?.resume(returning: credential)
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
    }
}
