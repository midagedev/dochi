# Service Interfaces (Implementation Appendix)

Note: This is a non‑normative, implementation‑oriented appendix to help developers map the high‑level specs to modules. Names here are illustrative and are not part of the public spec contract.

## ContextServiceProtocol
- System: `loadSystem()`, `saveSystem(_:)`, `systemPath`
- Memory (legacy): `loadMemory()`, `saveMemory(_:)`, `appendMemory(_:)`, `memoryPath`, `memorySize`
- Family: `loadFamilyMemory()`, `saveFamilyMemory(_:)`, `appendFamilyMemory(_:)`
- User: `loadUserMemory(userId)`, `saveUserMemory(userId, content)`, `appendUserMemory(userId, content)`
- Profiles: `loadProfiles()`, `saveProfiles(_:)`
- Base System Prompt: `loadBaseSystemPrompt()`, `saveBaseSystemPrompt(_:)`, `baseSystemPromptPath`
- Workspace: `listWorkspaces()`, `loadWorkspaceConfig(id)`, `saveWorkspaceConfig(_:)`
- Workspace Memory: `loadWorkspaceMemory(workspaceId)`, `saveWorkspaceMemory(workspaceId, content)`, `appendWorkspaceMemory(workspaceId, content)`
- Agent (workspace‑scoped):
  - Persona: `loadAgentPersona(workspaceId, agentName)`, `saveAgentPersona(workspaceId, agentName, content)`
  - Memory: `loadAgentMemory(workspaceId, agentName)`, `saveAgentMemory(workspaceId, agentName, content)`, `appendAgentMemory(workspaceId, agentName, content)`
  - Config: `loadAgentConfig(workspaceId, agentName) -> AgentConfig?`, `saveAgentConfig(workspaceId, config)`
  - Management: `listAgents(workspaceId)`, `createAgent(workspaceId, name, wakeWord, description)`
- Migration helpers + deprecated non‑workspace APIs retained for compatibility

## ConversationServiceProtocol
- CRUD: `list()`, `load(id)`, `save(conversation)`, `delete(id)`

## KeychainServiceProtocol
- Secrets: `save(account, value)`, `load(account)`, `delete(account)`

## MCPServiceProtocol
- Server lifecycle: `addServer(config)`, `removeServer(id)`, `connect(serverId)`, `disconnect(serverId)`, `disconnectAll()`
- Discovery: `listServers()`, `getServer(id)`
- Tools: `listTools() -> [MCPToolInfo]`, `callTool(name, arguments) -> MCPToolResult`

## DeviceServiceProtocol
- Current device, workspace peers: `currentDevice`, `workspaceDevices`
- Lifecycle: `registerDevice()`, `startHeartbeat()`, `stopHeartbeat()`, `removeDevice(id)`
- Queries: `fetchWorkspaceDevices()`, `updateDeviceName(_:)`

## SoundServiceProtocol
- UI SFX: `playInputComplete()`, `playWakeWordDetected()`

## SupabaseServiceProtocol
- Config: `isConfigured`, `configure(url, anonKey)`
- Auth: `authState`, `onAuthStateChanged`, `signInWithApple()`, `signInWithEmail`, `signUpWithEmail`, `signOut()`, `restoreSession()`
- Workspaces: `createWorkspace`, `joinWorkspace`, `leaveWorkspace`, `listWorkspaces`, `currentWorkspace()`, `setCurrentWorkspace(_:)`, `regenerateInviteCode(workspaceId)`
