# 06. Agent Definition and Lifecycle

## 1) 목표

"선언적 에이전트" 원칙을 유지하면서 SDK 런타임이 바로 소비 가능한 구성 모델을 정의한다.

## 2) 에이전트 정의 파일

각 에이전트는 아래 3파일을 기본 단위로 가진다.

- `system.md`
- `config.json`
- `memory.md`

`config.json` 예시 필드:

- `id`, `name`, `wakeWord`, `description`
- `defaultModel`
- `permissionProfile` (safe/sensitive/restricted 정책)
- `toolGroups`
- `subagents`
- `memoryPolicy`

## 3) 워크스페이스 내 에이전트 구조

```text
workspaces/{workspaceId}/agents/{agentId}/
  system.md
  memory.md
  config.json
  subagents/
    {subagentId}.json
```

## 4) 런타임 매핑 규칙

- `system.md` -> SDK `systemPrompt`
- `permissionProfile` -> SDK `permissionMode` + `canUseTool`
- `toolGroups` -> 툴 라우터 allowlist
- `subagents` -> SDK subagent 구성

## 5) 웨이크워드 라우팅

입력 라우팅 단계:

1. 채널(음성/메신저/UI)별 전처리
2. wakeWord 매칭
3. workspace candidate 선택
4. agent 확정
5. 사용자 식별(profile) 확정

라우팅 결과는 `RoutingDecision`으로 기록하고 세션 시작 이벤트에 첨부한다.

## 6) 세션 라이프사이클

상태:

- `created`
- `running`
- `awaiting_approval`
- `interrupted`
- `completed`
- `failed`
- `archived`

전이 규칙:

- `running -> awaiting_approval`: sensitive/restricted 도구
- `awaiting_approval -> running`: 승인
- `awaiting_approval -> failed`: 거부/timeout
- `running -> completed`: 정상 종료

## 7) 서브에이전트 정책

서브에이전트는 기본적으로 아래를 상속하지 않는다.

- 전체 개인 메모리
- unrestricted tool access

명시적 정책으로만 부여한다.

기본 권장 패턴:

- Planner subagent: 읽기 중심
- Executor subagent: 제한된 쓰기/실행
- Reviewer subagent: 결과 검증 전용

## 8) 에이전트 버전 관리

- `config.json`에 `version`과 `updatedAt` 유지
- 실행 중 세션은 시작 시점 버전을 고정
- 버전 변경 시 신규 세션부터 적용

## 9) 에이전트 생성/수정 UX 원칙

- 생성은 템플릿 기반(가정 비서/코딩/아이 대화)
- 권한은 최소 권한 기본
- 변경 diff를 사용자에게 보여주고 승인 후 반영

