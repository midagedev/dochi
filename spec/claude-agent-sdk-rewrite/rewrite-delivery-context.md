# Rewrite Delivery Context (Claude Agent SDK)

기준일: 2026-02-19  
대상: Dochi 전면 리라이트 (Claude Agent SDK 중심)

## 1) 목적

이 문서는 아래를 하나로 묶은 실행 컨텍스트다.

- 반드시 참고해야 할 스펙 문서
- 현재 리라이트 관련 GitHub 이슈
- 고품질 완료를 위한 작업/검증/운영 규칙

핵심 원칙:

1. 엔진 재구현 금지 (SDK 우선)
2. Dochi 고유 가치(컨텍스트/로컬 실행/권한 분리) 강화
3. 품질 게이트 통과 없이는 완료로 간주하지 않음

---

## 2) Source of Truth 우선순위

리라이트 작업 시 아래 순서로 문서를 본다.

1. `CONCEPT.md`
2. `spec/claude-agent-sdk-rewrite/README.md`
3. `spec/claude-agent-sdk-rewrite/09-implementation-roadmap.md`
4. `spec/claude-agent-sdk-rewrite/04-runtime-bridge-design.md`
5. `spec/claude-agent-sdk-rewrite/05-context-and-memory-architecture.md`
6. `spec/claude-agent-sdk-rewrite/07-tools-permissions-hooks.md`
7. `spec/claude-agent-sdk-rewrite/10-testing-observability-operations.md`
8. `spec/execution-context.md` (기존 제품 전반 컨텍스트와 충돌 여부 확인용)

보조 문서:

- `spec/security.md`
- `spec/flows.md`
- `spec/states.md`
- `spec/tools.md`

---

## 3) GitHub Issue 맵 (Rewrite Program)

리라이트 트랙 핵심 이슈:

