# Data Overview (Conceptual)

엔티티와 관계. 구체적 필드는 [models.md](./models.md), 테이블 스키마는 [supabase.md](./supabase.md) 참조.

---

## Entities

- **User**: 사람. 별칭(aliases) 보유. 개인 기억(personal memory) 소유
- **Workspace**: 목적별 공유 컨텍스트 (가족, 팀). 에이전트와 공유 기억 포함. 멤버 관리
- **Agent**: 이름 있는 AI 어시스턴트. 페르소나, 웨이크워드, 기본 모델, 권한. 워크스페이스 범위
- **Memory**:
  - Workspace memory: 멤버 전체 공유 사실
  - Agent memory: 에이전트가 자동 축적하는 메모
  - Personal memory: 사용자 소유, 워크스페이스 횡단
- **Conversation**: 사용자-에이전트 간 메시지 순서열. 도구 호출과 요약 포함 가능
- **Message**: system/user/assistant/tool 콘텐츠. 이미지, 도구 호출 포함 가능
- **Device**: 실행 피어. 음성, 도구, UI 수행 가능. 사용자와 워크스페이스에 연결

---

## Relationships

```
User ──1:N── Device
User ──N:M── Workspace (via WorkspaceMember)
User ──1:1── Personal Memory

Workspace ──1:N── Agent
Workspace ──1:N── Conversation
Workspace ──1:1── Workspace Memory

Agent ──1:1── Persona
Agent ──1:1── Agent Memory
Agent ──1:N── Conversation
```

---

## Retention & Size

- 메모리: 라인 지향 (`- ...`). append 우선, safe update
- 크기 한도 초과 시 LLM 요약으로 압축 ([llm-requirements.md](./llm-requirements.md#context-compression) 참조)
- 수동 편집: preview + confirm 가드레일 ([tools.md](./tools.md) Agent Editor 참조)

---

## Visibility

| 데이터 | 가시성 |
|--------|--------|
| Personal memory | 소유 사용자만 |
| Workspace memory | 워크스페이스 멤버 |
| Agent memory | 해당 에이전트 대화 시 |
| Conversation | 참여자(사용자 + 에이전트) |

상세 권한 규칙: [security.md](./security.md) 참조.
