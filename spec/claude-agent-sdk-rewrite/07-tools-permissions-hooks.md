# 07. Tools, Permissions, Hooks

## 1) 목표

도구 실행의 안전성과 예측 가능성을 SDK 표준 기능 위에서 구현한다.

## 2) 도구 계층

### Local Native Tools

- 캘린더, 리마인더, 연락처, Finder, Shortcuts, FaceTime 등
- 앱 프로세스에서 실행하고 런타임에는 브리지 도구로 노출

### External Tools (MCP)

- 코드 호스팅, 외부 SaaS, 파일 서버 등
- MCP 서버 등록/해제/상태 관리는 도메인 계층이 담당

## 3) 권한 분류

Dochi 분류를 유지:

- `safe`
- `sensitive`
- `restricted`

SDK 매핑:

- `permissionMode`: 세션 기본 모드
- `canUseTool`: 호출 단위 최종 허용/거부/승인 요구

## 4) 정책 판정 순서

1. 에이전트 tool allowlist 확인
2. workspace 정책 확인
3. 사용자 개인 정책 확인
4. 런타임 PreToolUse 훅 판정
5. 필요 시 사용자 승인

어느 단계에서든 거부되면 즉시 중단하고 사유를 구조화 이벤트로 기록한다.

## 5) 사용자 승인 UX

승인 카드 최소 정보:

- 도구명
- 실행 이유
- 주요 인자 요약
- 위험도
- 예상 영향 범위

사용자는 `한 번 허용`, `이번 세션 허용`, `거부` 중 선택한다.

## 6) Hooks 설계

### PreToolUse

- 위험도 판정
- 금지 명령 차단
- PII/비밀정보 마스킹 적용

### PostToolUse

- 결과 요약 생성
- 메모리 후보 추출
- 실행 비용/지연 메트릭 기록

### Stop/SubagentStop

- 세션 최종 상태 기록
- 감사 로그 flush
- 리소스 정리

## 7) 금지 정책 예시

- destructive shell 명령(`rm -rf`, `sudo`, 광범위 권한 변경)
- workspace 경계를 넘는 파일 접근
- 개인 컨텍스트 외부 반출

금지 정책은 룰셋 파일로 선언하고, PreToolUse에서만 집행한다.

## 8) 도구 타임아웃/재시도

- safe read 도구: 제한적 재시도 허용
- write/execution 도구: 기본 재시도 금지 (중복 부작용 방지)
- timeout은 도구별 정책 파일에서 관리

## 9) 감사 로그 스키마

필수 필드:

- `toolCallId`
- `sessionId`
- `agentId`
- `toolName`
- `argumentsHash`
- `decision` (allowed/denied/approved)
- `latencyMs`
- `resultCode`

