# Always-On Coding Agent Ops Scenario Spec

작성일: 2026-02-22  
상태: Draft (Implementation Guide)

## 1. 목적

코딩 에이전트 운영을 다음 3가지 사용자 가치로 고정한다.

1. 에이전트가 쉬지 않도록 `일감 큐`를 지속적으로 공급한다.
2. 세션 모니터링으로 `요즘 무엇을 하고 있는지`를 메모리로 축적한다.
3. 개인/회사 레포를 구분해 `자율도(실행 권한)`를 다르게 적용한다.

핵심 원칙은 "기능 추가"가 아니라 "시나리오를 만족하는 운영 루프"다.

## 2. 현재 코드베이스 기반점

이미 있는 기반:

- 알림/점검 루프: `Dochi/Services/HeartbeatService.swift`
- 텔레그램 전송: `Dochi/Services/Telegram/TelegramProactiveRelay.swift`
- 프로액티브 제안: `Dochi/Services/ProactiveSuggestionService.swift`
- 구독제 토큰 모니터링 + 자동작업 큐잉: `Dochi/Services/ResourceOptimizerService.swift`
- 세션/레포 관찰 + 실행 가드: `Dochi/Services/ExternalToolSessionManager.swift`
- 레포 도메인 추론(personal/company/unknown): `Dochi/Services/GitRepositoryInsightScanner.swift`
- 변화 저널 저장: `Dochi/Services/HeartbeatChangeJournalService.swift`

현재 공백:

1. "해야 할 일"을 통합한 단일 `work queue`가 없다.
2. 오케스트레이션 결과 요약(`context_reflection`)이 메모리 파이프라인으로 자동 연결되지 않는다.
3. 레포별 자율도 정책이 `T0/T1/T2/T3` 단일 매트릭스에만 있고, `개인/회사 레포 정책 프로필`은 없다.

## 3. 사용자 시나리오 (명확한 계약)

### 시나리오 A: Work Never Stops

- 사용자 상황: 내가 자리에 없거나 집중이 끊겨도 "지금 해야 할 일"이 계속 올라온다.
- 트리거:
  - heartbeat change event
  - resource auto task queued
  - session stale/dead 전이
  - git dirty spike / ahead-behind 급변
- 기대 동작:
  1. 시스템이 `WorkItem`을 생성한다.
  2. 중복을 제거하고 우선순위를 계산한다.
  3. 채널 정책(app/telegram/both)에 따라 알림을 전송한다.
  4. 사용자가 `지금 실행/나중에/무시`로 처리한다.

수용 기준:

- 지난 24시간 동안 heartbeat가 관측한 유효 이벤트 중 90% 이상이 큐에 기록된다.
- 동일 `dedupeKey`의 WorkItem은 쿨다운 내 재알림되지 않는다.

### 시나리오 B: Session Memory Digest

- 사용자 상황: "내가 요즘 뭘 했지?"를 물으면 최근 작업 히스토리가 구조적으로 나온다.
- 트리거:
  - orchestrator summarize 결과
  - 세션 종료/상태 전이
  - 일정 주기(예: 1시간) digest 작업
- 기대 동작:
  1. 세션 출력에서 요약/하이라이트를 추출한다.
  2. 대화요약/메모리후보를 `workspace/agent/personal` 레이어로 분류한다.
  3. 회고 질의 시 "최근 N일 작업 타임라인 + 주요 산출물"을 재구성한다.

수용 기준:

- 최근 7일 질의에서 종료된 세션의 핵심 하이라이트 누락률이 20% 이하.
- 동일 이벤트의 중복 메모리 삽입률 10% 이하.

### 시나리오 C: Personal vs Company Autonomy

- 사용자 상황: 개인 레포는 자동 실행을 허용하고, 회사 레포는 보수적으로 통제한다.
- 트리거:
  - 레포 등록/attach 시 분류
  - 실행 요청 시 레포 정책 조회
- 기대 동작:
  1. 레포를 `personal/company/unknown`으로 분류/확정한다.
  2. 레포 정책에 따라 실행 가드(allow/confirm/deny)를 결정한다.
  3. destructive command는 레포 정책 + tier를 함께 본다.

수용 기준:

- 회사 레포에서 destructive command 무확인 실행 0건.
- 개인 레포에서 비파괴 명령 자동화 성공률 95% 이상.

## 4. 운영 루프 설계

## 4.1 Loop-1: Work Queue Loop

입력:

- `HeartbeatChangeEvent`
- `AutoTaskRecord`
- `OrchestrationSessionSelection` 실패/폴백

처리:

