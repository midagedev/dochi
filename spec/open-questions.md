# Open Questions & Decisions

미결 과제. 확정 시 해당 스펙 문서에 반영하고 여기서 제거.

---

## 확정됨 (이전 버전에서 미결 → 이번 정리에서 확정)

| 항목 | 결정 | 반영 위치 |
|------|------|----------|
| Context cap and summarization | 80k chars, 3단계 압축 (대화 제거 → 메모리 요약 → 개인 메모리 요약) | [llm-requirements.md](./llm-requirements.md#context-compression) |
| 에이전트 전환 규칙 | 웨이크워드 → 현재 WS 우선 매칭 → 전체 WS 탐색. 텍스트는 UI/도구 | [voice-and-audio.md](./voice-and-audio.md#wake-word--agent-routing) |
| 권한 확인 UX | 로컬: 인라인 배너 30s. 텔레그램: 거부+인앱 안내 | [security.md](./security.md#사용자-확인-ux) |

---

## 미결

### Device selection policy for remote-origin tasks
- Owner: TBD
- Target: Phase 4 시작 전
- Notes: 어떤 기준으로 실행 디바이스 선택? (가용성, 능력, 사용자 근접성). 타이브레이커, 사용자 오버라이드

### Local LLM support MVP scope
- Owner: TBD
- Target: Phase 5 이전
- Notes: 지원 모델 범위, 다운로드 UX, 오프라인 정책, 폴백 체인과의 관계

### Telegram feature scope expansion
- Owner: TBD
- Target: Phase 4 이후
- Notes: 그룹/채널 지원 여부, rate limit, 인앱 대비 권한 범위

### Sync conflict edge cases
- Owner: TBD
- Target: Phase 4
- Notes: 라인 단위 병합 실패 시 UX (diff 표시? 양쪽 보존?). 장기 오프라인 후 대량 충돌

### Multi-device audio conflict
- Owner: TBD
- Target: Phase 4
- Notes: 여러 디바이스에서 동시 음성 세션 시 처리 (하나만 활성? 사용자 선택?)
