# 05. Context and Memory Architecture

## 1) 목표

CONCEPT의 4계층 컨텍스트를 에이전트 런타임에 안정적으로 공급하고, 쓰기 정책을 명확히 분리한다.

4계층:

1. 에이전트 지침(system)
2. 워크스페이스 기억(shared)
3. 에이전트 기억(agent-local)
4. 개인 컨텍스트(personal-private)

## 2) 저장소 구조(목표)

```text
~/Library/Application Support/Dochi/
  users/{userId}/memory.md
  workspaces/{workspaceId}/
    memory.md
    agents/{agentId}/
      system.md
      memory.md
      config.json
```

Supabase에는 동기화 가능한 데이터만 저장하고, 민감 원문은 로컬 암호화 저장을 우선한다.

## 3) 컨텍스트 조합 순서

런타임 주입 순서(고정):

1. Global base instructions
2. Agent `system.md`
3. Workspace memory summary + hot facts
4. Agent memory summary + hot facts
5. Personal memory (현재 사용자)
6. Channel/runtime situational metadata

규칙:

- 개인 컨텍스트는 같은 사용자일 때만 주입
- workspace 경계를 절대 넘지 않는다
- 과도한 길이는 요약본 + 참조키로 축약

## 4) Context Snapshot 모델

`ContextSnapshot` 필드(초안):

- `snapshotId`
- `workspaceId`
- `agentId`
- `userId`
- `layers`
  - systemLayer
  - workspaceLayer
  - agentLayer
  - personalLayer
- `tokenEstimate`
- `createdAt`
- `sourceRevision`

런타임에는 snapshot 전체가 아니라 `snapshotRef`를 넘기고 필요 시 지연 로딩한다.

## 5) 메모리 쓰기 파이프라인

1. 대화 종료/툴 결과 훅에서 "메모리 후보" 추출
2. 분류기(개인/워크스페이스/에이전트/폐기) 적용
3. 중복/충돌 검사
4. 사용자 승인 정책 적용(자동/승인필수)
5. 저장 + 동기화 이벤트 발행

## 6) 메모리 압축 전략

- 원문은 append-only 로그로 보존
- 운영 컨텍스트는 summary projection으로 구성
- projection 재생성은 주기적 백그라운드 작업
- summary 모델 실패 시 기존 projection 유지 (fail-safe)

## 7) 공유/프라이버시 경계

### 개인 메모리

- owner 사용자만 읽기/수정
- workspace sync 대상 아님

### 워크스페이스 메모리

- 동일 workspace 멤버 가시
- 개인 식별정보는 정책에 따라 익명화 가능

### 에이전트 메모리

- 동일 workspace 내 해당 agent에 한정
- 다른 agent는 명시적 위임 경로에서만 참조 가능

## 8) Retrieval 전략

기본 retrieval 단계:

1. 정적 layer(system/config)
2. 최근 대화 window
3. memory hot facts
4. 필요 시 semantic search fallback

RAG/검색은 컨텍스트 budget 내에서만 사용하고, budget 초과 시 검색 결과 개수 제한을 강제한다.

## 9) 실패 시 정책

- memory 저장 실패: 응답은 유지, 백그라운드 재시도 큐 적재
- summary 손상: 스냅샷 재생성 후 복구
- 동기화 충돌: vector clock 기준 merge + 충돌 로그 기록

