# 12. CLI Long-Running Orchestration Contract (Phase 3)

## 목적
장시간 코딩 작업은 앱 내부 LLM 루프가 아니라 외부 CLI(`Codex CLI`/`Claude Code`) 세션으로 위임한다. 앱은 오케스트레이션 계층으로서 아래 3가지를 담당한다.

1. 작업 위임(`execute`)
2. 상태/중단 제어(`status`, `interrupt`)
3. 결과 요약 및 컨텍스트 반영(`summarize`)

## 계약 범위
- 전송 계층: Local Control Plane(JSON-RPC 스타일)
- 대상 세션: `ExternalToolSessionManager`의 `T0/T1` runtime 세션
- 비대상: `T2/T3` 분석 전용 세션의 실행 제어

## Control Plane 메서드

### `bridge.orchestrator.select_session`
- 입력
  - `repository_root?: string`
- 출력
  - `action`: `reuse_t0_active | attach_t1 | create_t0 | analyze_only | none`
  - `reason`: 선택 이유
  - `selected_session`: 선택 세션 메타(있을 때)

### `bridge.orchestrator.execute`
- 입력
  - `command: string`
  - `repository_root?: string`
  - `confirmed?: bool` (`T1 destructive`에서 필요)
- 출력
  - `status: "sent"`
  - `selection`: 선택 결과
  - `guard`: 정책 판단 결과

### `bridge.orchestrator.status`
- 입력
  - `repository_root?: string`
  - `session_id?: string`
  - `lines?: int` (기본 120, 최대 500)
- 출력
  - `session`: 실행 세션 상태
  - `line_count`, `output_lines`
  - `result_kind`: `running | succeeded | failed | unknown`
  - `summary`, `highlights`

### `bridge.orchestrator.interrupt`
- 입력
  - `repository_root?: string`
  - `session_id?: string`
- 동작
  - 선택된 runtime 세션에 `Ctrl-C` 전송(`tmux send-keys C-c`)
- 출력
  - `status: "interrupted"`
  - `session`

### `bridge.orchestrator.summarize`
- 입력
  - `repository_root?: string`
  - `session_id?: string`
  - `lines?: int` (기본 160, 최대 500)
- 출력
  - `result_kind`, `summary`, `highlights`
  - `context_reflection`
    - `conversation_summary`
    - `memory_candidate`

## 정책/가드
- `T0`: destructive/non-destructive 자동 실행 가능
- `T1`: non-destructive 허용, destructive는 `confirmed=true` 필요
- `T2/T3`: 실행 금지(분석 전용)

실패 코드 표준:
- `session_creation_required`
- `analyze_only_fallback`
- `runtime_session_missing`
- `policy_t*_...` (가드 정책 코드)

## 컨텍스트 반영 정책
요약 반영은 `bridge.orchestrator.summarize` 반환값을 기준으로 한다.

1. 대화 컨텍스트: `context_reflection.conversation_summary`를 tool result로 포함
2. 메모리 후보: `context_reflection.memory_candidate`를 후처리 파이프라인 입력으로 전달
3. 원문 출력: 필요 시 `bridge.orchestrator.status`의 `output_lines`로 보강

## 운영 흐름
1. `select_session`으로 후보 결정
2. `execute`로 명령 위임
3. `status`로 진행 조회
4. 필요 시 `interrupt`
5. 완료 시 `summarize`로 대화/메모리 반영

## CLI 표면
`DochiCLI`는 아래 커맨드로 계약을 노출한다.

- `dochi dev bridge orchestrator select [--repo PATH]`
- `dochi dev bridge orchestrator execute <command> [--repo PATH] [--confirmed]`
- `dochi dev bridge orchestrator status [--repo PATH] [--session ID] [--lines N]`
- `dochi dev bridge orchestrator interrupt [--repo PATH] [--session ID]`
- `dochi dev bridge orchestrator summarize [--repo PATH] [--session ID] [--lines N]`
