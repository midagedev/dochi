# Tool Routing Policy (Phase 3)

## 목적
- BuiltIn 도구와 MCP 도구의 라우팅/리스크/승인 흐름을 단일 정책으로 맞춘다.
- 경로별 예외 동작을 줄여 운영 리스크를 낮춘다.

## 라우팅 원칙
1. 요청 이름이 `mcp_`로 시작하면 MCP 경로로 라우팅한다.
2. 그 외 이름은 BuiltIn 경로(역직렬화 포함)로 라우팅한다.
3. 라우팅 결정은 로그에 남긴다.
   - requested 이름
   - source (`builtin`/`mcp`)
   - resolved 이름
   - risk (`safe`/`sensitive`/`restricted`)
   - reason

## MCP 리스크 분류
- `restricted` 키워드 우선: execute/run/shell/terminal/delete/remove/rm/sudo/reset/rebase/commit/push 등
- `sensitive` 키워드: create/update/set/add/edit/rename/move/copy/branch/merge/checkout/tag/stash/apply 등
- `safe` 키워드: list/get/read/search/status/log/diff/show/find/ls/cat/head/tail 등
- 매칭되지 않는 MCP 도구는 보수적으로 `sensitive` 처리

## 승인 정책
- `safe`: 승인 없이 실행
- `sensitive`/`restricted`: BuiltIn/MCP 모두 동일하게 승인 핸들러 필요
- 승인 채널이 없으면 실행 차단
- 사용자 거부 시 실행 차단

## 예외
- BuiltIn `shell.execute`, `terminal.run`은 기존 도구 내부 승인 흐름을 유지

## 감사/추적
- 라우팅 로그 + 기존 감사 로그를 조합해
  - 어떤 경로로 실행되었는지
  - 어떤 리스크로 분류되었는지
  - 승인/차단이 어떻게 되었는지
  를 추적한다.
