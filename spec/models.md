# Data Models

핵심 데이터 모델. Phase 태그로 MVP 범위를 명시.

- **P1**: Phase 1 (텍스트 MVP) 필수
- **P2**: Phase 2 (음성)
- **P3**: Phase 3 (도구 & 권한)
- **P4**: Phase 4 (원격 & 동기화)
- **제거**: 레거시, 재작성에서 제외

---

## Settings

### UserDefaults

| 키 | 타입 | Phase | 비고 |
|----|------|-------|------|
| `llmProvider` | String (LLMProvider) | P1 | |
| `llmModel` | String | P1 | |
| `chatFontSize` | Double | P1 | |
| `interactionMode` | String (InteractionMode) | P1 | voiceAndText / textOnly |
| `contextAutoCompress` | Bool | P1 | |
| `contextMaxSize` | Int | P1 | 기본 80k chars |
| `activeAgentName` | String | P1 | 기본 에이전트 선택 |
| `wakeWordEnabled` | Bool | P2 | |
| `wakeWord` | String | P2 | |
| `sttSilenceTimeout` | Double | P2 | |
| `supertonicVoice` | String (SupertonicVoice) | P2 | |
| `ttsSpeed` | Float | P2 | |
| `ttsDiffusionSteps` | Int | P2 | |
| `autoModelRoutingEnabled` | Bool | P3 | 모델 자동 선택 |
| `mcpServers` | [MCPServerConfig] (JSON) | P3 | |
| `telegramEnabled` | Bool | P4 | |
| `telegramStreamReplies` | Bool | P4 | |
| `currentWorkspaceId` | UUID? | P4 | |
| `hasSeenPermissionInfo` | Bool | P3 | 권한 안내 표시 여부 |
| `uiDensity` | String (UIDensity) | P1 | |
| ~~`claudeUIEnabled`~~ | - | 제거 | |
| ~~`claudeUIBaseURL`~~ | - | 제거 | |
| ~~`claudeUISandboxEnabled`~~ | - | 제거 | |
| ~~`toolsRegistryAutoReset`~~ | - | 제거 | 도구 레지스트리 자동 리셋은 세션 기반으로 단순화 |

### Keychain

| 계정 | Phase | 비고 |
|------|-------|------|
| `openai` | P1 | LLM API 키 |
| `anthropic` | P1 | |
| `zai` | P1 | |
| `tavily` | P3 | 웹검색 |
| `falai` | P3 | 이미지 생성 |
| `telegram_bot_token` | P4 | |
| ~~`claude_ui_token`~~ | 제거 | |

---

## Enums

### LLMProvider (P1)
```
openai | anthropic | zai
```
- `models: [String]` — 프로바이더별 사용 가능 모델 목록
- `apiURL: URL` — 프로바이더별 엔드포인트

### SupertonicVoice (P2)
```
F1 | F2 | F3 | F4 | F5 | M1 | M2 | M3 | M4 | M5
```

### InteractionMode (P1)
```
voiceAndText | textOnly
```

---

## AgentConfig (P1)

`workspaces/{wsId}/agents/{name}/config.json`

```json
{
  "name": "코디",
  "wakeWord": "코디야",
  "description": "개발 에이전트",
  "defaultModel": "gpt-4o",
  "permissions": ["safe"]
}
```

| 필드 | 타입 | 필수 | 비고 |
|------|------|------|------|
| name | String | O | 에이전트 표시 이름 |
| wakeWord | String? | | 미설정 시 웨이크워드로 전환 불가 |
| description | String? | | |
| defaultModel | String? | | 미설정 시 앱 기본 모델 사용 |
| permissions | [String]? | | 허용 권한 카테고리. 기본: ["safe"] → [security.md](./security.md) 참조 |

---

## UserProfile (P1)

`profiles.json`

| 필드 | 타입 | 필수 |
|------|------|------|
| id | UUID | O |
| name | String | O |
| aliases | [String] | |
| description | String? | |
| createdAt | Date | O |

---

## Workspace (P4)

`workspaces/{wsId}/config.json`

| 필드 | 타입 | 필수 |
|------|------|------|
| id | UUID | O |
| name | String | O |
| invite_code | String? | |
| owner_id | UUID | O |
| created_at | Date | O |

### WorkspaceMember

| 필드 | 타입 |
|------|------|
| id | UUID |
| workspace_id | UUID |
| user_id | UUID |
| role | owner / member |
| joined_at | Date |

---

## Conversation (P1)

| 필드 | 타입 | 필수 | 비고 |
|------|------|------|------|
| id | UUID | O | |
| title | String | O | |
| messages | [Message] | O | |
| createdAt | Date | O | |
| updatedAt | Date | O | |
| userId | String? | | 사용자 식별. 텔레그램: `tg:{chat_id}` |
| summary | String? | | 자동 생성 요약 |

---

## Message (P1)

| 필드 | 타입 | 필수 | 비고 |
|------|------|------|------|
| id | UUID | O | |
| role | system / user / assistant / tool | O | |
| content | String | O | |
| timestamp | Date | O | |
| toolCalls | [ToolCall]? | | assistant 메시지에만 |
| toolCallId | String? | | tool 메시지에만 |
| imageURLs | [URL]? | | |

---

## ToolCall (P1)

| 필드 | 타입 |
|------|------|
| id | String |
| name | String |
| arguments | [String: Any] |

Codable: `CodableToolCall { id, name, argumentsJSON: String }`

---

## ToolResult (P1)

| 필드 | 타입 |
|------|------|
| toolCallId | String |
| content | String |
| isError | Bool |

---

## LLMResponse (P1)

```
text(String) | toolCalls([ToolCall]) | partial(String)
```

---

## File Layout

기본 경로: `~/Library/Application Support/Dochi/`

```
system_prompt.md                           # P1: 앱 기본 규칙
profiles.json                              # P1: 사용자 프로필
memory/{userId}.md                         # P1: 개인 기억
workspaces/{wsId}/config.json              # P4: WS 설정
workspaces/{wsId}/memory.md                # P1: WS 공유 기억 (로컬 WS는 P1)
workspaces/{wsId}/agents/{name}/
    persona.md                             # P1: 에이전트 페르소나
    memory.md                              # P1: 에이전트 기억
    config.json                            # P1: 에이전트 설정
```

### 레거시 파일 (읽기 전용, P1에서 마이그레이션)
- `system.md` → `system_prompt.md`로 마이그레이션
- `family.md` → workspace memory로 마이그레이션
- `memory.md` → `memory/{defaultUserId}.md`로 마이그레이션

P1에서 레거시 파일 감지 시 자동 마이그레이션 + 원본 `.bak` 보존. 마이그레이션 후 레거시 경로 읽기 제거.
