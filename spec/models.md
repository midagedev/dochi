# Data Models

This document captures the core data models used by Dochi for a clean rewrite.

## Settings (UserDefaults + Keychain)
- UserDefaults keys (`AppSettings.Keys`):
  - `settings.wakeWordEnabled: Bool`
  - `settings.wakeWord: String`
  - `settings.llmProvider: String (LLMProvider)`
  - `settings.llmModel: String`
  - `settings.autoModelRoutingEnabled: Bool`
  - `settings.supertonicVoice: String (SupertonicVoice)`
  - `settings.ttsSpeed: Float`
  - `settings.ttsDiffusionSteps: Int`
  - `settings.chatFontSize: Double`
  - `settings.uiDensity: String (UIDensity)`
  - `settings.interactionMode: String (InteractionMode)`
  - `settings.hasSeenPermissionInfo: Bool`
  - `settings.sttSilenceTimeout: Double`
  - `settings.contextAutoCompress: Bool`
  - `settings.contextMaxSize: Int`
  - `settings.activeAgentName: String`
  - `settings.telegramEnabled: Bool`
  - `settings.telegramStreamReplies: Bool`
  - `settings.mcpServers: [MCPServerConfig] (JSON)`
  - `settings.currentWorkspaceId: UUID?`
  - `settings.toolsRegistryAutoReset: Bool`
  - `settings.claudeUIEnabled: Bool`
  - `settings.claudeUIBaseURL: String`
  - `settings.claudeUISandboxEnabled: Bool`
- Keychain accounts:
  - `openai`, `anthropic`, `zai` (LLM API keys)
  - `tavily`, `falai` (3rd‑party tools)
  - `telegram_bot_token`
  - `claude_ui_token`

## Enums
- `LLMProvider`: `openai | anthropic | zai`
  - `models`: provider‑specific model list
  - `apiURL`: base URL per provider
- `SupertonicVoice`: `F1..F5`, `M1..M5`
- `InteractionMode`: `voiceAndText | textOnly`

## AgentConfig (agents/{name}/config.json)
```json
{ "name": "코디", "wakeWord": "코디야", "description": "개발 에이전트", "defaultModel": "gpt-4o" }
```

## UserProfile (profiles.json)
- Fields: `id: UUID`, `name: String`, `aliases: [String]`, `description: String`, `createdAt: Date`

## Workspace (workspaces/{id}/config.json)
- Fields: `id: UUID`, `name: String`, `invite_code?: String`, `owner_id: UUID`, `created_at: Date`
- Members: `WorkspaceMember { id, workspace_id, user_id, role: owner|member, joined_at }`

## Conversation
- Fields: `id: UUID`, `title: String`, `messages: [Message]`, `createdAt: Date`, `updatedAt: Date`, `userId?: String`, `summary?: String`

## Message
- Fields: `id: UUID`, `role: system|user|assistant|tool`, `content: String`, `timestamp: Date`, `toolCalls?: [ToolCall]`, `toolCallId?: String`, `imageURLs?: [URL]`
- Encoding: `toolCalls` serialized via `CodableToolCall { id, name, argumentsJSON }`

## ToolCall / ToolResult
- `ToolCall { id: String, name: String, arguments: [String: Any] }`
- `ToolResult { toolCallId: String, content: String, isError: Bool }`

## LLMResponse
- `text(String) | toolCalls([ToolCall]) | partial(String)`

## File Layout (Context)
- Base dir: `~/Library/Application Support/Dochi/`
- Files:
  - `system_prompt.md`
  - `profiles.json`
  - `memory/{userId}.md`
  - `workspaces/{wsId}/config.json`
  - `workspaces/{wsId}/memory.md`
  - `workspaces/{wsId}/agents/{name}/persona.md|memory.md|config.json`
  - Legacy read support: `system.md`, `family.md`, `memory.md`

