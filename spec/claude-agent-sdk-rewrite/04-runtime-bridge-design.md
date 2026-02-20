# 04. Runtime Bridge Design

## 1) 목적

Swift 앱과 Claude Agent SDK 런타임(TypeScript sidecar)을 느슨하게 결합하기 위한 IPC 계층을 정의한다.

원칙:

- 런타임 언어 비종속
- 요청/응답 + 이벤트 스트림 분리
- 세션 단위 관측 가능성

## 2) 프로세스 모델

- 부모: Dochi macOS App
- 자식: `dochi-agent-runtime` (Node.js/TypeScript)
- 통신: Unix Domain Socket (로컬 전용)
- 프로토콜: JSON-RPC 2.0 + Server-Sent Event 스타일의 단방향 이벤트 채널

## 3) 초기화 수명주기

1. 앱 시작 시 런타임 바이너리 존재/버전 검사
2. 런타임 프로세스 실행
3. `runtime.initialize` 호출
4. 런타임이 설정/도구/훅 로딩 후 ready 이벤트 전송
5. 실패 시 exponential backoff 재시작

## 4) RPC 인터페이스 (초안)

### 4.1 Runtime

- `runtime.initialize`
  - 입력: runtimeVersion, configProfile, settingSources
  - 출력: capabilities, runtimeSessionId

- `runtime.health`
  - 출력: alive, uptimeMs, activeSessions, lastError

- `runtime.shutdown`
  - 출력: success

### 4.2 Session

- `session.open`
  - 입력: `workspaceId`, `agentId`, `conversationId`, `userId`, optional `sdkSessionId`
  - 출력: `sessionId`, `sdkSessionId`, `created`

- `session.run`
  - 입력: `sessionId`, `input`, `contextSnapshotRef`, `permissionMode`
  - 출력: ack
  - 이벤트: partial, tool_call, tool_result, completed, failed

- `session.interrupt`
  - 입력: `sessionId`
  - 출력: interrupted

- `session.close`
  - 입력: `sessionId`
  - 출력: closed

- `session.list`
  - 출력: session summaries

### 4.3 Tool Dispatch

- `tool.dispatch`
  - 런타임 -> 앱 요청
  - 입력: `toolCallId`, `toolName`, `arguments`, `riskLevel`

- `tool.result`
  - 앱 -> 런타임 응답
  - 입력: `toolCallId`, `success`, `content`, `structuredData?`

### 4.4 Approval

- `approval.request`
  - 런타임 -> 앱 요청
  - 입력: `sessionId`, `toolName`, `reason`, `preview`

- `approval.resolve`
  - 앱 -> 런타임 응답
  - 입력: approved/denied, optional note

## 5) 이벤트 스키마

모든 이벤트 공통 필드:

- `eventId`
- `timestamp`
- `sessionId`
- `workspaceId`
- `agentId`
- `eventType`
- `payload`

핵심 이벤트 타입:

- `runtime.ready`
- `session.started`
- `session.partial`
- `session.tool_call`
- `session.tool_result`
- `session.completed`
- `session.failed`
- `approval.required`
- `policy.blocked`

## 6) 오류 및 복구 정책

### 런타임 프로세스 종료

- 앱은 세션을 `recovering` 상태로 전이
- 자동 재시작 시 `sdkSessionId` 재주입으로 resume 시도
- resume 실패 시 사용자에게 명시 안내 후 새 세션 시작

### 도구 실행 타임아웃

- 도구별 timeout budget을 정책 파일에서 관리
- timeout 발생 시 런타임에 실패 결과 반환 + 재시도 금지 기본

### 브리지 단절

- 이벤트 수신 중단 감지 시 상태를 `degraded`로 표기
- 재연결 후 마지막 eventId 기준 ack/replay 지원

## 7) 보안 경계

- UDS 파일 권한은 앱 사용자 계정만 접근 가능하게 제한
- 브리지에는 원문 비밀값을 남기지 않고 reference token만 전달
- 감사 로그에는 tool args 마스킹 규칙 적용

## 8) 구현 우선순위

1. 최소 RPC (`initialize`, `open`, `run`, `dispatch`, `result`)
2. approval 이벤트 경로
3. health/recovery
4. replay/ack 고도화