1. WorkItem 생성 (source, severity, repo, suggestedAction, dedupeKey)
2. 우선순위 계산
3. 큐 저장 + 알림 발행

출력:

- in-app 카드
- Telegram DM
- 실행 액션(`orch.execute`, `bridge.send`, `kanban.create`, `memory.cleanup`)

## 4.2 Loop-2: Session Memory Loop

입력:

- `orch.summarize`의 `context_reflection`
- 세션 히스토리 인덱스 검색 결과
- 세션 종료 이벤트

처리:

1. 요약 정규화 (summary/highlights/outcome/repo/branch)
2. 메모리 레이어 분류
3. 중복 제거 후 저장

출력:

- 최근 작업 회고 응답 품질 향상
- 프로젝트/레포별 최근 맥락 자동 보존

## 4.3 Loop-3: Repo Autonomy Policy Loop

입력:

- `GitRepositoryInsight.workDomain`
- 레포 수동 태깅(사용자 확정)
- 실행 명령(command class, destructive 여부)

처리:

1. 레포 정책 조회
2. 기존 tier 가드와 합성
3. 최종 decision 산출

출력:

- allow / confirmation_required / denied
- 정책 코드 + 이유 추적

## 5. 데이터 모델 제안

```swift
struct WorkItem: Codable, Sendable, Identifiable {
    let id: UUID
    let source: String               // heartbeat / resource / orchestrator / user
    let title: String
    let detail: String
    let repositoryRoot: String?
    let severity: String             // info / warning / critical
    let suggestedAction: String      // orch.execute / orch.status / memory.digest ...
    let dedupeKey: String
    let status: String               // queued / notified / accepted / deferred / dismissed / expired
    let createdAt: Date
    let dueAt: Date?
}

enum RepositoryTrustDomain: String, Codable, Sendable {
    case personal
    case company
    case unknown
}

struct RepositoryAutonomyPolicy: Codable, Sendable {
    let trustDomain: RepositoryTrustDomain
    let allowAutoNonDestructive: Bool
    let requireConfirmDestructive: Bool
    let denyAllExecution: Bool
}
```

## 6. 정책 매트릭스 제안

| Domain | Non-Destructive | Destructive |
|---|---|---|
| personal | allow (T0/T1) | confirm |
| company | confirm | deny 또는 2-step confirm |
| unknown | confirm | deny |

추가 합성 규칙:

- 기존 tier가 `t2/t3`면 domain과 무관하게 `deny`.
- domain policy가 더 강하면 domain policy 우선.

## 7. 구현 백로그 (시나리오 정렬)

### P0

1. WorkItem 저장소 + 큐 API 추가  
대상: `Dochi/Services` 신규 `WorkQueueService`
2. Heartbeat/Resource 이벤트 -> WorkItem 브릿지 추가  
대상: `Dochi/Services/HeartbeatService.swift`, `Dochi/Services/ResourceOptimizerService.swift`
3. Telegram 알림을 WorkItem 기반으로 통합  
대상: `Dochi/Services/Telegram/TelegramProactiveRelay.swift`
4. 레포 정책 모델 추가 + 실행 가드 합성  
대상: `Dochi/Models/ExternalToolModels.swift`, `Dochi/Services/ExternalToolSessionManager.swift`

### P1

1. Orchestrator summarize 결과를 메모리 파이프라인으로 적재  
대상: `Dochi/ViewModels/DochiViewModel.swift`, `Dochi/Services/Runtime/Hooks/HookPipeline.swift`
2. 사용자 시나리오별 대시보드(최근 작업/큐 상태/정책 위반)  
대상: `Dochi/Views/Settings/UsageDashboardView.swift` 또는 신규 Ops 섹션
3. 레포 trust domain 수동 확정 UI  
대상: Repository settings/editor 화면

## 8. 테스트 기준

1. WorkQueue dedupe/TTL/우선순위 테스트
2. 회사 레포 destructive 차단 테스트
3. personal 레포 비파괴 자동 실행 테스트
4. 세션 요약 -> 메모리 적재 -> 회고 질의 회수 테스트
5. 텔레그램 채널 정책(appOnly/telegramOnly/both/off) 회귀 테스트

## 9. 구현 순서 권장

1. 시나리오 A(P0) 먼저 완성: "할 일이 계속 올라오는가?"
2. 시나리오 C(P0) 적용: "회사 레포에서 안전한가?"
3. 시나리오 B(P1) 연결: "최근 작업을 기억하는가?"

## 10. 스펙 영향 링크

- 실행 컨텍스트: `spec/execution-context.md`
- 기존 UX 스펙: `spec/project-context-proactive-ux.md`
- 도구/가드: `spec/tools.md`, `spec/security.md`
