# Open Questions & Decisions

미결 과제. 확정 시 해당 스펙 문서에 반영하고 여기서 제거.

---

## 확정됨

| 항목 | 결정 | 반영 위치 |
|------|------|----------|
| Context cap and summarization | 80k chars, 3단계 압축 (대화 제거 → 메모리 요약 → 개인 메모리 요약) | [llm-requirements.md](./llm-requirements.md#context-compression) |
| 에이전트 전환 규칙 | 웨이크워드 → 현재 WS 우선 매칭 → 전체 WS 탐색. 텍스트는 UI/도구 | [voice-and-audio.md](./voice-and-audio.md#wake-word--agent-routing) |
| 권한 확인 UX | 로컬: 인라인 배너 30s. 텔레그램: 거부+인앱 안내 | [security.md](./security.md#사용자-확인-ux) |
| Supabase DB 스키마 | 7 테이블 (workspaces, workspace_members, devices, conversations, profiles, context_history, leader_locks) | [supabase.md](./supabase.md#tables) |
| 설정 UI 구조 | 6탭 (일반, AI 모델, API 키, 음성, 통합, 계정) | SettingsView.swift |
| MCP 도구 LLM 노출 | `mcp_{serverName}_{toolName}` 네이밍으로 BuiltInToolService에서 통합 | BuiltInToolService.swift |

---

## 미결

### Sync 실제 구현 전략
- Owner: TBD
- Target: 다음 작업 사이클
- Notes: context_history 테이블을 KV 마커 용도로만 쓸지, 실제 메모리 내용을 저장할지. 별도 테이블(context_files 등) 복원 필요 여부. 대화 동기화 시 messages jsonb 크기 제한.

### TTS ONNX 모델 소싱
- Owner: TBD
- Target: TTS 실제 동작 시
- Notes: Supertonic 모델 포맷 확정 필요 (duration/acoustic/vocoder 3-stage). 모델 배포 방식 (앱 번들 vs 다운로드). 음소 vocab 테이블 포맷.

### Device selection policy for remote-origin tasks
- Owner: TBD
- Target: 디바이스 관리 구현 시
- Notes: 어떤 기준으로 실행 디바이스 선택? (가용성, 능력, 사용자 근접성). 타이브레이커, 사용자 오버라이드.

### Local LLM support MVP scope
- Owner: TBD
- Target: 로드맵 Phase 7+
- Notes: 지원 모델 범위, 다운로드 UX, 오프라인 정책, 폴백 체인과의 관계.

### Telegram feature scope expansion
- Owner: TBD
- Target: 텔레그램 기본 안정화 후
- Notes: 그룹/채널 지원 여부, rate limit, 멀티턴 대화 유지, 인앱 대비 권한 범위.

### Multi-device audio conflict
- Owner: TBD
- Target: 디바이스 관리 구현 후
- Notes: 여러 디바이스에서 동시 음성 세션 시 처리 (하나만 활성? 사용자 선택?).
