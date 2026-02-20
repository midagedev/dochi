# Tool Context Preference Routing

상태: Proposed (구현 대상)  
작성: 2026-02-20  
관련 이슈: TBD

## 1) 배경

최근 대화에서 "코딩 에이전트 목록" 요청 시 모델이 Finder/Kanban 같은 baseline 도구를 반복 호출하고,
의도와 직접 관련된 `agent.list`, `coding.sessions` 호출이 늦거나 누락되는 문제가 확인됐다.

현재 구조는 다음 특성이 있다.
- non-baseline 도구는 `tools.enable` 이후에만 노출 가능
- 도구 정렬은 `preferredToolGroups` 우선 + 이름 순 정렬
- 실제 사용 패턴(어떤 도구가 자주/최근 성공했는지)과 사용자 선호가 정렬에 반영되지 않음

## 2) 목표

1. 사용자/어시스턴트 선호 카테고리와 사용 이력을 결합해 도구 노출 우선순위를 개선한다.
2. 프롬프트 컨텍스트 토큰을 크게 늘리지 않고, 도구 선택에 필요한 신호만 요약해서 제공한다.
3. 기존 권한/정책 모델(`safe/sensitive/restricted`, capability router)을 깨지 않는다.

## 3) 비목표

- 개인화 모델 학습(ML) 도입
- 도구 권한 정책 자체 재설계
- UI 대규모 개편

## 4) 설계 개요

### 4.1 데이터 모델

`ToolContextProfile` (workspace + agent 단위)
- `agentName`
- `workspaceId`
- `categoryScores: [String: Double]`
- `toolScores: [String: Double]`
- `lastUpdatedAt`

`UserToolPreference` (workspace 단위, 사용자 공통)
- `preferredCategories: [String]` (명시 선택/수동 고정)
- `suppressedCategories: [String]`
- `updatedAt`

`ToolUsageEvent` (실행 이벤트 원본)
- `toolName`
- `category`
- `decision` (`allowed`, `approved`, `denied`, `policyBlocked`, `hookBlocked`)
- `latencyMs`
- `agentName`
- `workspaceId`
- `timestamp`

### 4.2 저장소

`ToolContextStore` 신규 도입
- 위치: `~/Library/Application Support/Dochi/tool_context.json`
- 전략: 메모리 캐시 + debounce write (기존 `UsageStore` 패턴 재사용)
- 보존: 원본 이벤트는 단기(최대 N건), 점수는 누적/감쇠(decay)

### 4.3 점수 업데이트

도구 실행 후(`ToolDispatchHandler.recordAudit`) 아래 규칙으로 프로필 갱신:
- 성공/허용 이벤트: category/tool 점수 가산
- 차단/거부 이벤트: tool 점수 소폭 감산
- 시간 감쇠: 최근 이벤트일수록 가중치가 높음

### 4.4 정렬/노출 알고리즘

`BuiltInToolService.availableToolSchemas` 경로에서 기존 정렬을 대체/확장:

`finalScore =`
- `policyGate` (통과 못하면 제외)
- `+ agentPreferredCategoryWeight`
- `+ userPreferredCategoryWeight`
- `+ usageCategoryWeight`
- `+ usageToolWeight`
- `+ baselineBoost` (필수 baseline 최소 보장)

정렬 후 룰:
- 상위 `N`개 + 필수 baseline subset만 노출 (기본 N=12)
- `coding.*` 의도에서 `agent.list`, `coding.sessions` 같은 고연관 도구에 intent boost 적용

### 4.5 프롬프트 컨텍스트 슬림 요약

`ContextSnapshotBuilder`에 고정 길이 도구 컨텍스트 블록 추가:
- "최근 성공 카테고리 Top 3"
- "현재 에이전트 선호 카테고리"
- "사용자 고정 선호 카테고리"

요약 길이 제한:
- 최대 120 토큰

## 5) UX 통합

화면 영향이 있는 최소 변경만 포함:
- Agent 설정 화면에 `선호 도구 카테고리` 편집 진입점(기존 `preferredToolGroups` 재사용)
- 사용자 전역 `선호/제외 카테고리` 토글은 별도 이슈로 분리

## 6) 단계별 구현

### Phase 1
- `ToolContextStore` + 모델 추가
- `ToolDispatchHandler`에서 usage 이벤트 기록
- 단위 테스트

### Phase 2
- `BuiltInToolService`에 점수 기반 정렬 도입
- intent boost (coding-agent-status 계열) 추가
- 회귀 테스트(코딩 에이전트 목록 시나리오)

### Phase 3
- Context snapshot에 120토큰 요약 블록 삽입
- 토큰 예산 회귀 테스트

## 7) 수용 기준 (DoD)

1. 코딩 에이전트 상태/목록 요청 회귀 테스트에서 `agent.list` 또는 `coding.sessions`가 우선 후보에 포함된다.
2. 도구 정렬이 이름순이 아닌 선호+이력 기반으로 재현 가능하게 동작한다.
3. 신규 저장소/에이전트(콜드 스타트)에서도 기존 baseline 동작이 깨지지 않는다.
4. 전체 테스트 통과.

## 8) 오픈 이슈

1. 사용자 전역 선호를 어느 UX 진입점에서 처음 수집할지
2. `suppressedCategories`를 하드 차단으로 볼지 소프트 감점으로 볼지
3. 여러 워크스페이스 간 선호 동기화를 기본값으로 할지
