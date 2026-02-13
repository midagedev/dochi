# Built-in Tools

내장 도구 스키마 정의. MCP 스타일 입력 스키마. 권한 카테고리는 [security.md](./security.md) 참조.

---

## 도구 레지스트리

기본 노출(baseline)과 조건부 노출을 분리하여 토큰 사용 최적화.

### 레지스트리 제어 도구 (항상 노출)
- `tools.list` {} — 사용 가능한 도구 목록
- `tools.enable` { names: [String] } — 이름으로 활성화
- `tools.enable_ttl` { minutes: Int } — 세션 내 TTL 설정
- `tools.reset` {} — 기본 상태 복원

### 기본 노출 전략
- baseline 도구만 LLM에 전달 (아래 표 참조)
- LLM이 `tools.enable`으로 추가 도구 활성화 가능
- 세션 종료 시 자동 리셋

---

## 도구 목록

### Baseline (항상 노출)

| 도구 | 카테고리 | 입력 | 조건 |
|------|---------|------|------|
| `tools.list` | safe | {} | - |
| `tools.enable` | safe | { names: [String] } | - |
| `tools.enable_ttl` | safe | { minutes: Int } | - |
| `tools.reset` | safe | {} | - |
| `create_reminder` | safe | { title, due_date?, notes?, list_name? } | - |
| `list_reminders` | safe | { list_name?, show_completed? } | - |
| `complete_reminder` | safe | { title } | - |
| `set_alarm` | safe | { label, fire_date?, delay_seconds? } | 둘 중 하나 필수 |
| `list_alarms` | safe | {} | - |
| `cancel_alarm` | safe | { label } | - |
| `save_memory` | safe | { content, scope: "workspace"\|"personal" } | - |
| `update_memory` | safe | { old_content, new_content, scope } | - |
| `set_current_user` | safe | { name } | - |
| `web_search` | safe | { query } | Tavily API 키 필요 |
| `generate_image` | safe | { prompt, image_size? } | fal.ai API 키 필요 |
| `print_image` | safe | { image_path } | - |
| `calculate` | safe | { expression } | - |
| `datetime` | safe | {} | 현재 날짜/시간 반환 |
| `clipboard.read` | safe | {} | - |
| `clipboard.write` | safe | { text } | - |
| `set_timer` | safe | { label, seconds } | - |
| `list_timers` | safe | {} | - |
| `cancel_timer` | safe | { label } | - |
| `calendar.list_events` | safe | { days_ahead?, calendar_name? } | EventKit |
| `contacts.search` | safe | { query } | Contacts.framework |
| `contacts.get_detail` | safe | { name } | - |
| `music.now_playing` | safe | {} | Apple Music (AppleScript) |
| `music.play_pause` | safe | {} | - |
| `music.next` | safe | {} | - |
| `music.search_play` | safe | { query } | - |
| `finder.reveal` | safe | { path } | Finder에서 표시 |
| `finder.get_selection` | safe | {} | 현재 선택 파일 |
| `finder.list_dir` | safe | { path } | 디렉토리 목록 |
| `kanban.create_board` | safe | { name, columns? } | - |
| `kanban.list_boards` | safe | {} | - |
| `kanban.list` | safe | { board_id, column?, priority? } | 카드 필터링 |
| `kanban.add_card` | safe | { board_id, title, column?, description?, priority?, labels?, assignee? } | - |
| `kanban.move_card` | safe | { board_id, card_id, column } | - |
| `kanban.update_card` | safe | { board_id, card_id, title?, description?, priority?, labels?, assignee? } | - |
| `kanban.delete_card` | safe | { board_id, card_id } | - |

### 조건부 — Calendar (sensitive)

| 도구 | 입력 |
|------|------|
| `calendar.create_event` | { title, start_date, end_date?, calendar_name?, location?, notes? } |
| `calendar.delete_event` | { event_id } |

### 조건부 — Git (safe: 읽기 / restricted: 쓰기)

| 도구 | 카테고리 | 입력 |
|------|---------|------|
| `git.status` | safe | { path? } |
| `git.log` | safe | { path?, count? } |
| `git.diff` | safe | { path?, staged? } |
| `git.commit` | restricted | { message, path? } |
| `git.branch` | restricted | { action: "list"\|"create"\|"switch"\|"delete", name? } |

### 조건부 — GitHub (safe/sensitive)

| 도구 | 카테고리 | 입력 |
|------|---------|------|
| `github.list_issues` | safe | { repo, state?, labels? } |
| `github.view` | safe | { repo, number } |
| `github.create_issue` | sensitive | { repo, title, body?, labels? } |
| `github.create_pr` | sensitive | { repo, title, body?, head, base? } |

