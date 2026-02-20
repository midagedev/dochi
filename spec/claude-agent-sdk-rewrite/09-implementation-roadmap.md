# 09. Implementation Roadmap

> Deprecated (2026-02-20): 본 문서는 SDK 전면 전환 시점 로드맵 이력이다.  
> 현재 active 로드맵은 `spec/claude-agent-sdk-rewrite/README.md`와 `spec/claude-agent-sdk-rewrite/rewrite-delivery-context.md`, 그리고 이슈 [#318](https://github.com/midagedev/dochi/issues/318)을 따른다.

## 1) 전략

전면 교체가 목표이지만, 실행은 짧은 단계로 쪼개 리스크를 줄인다.

원칙:

- 단계별로 "동작 가능한 상태" 유지
- 각 단계 종료 시 삭제 가능한 legacy를 즉시 제거

## 2) 단계 계획

## Phase 0 - Skeleton (1주)

산출물:

- `dochi-agent-runtime` 프로젝트 생성 (TypeScript)
- 브리지 프로토콜 최소 구현 (`initialize`, `health`)
- macOS 앱에서 런타임 프로세스 lifecycle 관리

완료 기준:

- 앱 시작 시 런타임 준비 상태 표시
- 장애 시 자동 재시작 동작 확인

## Phase 1 - Core Session (1~2주)

산출물:

- `session.open/run/interrupt/close` 구현
- partial 스트리밍 UI 연결
- 세션 ID 매핑 저장

완료 기준:

- 기본 질의응답이 SDK 경로로만 처리됨
- 기존 custom loop 우회 가능

## Phase 2 - Tool Bridge + Permissions (2주)

산출물:

- Local tool dispatch 연결
- `canUseTool` + 승인 UI 연동
- PreToolUse/PostToolUse 훅 정책

완료 기준:

- safe/sensitive/restricted 정책이 SDK 경로에서 동작
- 감사 로그 생성

## Phase 3 - Context/Memory Integration (2주)

산출물:

- 4계층 snapshot builder
- 메모리 후보 추출/저장 파이프라인
- summary projection 및 budget 제어

완료 기준:

- 에이전트 응답 품질이 기존 대비 동등 이상
- 개인/워크스페이스 경계 위반 0건

## Phase 4 - Multi-device + Channel Unification (2주)

산출물:

- lease 기반 디바이스 할당
- 메신저/음성/텍스트 통합 세션 라우팅
- cross-device resume

완료 기준:

- 지정 시나리오 E2E 통과
- 라우팅 실패율 목표치 이내

## Phase 5 - Legacy Removal (1주)

산출물:

- 기존 LLM adapter/tool loop/enable-ttl 코드 제거
- 관련 테스트 재구성
- 문서 정본 업데이트

완료 기준:

- 레거시 엔진 경로 0%
- 빌드/테스트/스모크 전체 통과

## 3) 삭제 우선 후보 (현재 코드 기준)

- `Dochi/ViewModels/DochiViewModel.swift` 내 커스텀 tool loop
- `Dochi/Services/LLM/*Adapter.swift`, `LLMService.swift`
- `Dochi/Services/Tools/ToolsRegistryTool.swift`
- `Dochi/Services/Tools/ToolRegistry.swift`의 enable TTL 구조

## 4) 리스크와 대응

### 리스크: 기능 공백

- 대응: 채널별 최소 기능 계약 정의 후 단계별 이행

### 리스크: 권한 UX 혼선

- 대응: 승인 UI 단일 컴포넌트화

### 리스크: 런타임 장애

- 대응: watchdog + session recover 설계 선적용

### 리스크: 컨텍스트 품질 저하

- 대응: 회귀 평가셋 구축, 단계별 비교

## 5) 즉시 착수 작업 (Kickoff Backlog)

1. Runtime sidecar 프로젝트 생성
2. Bridge protocol schema 파일 작성
3. Session ID mapping 저장소 도입
4. Approval UI 컴포넌트 스켈레톤 구현
5. Hook 이벤트 로그 스키마 정의
