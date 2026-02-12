# Service Interfaces

구현 참고용 서비스 인터페이스 정의. Phase 태그로 MVP 범위 명시.

- **P1**: Phase 1 (텍스트 MVP)
- **P2**: Phase 2 (음성)
- **P3**: Phase 3 (도구 & 권한)
- **P4**: Phase 4 (원격 & 동기화)

---

## ContextServiceProtocol (P1)

파일 기반 컨텍스트 관리. 모든 경로는 `~/Library/Application Support/Dochi/` 기준.

### P1 필수
- `loadBaseSystemPrompt() -> String?`
- `saveBaseSystemPrompt(_: String)`
- `loadProfiles() -> [UserProfile]`
- `saveProfiles(_: [UserProfile])`
- `loadUserMemory(userId: String) -> String?`
- `saveUserMemory(userId: String, content: String)`
- `appendUserMemory(userId: String, content: String)`
- `loadWorkspaceMemory(workspaceId: UUID) -> String?`
- `saveWorkspaceMemory(workspaceId: UUID, content: String)`
- `appendWorkspaceMemory(workspaceId: UUID, content: String)`
- `loadAgentPersona(workspaceId: UUID, agentName: String) -> String?`
- `saveAgentPersona(workspaceId: UUID, agentName: String, content: String)`
- `loadAgentMemory(workspaceId: UUID, agentName: String) -> String?`
- `saveAgentMemory(workspaceId: UUID, agentName: String, content: String)`
- `appendAgentMemory(workspaceId: UUID, agentName: String, content: String)`
- `loadAgentConfig(workspaceId: UUID, agentName: String) -> AgentConfig?`
- `saveAgentConfig(workspaceId: UUID, config: AgentConfig)`
- `listAgents(workspaceId: UUID) -> [String]`
- `createAgent(workspaceId: UUID, name: String, wakeWord: String?, description: String?)`

### P1 마이그레이션 (1회성)
- `migrateIfNeeded()` — 레거시 파일 감지 → 새 구조로 이전 + `.bak` 보존

---

## ConversationServiceProtocol (P1)

- `list() -> [Conversation]`
- `load(id: UUID) -> Conversation?`
- `save(conversation: Conversation)`
- `delete(id: UUID)`

---

## KeychainServiceProtocol (P1)

- `save(account: String, value: String) throws`
- `load(account: String) -> String?`
- `delete(account: String) throws`

---

## SoundServiceProtocol (P2)

- `playInputComplete()`
- `playWakeWordDetected()`

---

## MCPServiceProtocol (P3)

### 서버 관리
- `addServer(config: MCPServerConfig)`
- `removeServer(id: UUID)`
- `connect(serverId: UUID) async throws`
- `disconnect(serverId: UUID)`
- `disconnectAll()`

### 조회
- `listServers() -> [MCPServerConfig]`
- `getServer(id: UUID) -> MCPServerConfig?`

### 도구
- `listTools() -> [MCPToolInfo]`
- `callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult`

---

## SupabaseServiceProtocol (P4)

### 설정 & 인증
- `isConfigured: Bool`
- `configure(url: URL, anonKey: String)`
- `authState: AuthState` — signedOut / signingIn / signedIn(userId, email)
- `signInWithApple() async throws`
- `signInWithEmail(email: String, password: String) async throws`
- `signUpWithEmail(email: String, password: String) async throws`
- `signOut() async throws`
- `restoreSession() async`

### 워크스페이스
- `createWorkspace(name: String) async throws -> Workspace`
- `joinWorkspace(inviteCode: String) async throws -> Workspace`
- `leaveWorkspace(id: UUID) async throws`
- `listWorkspaces() async throws -> [Workspace]`
- `currentWorkspace() -> Workspace?`
- `setCurrentWorkspace(_: Workspace?)`
- `regenerateInviteCode(workspaceId: UUID) async throws -> String`

### 동기화
- `syncContext() async throws` — 컨텍스트 push/pull
- `syncConversations() async throws` — 대화 push/pull

---

## DeviceServiceProtocol (P4)

- `currentDevice: Device`
- `registerDevice() async throws`
- `startHeartbeat()`
- `stopHeartbeat()`
- `removeDevice(id: UUID) async throws`
- `fetchWorkspaceDevices() async throws -> [Device]`
- `updateDeviceName(_: String) async throws`