### 조건부 — Agent Orchestration (sensitive)

| 도구 | 입력 |
|------|------|
| `agent.delegate_task` | { agent_name, task, context? } |
| `agent.check_status` | { agent_name } |

### 조건부 — Coding Agent (restricted/sensitive)

| 도구 | 카테고리 | 입력 |
|------|---------|------|
| `coding.run_task` | restricted | { task, working_directory? } |
| `coding.review` | sensitive | { file_path?, diff? } |

### 조건부 — Open URL (sensitive)

| 도구 | 입력 |
|------|------|
| `open_url` | { url } |

### 조건부 — Shell (restricted)

| 도구 | 입력 |
|------|------|
| `shell_command` | { command, working_directory?, timeout? } |

### 조건부 — Settings (sensitive)

| 도구 | 입력 |
|------|------|
| `settings.set` | { key, value: String } |
| `settings.get` | { key } |
| `settings.list` | {} |
| `settings.mcp_add_server` | { name, command, arguments?, environment?, is_enabled? } |
| `settings.mcp_update_server` | { id: UUID, name?, command?, arguments?, environment?, is_enabled? } |
| `settings.mcp_remove_server` | { id: UUID } |

설정 가능 키: `wakeWordEnabled`, `wakeWord`, `llmProvider`, `llmModel`, `supertonicVoice`, `ttsSpeed`, `ttsDiffusionSteps`, `chatFontSize`, `sttSilenceTimeout`, `contextAutoCompress`, `contextMaxSize`, `activeAgentName`, `telegramEnabled`, `defaultUserId`, API 키들.

### 조건부 — Agent (sensitive)

| 도구 | 입력 |
|------|------|
| `agent.create` | { name, wake_word?, description? } |
| `agent.list` | {} |
| `agent.set_active` | { name } |

### 조건부 — Agent Editor (sensitive)

**Persona:**
- `agent.persona_get` { name? }
- `agent.persona_search` { query, name? }
- `agent.persona_update` { mode: "replace"\|"append", content, name? }
- `agent.persona_replace` { find, replace, name?, preview?, confirm? }
- `agent.persona_delete_lines` { contains, name?, preview?, confirm? }

**Memory:**
- `agent.memory_get` { name? }
- `agent.memory_append` { content, name? }
- `agent.memory_replace` { content, name? }
- `agent.memory_update` { find, replace, name? }

**Config:**
- `agent.config_get` { name? }
- `agent.config_update` { wake_word?, description?, name? }

가드레일: `persona_replace`, `persona_delete_lines`에서 매칭 5건 초과 시 `confirm: true` 없으면 거부. `preview: true`로 미리보기 가능.

### 조건부 — Context (sensitive)

| 도구 | 입력 |
|------|------|
| `context.update_base_system_prompt` | { mode: "replace"\|"append", content } |

### 조건부 — Profile Admin (sensitive)

| 도구 | 입력 |
|------|------|
| `profile.create` | { name, aliases?, description? } |
| `profile.add_alias` | { name, alias } |
| `profile.rename` | { from, to } |
| `profile.merge` | { source, target, merge_memory: "append"\|"skip"\|"replace" } |

merge: personal memory 이전 + 대화 userId 매핑 갱신.

### 조건부 — Workspace (sensitive, Supabase 필요)

| 도구 | 입력 |
|------|------|
| `workspace.create` | { name } |
| `workspace.join_by_invite` | { invite_code } |
| `workspace.list` | {} |
| `workspace.switch` | { id: UUID } |
| `workspace.regenerate_invite_code` | { id: UUID } |

### 조건부 — Telegram (sensitive)

| 도구 | 입력 |
|------|------|
| `telegram.enable` | { enabled: Bool, token? } |
| `telegram.set_token` | { token } |
| `telegram.get_me` | {} |
| `telegram.send_message` | { chat_id: Int, text } |

---

## 반환 형식

- 모든 도구는 사람이 읽을 수 있는 요약 문자열 반환
- 필요 시 구조화 텍스트(JSON snippet) 포함
- 에러: `{ isError: true, content: "에러 설명 + 해결 안내" }`

---

## 날짜 형식

도구 입력의 날짜: ISO 8601 (`2026-02-07T15:00:00`) 권장. 한국어 자연어도 허용 ("내일 오후 3시").

---

## 이미지 크기 옵션 (generate_image)

`square_hd`, `square`, `landscape_4_3`, `landscape_16_9`, `portrait_4_3`, `portrait_16_9`
