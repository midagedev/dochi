# 상태 정의 (States & Transitions)

앱의 핵심 상태와 전이 규칙. 불가능한 상태 조합을 타입 시스템으로 방지하는 것이 설계 목표.

## Interaction State

앱의 메인 상태 머신. 한 시점에 하나만 활성.

```
idle ──→ listening ──→ processing ──→ speaking ──→ idle
  │          │             │            │
  │          └─→ idle      └─→ idle     └─→ listening (연속대화)
  └──→ processing (텍스트 입력)
```

| 상태 | 설명 | 진입 조건 | 가능한 전이 |
|------|------|----------|------------|
| idle | 대기. 입력 수신 가능 | 초기, TTS 완료, 취소, 에러 복귀 | → listening (웨이크워드/UI), → processing (텍스트 전송) |
| listening | STT 활성. 발화 캡처 중 | 웨이크워드 감지, 연속대화, UI 토글 | → processing (발화 완료), → idle (침묵 타임아웃, 취소) |
| processing | LLM 호출 + 도구 실행 | 텍스트 전송, STT 완료 | → speaking (TTS 시작), → idle (에러, 취소, 텍스트 모드 응답 완료) |
| speaking | TTS 재생 중 | 응답 음성 준비 완료 | → idle (세션 비활성), → listening (연속대화), → idle (barge-in) |

## Session State

연속 대화 세션 관리. Interaction State와 결합하여 동작.

```
inactive ──→ active ──→ ending ──→ inactive
                │         │
                │         └─→ active (부정 응답)
                └─→ inactive (직접 종료 명령)
```

| 상태 | 설명 | 전이 |
|------|------|------|
| inactive | 세션 없음. 웨이크워드 대기 | → active: 웨이크워드 감지 |
| active | 연속 대화 중. speaking 완료 시 자동으로 listening 전환 | → ending: 침묵 타임아웃 (기본 10s), → inactive: 종료 명령어 ("대화 종료", "그만할게") |
| ending | "종료할까요?" 질문 후 응답 대기 | → inactive: 긍정 응답 / 추가 침묵 / 확인 없이 타임아웃, → active: 부정 응답 |

## Processing Sub-state

processing 상태의 세부 단계.

```
streaming ──→ toolCalling ──→ streaming ──→ complete
                  │
                  └──→ toolError ──→ streaming (에러 포함 LLM 재호출)
```

- streaming: LLM SSE 스트리밍 수신 중. 부분 응답 UI 렌더링
- toolCalling: 도구 실행 중. UI에 도구 이름 표시
- toolError: 도구 실패. 에러 메시지를 포함하여 LLM 재호출
- complete: 응답 완료. → speaking 또는 → idle 전이
- tool loop 최대 10회. 초과 시 에러 메시지 포함하여 LLM 최종 호출 후 complete

## Connection States

Interaction State와 독립적으로 관리. 각각 해당 기능의 가용성만 결정.

| 영역 | 상태 | 영향 |
|------|------|------|
| Auth | signedOut → signingIn → signedIn | 클라우드 기능(동기화, 워크스페이스) 가용성 |
| Telegram | disabled → connecting → polling → error | error 시 exponential backoff 재연결 |
| Sync | offline → syncing → synced → conflict | offline에서도 로컬 기능 정상 동작 |
| TTS Engine | unloaded → loading → ready → error | 음성 모드 가용성. error 시 텍스트 폴백 |

## 금지된 상태 조합

| 조합 | 이유 | 올바른 처리 |
|------|------|------------|
| listening + speaking | 동시 입출력 불가 | barge-in: speaking → idle → listening 순차 전이 |
| processing + listening | 응답 중 새 입력 불가 | 취소 후 listening 전이 |
| session.ending + interaction.processing | 종료 확인 중 새 쿼리 불가 | ending 해소 후 processing |
| session.inactive + interaction.speaking | 세션 없이 TTS 불가 | 텍스트 모드에서는 session 무관하게 speaking 가능 (수정: 텍스트 모드 예외 허용) |

## Barge-in 처리

사용자가 TTS 재생 중 말하거나 텍스트를 입력한 경우:

1. TTS 즉시 중단 — 현재 문장 포함, 큐 전체 비움
2. speaking → idle (일시)
3. idle → listening (음성) 또는 idle → processing (텍스트)
4. 이전 응답은 이미 표시된 부분까지 대화에 보존

## 텔레그램 요청 상태

앱의 Interaction State와 독립. 별도 비동기 파이프라인.

```
received → processing → replied
               │
               └─→ failed (에러 메시지 전송)
```

- 다수의 텔레그램 요청이 동시 진행 가능 (큐 기반 순차 처리 권장)
- 앱이 음성 대화 중이어도 텔레그램 요청은 별도 처리
- 앱 종료 시 처리 중인 요청은 유실 (재개 없음, 에러 응답도 없음)
