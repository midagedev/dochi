# 01. Claude Agent SDK Reference

이 문서는 Dochi 리라이트에서 필요한 Claude Agent SDK 핵심 기능만 정리한 실무 참조 문서입니다.

## 1) SDK가 해결하는 영역

Claude Agent SDK는 다음 엔진 책임을 기본 제공한다.

- 대화/툴 호출 루프 실행
- 권한 모드와 도구 실행 승인 흐름
- 세션 생성/재개/중단
- 훅 기반 정책 삽입 (PreToolUse, PostToolUse 등)
- MCP 도구 연결
- 서브에이전트 실행과 컨텍스트 분리

리라이트 방향은 "엔진 재구현"이 아니라 "도메인 통합"이어야 한다.

## 2) 인증/접속 모델

공식 문서 기준 지원 경로:

- Anthropic API Key
- AWS Bedrock
- Google Vertex AI

주의사항:

- Claude.ai 계정(웹/앱 구독)을 제3자 앱의 일반 API 호출 권한으로 직접 전용할 수 없다.
- ChatGPT OAuth/플랜과 OpenAI API가 분리되는 것처럼, Claude도 런타임 인증 경로를 명확히 분리해야 한다.

## 3) 세션 모델

핵심 포인트:

- `query()`는 필요 시 세션 ID를 지정하여 기존 세션을 이어갈 수 있다.
- SDK 클라이언트 단에서 중단/재개/권한 모드 변경 API를 제공한다.
- 장기 대화/워크플로우는 "Dochi Session ID <-> SDK Session ID" 매핑이 필수다.

Dochi 적용 규칙:

- 세션 키는 최소 `workspaceId + agentId + conversationId + deviceId`로 구성한다.
- 음성/텍스트/메신저 채널이 달라도 동일 세션 키를 재사용 가능해야 한다.

## 4) 권한 모델

핵심 포인트:

- `permissionMode` 및 `canUseTool`로 도구 실행을 통제한다.
- default/plan/acceptEdits/bypassPermissions(고위험) 같은 모드를 제공한다.
- 실제 제품에서는 모드 + 정책 함수 + 사용자 확인 UI를 함께 써야 안전하다.

Dochi 적용 규칙:

- Safe 도구는 자동 허용 가능
- Sensitive/Restricted는 `canUseTool` + 사용자 확인 이중 게이트 적용
- `bypassPermissions`는 개발/테스트 한정, 프로덕션 비허용

## 5) Hooks

핵심 포인트:

- PreToolUse, PostToolUse, Notification, Stop, SubagentStop 훅을 이용해 정책과 관측을 삽입한다.
- TypeScript SDK가 가장 넓은 훅 이벤트를 지원한다.

Dochi 적용 규칙:

- PreToolUse: 정책/금칙어/PII 마스킹/위험도 판정
- PostToolUse: 결과 요약, 메모리 후보 추출, 감사 로그
- Stop/SubagentStop: 세션 결과 커밋, 메트릭 집계

## 6) 서브에이전트

핵심 포인트:

- 서브에이전트는 독립 컨텍스트를 가지며 병렬 작업이 가능하다.
- 메인 에이전트 컨텍스트를 줄이고 도메인별 역할 분리를 강화할 수 있다.

Dochi 적용 규칙:

- 코딩, 가정 비서, 아이 대화, 운영 자동화를 서브에이전트 단위로 분리
- 서브에이전트별 도구/권한/메모리 접근 범위를 강제

## 7) MCP

핵심 포인트:

- 런타임에서 MCP 서버를 연결하면 외부 도구를 표준 방식으로 호출 가능
- 소켓/stdio 기반 서버를 조합해 도구 생태계를 확장 가능

Dochi 적용 규칙:

- 내장 macOS 도구는 우선 로컬 브리지 도구로 제공
- 장기적으로 외부 연동은 MCP 우선 전략 채택

## 8) TypeScript vs Python 선택

Dochi 리라이트 1차 선택: TypeScript SDK

근거:

- 훅 이벤트 커버리지 우위
- 옵션/설정(예: `settingSources`, permission API) 적용 범위가 실무적으로 넓음
- Node 런타임 기반 sidecar 운영이 macOS 앱과 IPC 통합에 유리

원칙:

- 런타임은 TS로 시작하되, 브리지를 언어 중립(JSON-RPC)로 설계해 교체 가능성 확보

## 9) 초기 런타임 권장 설정

- 모델: Claude Sonnet 계열(기본), 필요 시 프로필별 override
- `settingSources`: `project`, `user`(개발 단계), 배포 시 최소화
- hooks: PreToolUse/PostToolUse/Stop 활성화
- maxTurns: 채널/과업 성격별 동적 제한
- permissionMode: 사용자/에이전트 정책 기반 동적 제어

## 10) 참고 문서

- [Agent SDK Overview](https://platform.claude.com/docs/en/agent-sdk/overview)
- [Quickstart](https://docs.anthropic.com/en/docs/claude-code/sdk/sdk-quickstart)
- [TypeScript SDK](https://docs.anthropic.com/en/docs/claude-code/sdk/typescript)
- [Python SDK](https://docs.anthropic.com/en/docs/claude-code/sdk/python)
- [Permissions](https://docs.anthropic.com/en/docs/claude-code/sdk/sdk-permissions)
- [Hooks](https://docs.anthropic.com/en/docs/claude-code/hooks/sdk-hooks)
- [Sessions](https://docs.anthropic.com/en/docs/claude-code/sdk/sdk-sessions)
- [Subagents](https://docs.anthropic.com/en/docs/claude-code/sdk/sdk-sub-agents)
- [MCP](https://docs.anthropic.com/en/docs/claude-code/sdk/mcp)