- [#281](https://github.com/midagedev/dochi/issues/281) Phase 0: Runtime Sidecar
- [#282](https://github.com/midagedev/dochi/issues/282) Phase 1: Bridge Schema + Session Mapping
- [#283](https://github.com/midagedev/dochi/issues/283) Phase 1: Session Streaming Integration
- [#284](https://github.com/midagedev/dochi/issues/284) Phase 2: Local Tool Dispatch Bridge
- [#285](https://github.com/midagedev/dochi/issues/285) Phase 2: Permission Gate + Approval UX
- [#286](https://github.com/midagedev/dochi/issues/286) Phase 2: Hook Pipeline + Audit Schema
- [#287](https://github.com/midagedev/dochi/issues/287) Phase 3: ContextSnapshot Builder
- [#288](https://github.com/midagedev/dochi/issues/288) Phase 3: Memory Pipeline + Projection
- [#289](https://github.com/midagedev/dochi/issues/289) Phase 3: Agent Definition v2
- [#290](https://github.com/midagedev/dochi/issues/290) Phase 4: Lease Routing
- [#291](https://github.com/midagedev/dochi/issues/291) Phase 4: Cross-device Resume
- [#292](https://github.com/midagedev/dochi/issues/292) Phase 5: Test/E2E/SLO Gates
- [#293](https://github.com/midagedev/dochi/issues/293) Phase 5: Legacy Engine Removal

관련 실험 이슈:

- [#280](https://github.com/midagedev/dochi/issues/280) Shadow planner 실험 (리라이트 중에도 측정/관측 자산 활용)

---

## 4) 권장 실행 순서 (의존 관계)

강제 선행:

1. #281 -> #282 -> #283
2. #283 -> #284 -> #285 -> #286
3. #286 -> #287 -> #288 -> #289
4. #289 -> #290 -> #291
5. #291 -> #292 -> #293

병렬 가능:

- #287, #289 일부 스키마 작업
- #292의 테스트 하네스 초안은 #284 이후부터 점진 구축 가능

금지:

- #281~#286 완료 전 #293(레거시 삭제) 착수
- 승인 UX(#285) 없이 restricted 도구 실서비스 경로 활성화

---

## 5) 고품질 완료를 위한 Quality Bar

## A. 설계 품질

각 이슈 PR은 다음을 명시해야 한다.

1. 어떤 문서 조항을 구현했는지
2. 어떤 문서 조항을 의도적으로 미뤘는지
3. 남은 리스크와 차단 조건

필수 섹션:

- `Spec Impact`
- `Out of Scope`
- `Risk & Rollback`

## B. 코드 품질

필수 규칙:

1. 앱 레이어에서 custom tool loop 신규 작성 금지
2. 권한 판정은 단일 경로(canUseTool + approval) 유지
3. 로그는 구조화(JSON/event envelope)로 남김
4. 세션/툴/승인 흐름은 traceId로 연결

## C. 테스트 품질

각 이슈 최소 테스트:

1. unit 2개 이상 (정상/실패)
2. integration 1개 이상 (브리지 왕복 또는 상태 전이)
3. 리그레션 1개 이상 (기존 동작 보존 또는 의도된 변경 고정)

하드 게이트:

- `xcodebuild ... test` 통과
- 새로운 runtime path smoke 테스트 통과
- 해당 이슈 수용 기준 체크리스트 100% 체크

## D. 운영 품질

필수 관측 항목:

1. session lifecycle 이벤트
2. tool decision 이벤트
3. approval 이벤트
4. 오류 코드 표준화

이 4개 중 하나라도 빠지면 완료 처리 금지.

---

## 6) 이슈 단위 작업 루프 (권장)

1. 이슈 시작
2. 관련 문서 조항 링크 정리
3. 최소 설계 메모(5~10줄)
4. 구현
5. 테스트(단위/통합/스모크)
6. 로그/메트릭 확인
7. PR 작성 + Spec Impact
8. 머지 후 다음 이슈로 진행

각 이슈는 1개의 명확한 실패 모드까지 반드시 검증한다.

---

## 7) 단계별 완료 정의 (DoD)

## Phase 0~1 완료 정의

- runtime initialize/health/session open-run-close가 안정 동작
- SDK 세션 스트리밍이 기본 채팅 경로를 대체

## Phase 2 완료 정의

- local tool dispatch + approval + hook 파이프라인이 연결됨
- sensitive/restricted 무승인 실행 0건

## Phase 3 완료 정의

- 4계층 컨텍스트 스냅샷 주입
- 메모리 파이프라인이 레이어 경계 위반 없이 동작

## Phase 4 완료 정의

- lease 기반 디바이스 라우팅
- cross-device resume 성공률 목표치 달성

## Phase 5 완료 정의

- 회귀 평가/통합/E2E/SLO 게이트 자동화
- legacy 엔진 경로 0%

---

## 8) 위험요소와 대응 규칙

주요 위험:

1. 엔진 이중화 (legacy + sdk)
2. 권한 경로 분기
3. 컨텍스트 경계 누수
4. 디버깅 불가능한 이벤트 누락

대응:

1. feature flag는 전환용으로만 사용하고 영구 공존 금지
2. approval 경로를 단일 UI/단일 API로 통합
3. 개인/워크스페이스 메모리 분리 테스트를 필수화
4. 이벤트 스키마 계약 테스트 추가

---

## 9) PR 템플릿 체크리스트 (리라이트 전용)

- [ ] 관련 이슈 번호 연결
- [ ] 구현한 스펙 문서 링크
- [ ] 미구현 스펙 항목 명시
- [ ] 테스트 실행 커맨드/결과 첨부
- [ ] 로그/메트릭 스냅샷 첨부
- [ ] 롤백 방법 명시

---

## 10) 최종 완료 조건 (Program Exit Criteria)

아래 6개를 모두 만족하면 리라이트 완료로 판단한다.

1. #281~#293 모두 close
2. 레거시 엔진 경로 제거 완료
3. 컨셉 시나리오(가정/개발/메신저) E2E 통과
4. 권한/보안 회귀 없음
5. SLO 게이트 충족
6. 운영자가 trace/log만으로 장애 재현 가능

---

## 11) 업데이트 규칙

- 이 문서는 리라이트 진행 중 주간 1회 업데이트한다.
- 이슈 추가/변경 시 3번 섹션(이슈 맵)을 즉시 갱신한다.
- 품질 기준 변경 시 5번/10번 섹션을 우선 갱신한다.

