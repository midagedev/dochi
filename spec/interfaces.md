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

---

## TTSServiceProtocol (P2)

TTS 서비스 공통 인터페이스. 여러 프로바이더가 구현.

- `engineState: TTSEngineState` — unloaded / loading / ready / error(String)
- `isSpeaking: Bool`
- `loadEngine() async throws`
- `unloadEngine()`
- `enqueueSentence(_: String)`
- `stopAndClear()`
- `onComplete: (() -> Void)?`

### 구현체

| 서비스 | 설명 |
|--------|------|
| `TTSRouter` | 설정에 따라 프로바이더 전환 (System / GoogleCloud) |
| `SystemTTSService` | Apple AVSpeechSynthesizer 기반. 폴백 역할 |
| `GoogleCloudTTSService` | Google Cloud TTS API. Wavenet/Neural2/Standard/Chirp3-HD 음성 |
| `SupertonicService` | ONNX 기반 로컬 TTS (현재 추론 파이프라인 TODO) |

---

## SpeechServiceProtocol (P2)

- `isAuthorized: Bool`
- `isListening: Bool`
- `requestAuthorization() async -> Bool`
- `startListening(silenceTimeout: TimeInterval, onPartialResult: ((String) -> Void)?, onFinalResult: ((String) -> Void)?)`
- `stopListening()`
- `startContinuousRecognition(wakeWord: String, threshold: Int?, onWakeWordDetected: (() -> Void)?)`
- `stopContinuousRecognition()`

---

## LLMServiceProtocol (P1)

- `send(messages:systemPrompt:model:provider:apiKey:tools:onPartial:) async throws -> LLMResponse`
- `cancel()`
- `lastMetrics: ExchangeMetrics?`

---

## TelegramServiceProtocol (P4)

- `isPolling: Bool`
- `startPolling(token: String) async throws`
- `stopPolling()`
- `sendMessage(chatId: Int, text: String) async throws`
- `editMessage(chatId: Int, messageId: Int, text: String) async throws`
- `getMe() async throws -> String`
- `onMessage: ((TelegramUpdate) -> Void)?`

---

## BuiltInToolServiceProtocol (P1/P3)

- `confirmationHandler: ToolConfirmationHandler?`
- `availableToolSchemas(for permissions: [String]) -> [[String: Any]]`
- `execute(name: String, arguments: [String: Any]) async -> ToolResult`
- `enableTools(names: [String])`
- `enableToolsTTL(minutes: Int)`
- `resetRegistry()`
- `allToolInfos: [ToolInfo]` — UI용 도구 정보 목록

---

## HeartbeatService (UI)

프로액티브 에이전트: 주기적으로 캘린더/칸반/미리알림 점검.

- `restart()` — 설정에 따라 타이머 시작/재시작
- `stop()`
- `setProactiveHandler(_: (String) -> Void)`

---

## MetricsCollector (P5)

LLM 교환 메트릭 수집 (링버퍼 100건).

- `record(_: ExchangeMetrics)`
- `recentMetrics: [ExchangeMetrics]`
- `sessionSummary() -> String`

---

## AvatarManager (UI)

VRM 3D 아바타 관리. macOS 15+ (RealityKit).

- `loadVRM() async throws -> Entity`
- `setExpression(_: AvatarExpression)`
- `setLipSync(intensity: Float)`
- `startIdleAnimation()`
- `updateHeadRotation(yaw:pitch:)`
