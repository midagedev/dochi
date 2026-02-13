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
| `ttsSpeed` | Double | P2 | |
| `ttsPitch` | Double | P2 | 0 = 기본, +높은/-낮은 |
| `ttsDiffusionSteps` | Int | P2 | ONNX용 |
| `ttsProvider` | String (TTSProvider) | P2 | system / googleCloud |
| `googleCloudVoiceName` | String | P2 | Google Cloud TTS 음성 ID |
| `mcpServersJSON` | String (JSON) | P3 | MCP 서버 목록 |
| `telegramEnabled` | Bool | P4 | |
| `telegramStreamReplies` | Bool | P4 | |
| `currentWorkspaceId` | String (UUID) | P4 | |
| `hasSeenPermissionInfo` | Bool | P3 | 권한 안내 표시 여부 |
| `uiDensity` | String | P1 | |
| `wakeWordAlwaysOn` | Bool | P2 | 앱 활성 중 항상 감지 |
| `avatarEnabled` | Bool | UI | 3D 아바타 표시 |
| `heartbeatEnabled` | Bool | UI | 프로액티브 에이전트 |
| `heartbeatIntervalMinutes` | Int | UI | 기본 30분 |
| `heartbeatCheckCalendar` | Bool | UI | |
| `heartbeatCheckKanban` | Bool | UI | |
| `heartbeatCheckReminders` | Bool | UI | |
| `heartbeatQuietHoursStart` | Int | UI | 기본 23시 |
| `heartbeatQuietHoursEnd` | Int | UI | 기본 8시 |
| `fallbackLLMProvider` | String | P5 | |
| `fallbackLLMModel` | String | P5 | |
| `supabaseURL` | String | P4 | |
| `supabaseAnonKey` | String | P4 | |

### Keychain

| 계정 | Phase | 비고 |
|------|-------|------|
| `openai` | P1 | LLM API 키 |
| `anthropic` | P1 | |
| `zai` | P1 | |
| `tavily` | P3 | 웹검색 |
| `falai` | P3 | 이미지 생성 |
| `telegram_bot_token` | P4 | |
| `google_cloud_tts` | P2 | Google Cloud TTS API 키 |

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

### TTSProvider (P2)
```
system | googleCloud
```
- `system`: Apple AVSpeechSynthesizer
- `googleCloud`: Google Cloud TTS API (Wavenet/Neural2/Standard/Chirp3-HD)
- `displayName`, `requiresAPIKey`, `keychainAccount` 프로퍼티

### GoogleCloudVoice (P2)
한국어 TTS 음성 카탈로그.
- Tier: `chirp3HD`, `wavenet`, `neural2`, `standard`
- 14종 한국어 음성 내장 (ko-KR-*)
- `voicesByTier`: tier별 그룹화 목록

### KanbanBoard (UI)
`~/Library/Application Support/Dochi/kanban/{boardId}.json`

| 필드 | 타입 | 비고 |
|------|------|------|
| id | UUID | |
| name | String | |
| columns | [String] | 기본: ["할 일", "진행 중", "완료"] |
| cards | [KanbanCard] | |
| createdAt | Date | |

### KanbanCard (UI)

| 필드 | 타입 | 비고 |
|------|------|------|
| id | UUID | |
| title | String | |
| description | String? | |
| column | String | |
| priority | low/medium/high/urgent | |
| labels | [String] | |
| assignee | String? | |
| createdAt | Date | |
| updatedAt | Date | |

### ExchangeMetrics (P5)

| 필드 | 타입 | 비고 |
|------|------|------|
| id | UUID | |
| provider | String | |
| model | String | |
| inputTokens | Int | |
| outputTokens | Int | |
| firstTokenLatency | TimeInterval? | |
| totalLatency | TimeInterval | |
| toolCallCount | Int | |
| timestamp | Date | |

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
conversations/{id}.json                    # P1: 대화 기록
memory/{userId}.md                         # P1: 개인 기억
kanban/{boardId}.json                      # UI: 칸반 보드 데이터
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
