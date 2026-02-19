# Dochi Capability-First Tool Architecture (V2)

상태: Proposed (구조 전환안)  
작성: 2026-02-19  
대상 릴리즈: 2026-Q1~Q2  
관련 문서:
- [product-spec.md](./product-spec.md)
- [tools.md](./tools.md)
- [flows.md](./flows.md)
- [project-context-proactive-ux.md](./project-context-proactive-ux.md)

---

## 1) 문서 목적

기존의 `tools.list/tools.enable` 중심 구조를 유지하는 선에서 최적화하지 않고,  
Dochi의 제품 컨셉(워크스페이스/에이전트/프로젝트 기반, 로컬 우선, 디바이스 투명성, 맥락 지속)에 맞는 **목표 아키텍처**로 전면 전환한다.

이 문서는 아래를 정의한다.
- 왜 기존 구조를 폐기하는지
- 어떤 런타임 모델로 바꿀지
- UX에 어떻게 자연스럽게 녹일지
- 어떤 순서로 안전하게 마이그레이션할지

---

## 2) 기존 구조 폐기 결정

## 2.1 기존 구조 요약
- LLM이 `tools.list`로 목록을 조회
- 필요 시 `tools.enable`로 도구를 동적으로 활성화
- 활성화 결과를 보고 다시 도구 선택

## 2.2 구조적 한계
- 모델이 준비 동작(`list/enable`)에 호출 예산을 소모하고 실제 작업 도구 호출을 못하는 루프가 발생한다.
- 매 턴 도구 노출셋이 변동되어 프롬프트 prefix 안정성이 낮아진다.
- 워크스페이스/에이전트/채널 권한 정책을 모델 추론에 과도하게 위임한다.
- 사용자에게는 “무엇을 하려는지”보다 “도구 협상”이 먼저 드러나 UX가 부자연스럽다.

## 2.3 제품 컨셉과의 불일치
- Dochi는 기능 자체보다 **현재 맥락(workspace/project/agent)**이 우선이다.
- Dochi는 사용자가 디바이스를 의식하지 않아야 하므로, “어느 Mac에서 실행할지”도 런타임이 결정해야 한다.
- 모델이 도구를 탐색하는 방식은 컨텍스트 중심 UX와 충돌한다.
- 따라서 도구 활성화는 모델 책임이 아니라 **서버 책임**이어야 한다.

---

## 3) 목표 원칙

1. Capability First  
도구 단위가 아니라 사용자 과업 단위(Capability)로 라우팅한다.

2. Context Decides  
`workspace + project + branch + agent + channel`이 허용 Capability를 결정한다.

3. Stable Prefix  
도구 스키마는 고정 묶음으로 제공하고 턴별 변동을 최소화한다.

4. Bounded Execution  
도구 호출은 예산/반복/시간 제한이 있는 상태기계로 실행한다.

5. UX Transparency  
“도구 이름”보다 “지금 어떤 작업 모드인지”를 사용자에게 노출한다.

6. Local-First Safety  
민감/위험 동작은 로컬 확인을 기본값으로 하고 원격 채널은 보수적으로 제한한다.

7. Device Transparency  
사용자는 목적만 말하고, 실행 디바이스 선택은 시스템이 담당한다.

---

## 4) 목표 아키텍처 (전면 교체)

## 4.1 런타임 구성

1. Context Snapshot Builder  
- 현재 세션에서 `workspace/project/branch/agent/channel/interaction state`를 정규화한다.

2. Intent + Task Classifier  
- 입력을 `작업 타입`으로 분류한다. 예: `chat`, `calendar`, `coding.review`, `coding.change`, `web.research`, `ops`.

3. Capability Router  
- 분류 결과와 컨텍스트를 기반으로 `Primary Capability 1개 + Secondary Capability 최대 1개`를 선택한다.

4. Policy Engine  
- 워크스페이스 정책, 에이전트 권한, 채널 제약(Desktop/Voice/Telegram)으로 도구 허용셋을 필터링한다.

5. Device Execution Router
- `local peer first`로 실행 디바이스를 선택한다.
- 로컬 불가 시 동일 워크스페이스의 다른 피어로 failover한다.
- 선택 기준: capability 지원 여부, 권한, 최근 헬스/가용성, latency.

6. Tool Menu Compiler  
- 최종 `allowed_tools`를 컴파일한다.
- hard limit: 턴당 최대 12개 도구.

7. Execution Loop Controller  
- 계획/실행/반성 단계를 제한된 루프로 수행한다.
- 루프 한도: Desktop Text 6회, Voice 3회, Telegram 2회.

8. Observation & Memory Writer  
- 도구 결과와 실패 원인을 구조화 이벤트로 저장하고, 필요한 경우 memory update로 반영한다.

## 4.2 핵심 전환 포인트

- 모델 노출 카탈로그에서 `tools.list`, `tools.enable`, `tools.enable_ttl`, `tools.reset` 제거
- 모델은 매 턴 고정된 `allowed_tools`만 본다.
- 도구 선택 실패 시 “도구 재협상”이 아니라 “질문/설명/대체 행동”으로 복구한다.

## 4.3 피어 디바이스 실행 규칙
- 실행은 항상 디바이스에서 수행한다. 클라우드는 동기화/큐/메타데이터만 담당한다.
- 텔레그램 요청은 사용자가 지정한 워크스페이스의 대표 피어(예: 집 Mac)를 1순위로 시도한다.
- 대표 피어가 오프라인이면 동일 워크스페이스의 대체 피어로 라우팅하고, 모두 불가하면 지연/실패를 사용자에게 명확히 알린다.
- 디바이스 라우팅 결과(선택/실패 사유)는 Activity Timeline에 기록한다.

---

## 5) Capability Pack 설계

도구는 유지하되, 런타임 노출 단위를 아래 Capability Pack으로 재구성한다.

### 5.1 Pack 카탈로그 (v2)

1. `cap.chat.core`
- 목적: 일반 질의, 요약, 간단 계산/시간 조회, 앱 안내
- 기본 도구: `calculate`, `datetime`, `app.guide`

2. `cap.memory.personal`
- 목적: 사용자/워크스페이스 기억 저장 및 수정
- 기본 도구: `save_memory`, `update_memory`, `set_current_user`

3. `cap.personal.organizer`
- 목적: 일정/미리알림/알람 중심 개인 생산성
- 기본 도구: `create_reminder`, `list_reminders`, `complete_reminder`, `set_alarm`, `list_alarms`, `cancel_alarm`, `calendar.list_events`

4. `cap.personal.calendar-write`
- 목적: 캘린더 쓰기(민감)
- 기본 도구: `calendar.create_event`, `calendar.delete_event`

5. `cap.coding.read`
- 목적: 저장소 읽기/검토
- 기본 도구: `git.status`, `git.log`, `git.diff`, `coding.review`

6. `cap.coding.write`
- 목적: 코드/저장소 변경(제한)
- 기본 도구: `coding.run_task`, `git.commit`, `git.branch`

7. `cap.web.research`
- 목적: 웹 탐색/외부 검색
- 기본 도구: `web_search`, `open_url`

8. `cap.workspace.admin`
- 목적: 워크스페이스/에이전트/설정 관리
- 기본 도구: `workspace.*`, `agent.*`, `settings.*`, `context.update_base_system_prompt`

9. `cap.integration.telegram`
- 목적: 텔레그램 통합 관리
- 기본 도구: `telegram.enable`, `telegram.set_token`, `telegram.get_me`, `telegram.send_message`

10. `cap.device.actions`
- 목적: 로컬 디바이스 상호작용
- 기본 도구: `clipboard.*`, `finder.*`, `music.*`, `contacts.*`, `print_image`, `generate_image`

### 5.2 Pack 조합 규칙

- 기본: Primary 1개
- 복합 질의: Secondary 1개까지 허용
- 금지 조합: `cap.workspace.admin + cap.coding.write` (사고 반경 과대)
- `cap.coding.write`, `cap.personal.calendar-write`는 단독 또는 `cap.chat.core`만 병행 가능

---

## 6) 정책 모델 (Policy Engine)

## 6.1 입력 축
- Workspace policy: 허용 Capability/도구 allowlist
- Agent role policy: 페르소나별 금지 Capability
- Channel policy: Desktop Text / Voice / Telegram
- Device policy: 홈 허브 우선 여부, 디바이스별 허용 도구, 오프라인 폴백 규칙
- Interaction state policy: `processing`, `speaking`, `ending` 등 상태 기반 제한

## 6.2 위험도별 기본 정책

1. `safe`
- 자동 실행 가능

2. `sensitive`
- Desktop에서는 확인 UI 필요
- Telegram에서는 기본 거부(인앱 유도)

3. `restricted`
- 명시적 사용자 승인 + 프로젝트 컨텍스트 확인 필요
- Voice/Telegram에서는 기본 거부

## 6.3 정책 실패 처리
- 실패 사유를 구조화 코드로 반환한다. (`policy_denied`, `channel_blocked`, `confirmation_required`)
- 모델에는 동일 요청 재시도 대신 대체 경로를 선택하도록 안내한다.

---

## 7) 실행 상태기계 (Execution Loop Controller)

## 7.1 상태
- `plan` -> `act` -> `observe` -> `reflect` -> (`act` 반복 또는 `final`)

## 7.2 하드 가드레일
- 동일 도구+동일 인자 시그니처 2회 초과 금지
- 같은 실패 코드 2회 반복 시 즉시 종료
- turn wall-clock 20초 초과 시 안전 종료
- 도구 타임아웃은 개별 10초

## 7.3 종료 전략

1. 정상 종료
- 사용자 요청 충족 + 결과 요약

2. 제한 종료
- 예산/시간/정책 한도 도달 시 현재까지의 관찰결과와 다음 행동 제안 제공

3. 복구 종료
- “질문 1개”로 모호성 해소가 가능하면 Clarifying Question으로 전환

---

## 8) 프롬프트/컨텍스트 전략

## 8.1 고정 Prefix 구성

1. Base system prompt  
2. Agent persona  
3. Capability runtime instruction (고정 템플릿)  
4. Capability tool schemas (선택된 pack에 대한 정렬 고정)  

위 4개를 캐시 친화적으로 유지하고, 매 턴 바뀌는 항목은 아래로 내린다.
- 프로젝트/브랜치 상태
- 최근 대화
- 최신 툴 결과

## 8.2 모델 규칙
- 도구 탐색 시도 금지
- 허용 목록 밖 도구 요청 금지
- 불가 시 사유+대체안을 직접 설명

---

## 9) UX 통합 방식 (Dochi 컨셉 반영)

## 9.1 상단 컨텍스트 스트립
- `workspace / project / branch`와 함께 `활성 Capability` 칩 표시
- 예: `Coding Review`, `Calendar`, `Research`

## 9.2 실행 전 노출
- 입력 직후 “이번 요청은 X Capability로 처리합니다”를 짧게 노출

## 9.3 확인 UI
- sensitive/restricted 동작은 “무엇을 왜 실행하는지” 1문장으로 확인
- 승인/거부 선택은 프로젝트 단위로 단기 기억 가능

## 9.4 실행 후 리시트
- 어떤 액션이 실행됐는지 사용자 언어로 기록
- 도구명 대신 사용자 행동명 중심으로 표기

---

## 10) 디바이스 투명 실행 모델

1. Workspace-Aware Peer Selection
- 각 워크스페이스에 `preferred peer`를 둘 수 있다. (예: 가족 WS는 집 Mac)
- preferred peer가 가능하면 우선 사용, 아니면 건강한 peer로 자동 전환.

2. Agent-Aware Capability Gate
- 같은 워크스페이스라도 에이전트별 허용 Capability가 다르다.
- 예: `키키`는 `cap.coding.*`를 영구 차단, `코디`는 `cap.coding.*` 허용.

3. Execution Lease
- 동일 작업이 여러 피어에서 중복 실행되지 않도록 lease 기반으로 단일 실행 보장.
- lease 만료/충돌은 best-effort로 처리하고 결과는 사용자에게 투명하게 알린다.

4. Cloud Role Boundary
- 클라우드는 실행 엔진이 아니다.
- 역할은 인증/동기화/메시지 라우팅/상태 중계로 한정한다.

---

## 11) 채널별 운영 모드

1. Desktop Text
- Capability 전체 사용 가능 (정책 통과 전제)
- 최대 실행 루프 6

2. Voice
- 저위험, 짧은 작업 위주
- 최대 실행 루프 3
- 확인이 필요한 동작은 텍스트 확인으로 승격

3. Telegram
- `safe` 중심
- `sensitive/restricted` 기본 차단 + 인앱 이동 안내
- 최대 실행 루프 2

---

## 12) 관측성/지표

턴 단위로 아래를 저장한다.
- chosen capability pack(s)
- selected execution peer
- compiled tool count
- executed tool sequence
- guardrail trigger reason
- policy deny reason
- final outcome (`success`, `partial`, `failed`)

핵심 운영 지표:
- loop abort rate < 1%
- 평균 도구 호출 수 (채널별)
- peer failover rate
- policy deny 후 사용자 이탈률
- 첫 응답 레이턴시 p50/p95
- prompt token usage delta

---

## 13) 마이그레이션 계획

## Phase 0: 계측 선반영 (1주)
- 현재 구조에 루프/반복/토큰 지표를 먼저 심는다.

## Phase 1: Capability Registry 도입 (1주)
- Pack manifest + router + policy engine를 구현
- feature flag: `CAPABILITY_ROUTER_V2`

## Phase 2: Peer Execution Router 도입 (1주)
- preferred peer 선택 + 폴백 + lease 기록 구현

## Phase 3: 컴파일드 툴 메뉴 경로 추가 (1주)
- 기존 경로와 병렬 운영
- 내부 dogfood 사용자만 v2 경로 사용

## Phase 4: 실행 상태기계 교체 (1주)
- loop controller와 guardrail 이관

## Phase 5: UX 통합 (1주)
- Capability 칩, 확인 UI, 리시트 컴포넌트 반영

## Phase 6: 레거시 도구 협상 제거 (1~2 릴리즈)
- 모델 노출에서 `tools.list/enable` 제거
- 호환 shim은 내부 호출만 허용, 외부 모델에서는 차단

## Phase 7: 정식 전환
- `CAPABILITY_ROUTER_V2` 기본 ON
- 레거시 코드 삭제

---

## 14) 테스트 전략

1. Unit
- classifier/router/policy/guardrail 순수 로직 테스트

2. Integration
- 실제 tool registry와 pack compiler 연결 테스트

3. E2E
- 과거 loop 재현 시나리오를 회귀 케이스로 고정
- `<= 3`회 내 목표 도구 실행 성공 검증
- preferred peer 오프라인 상황에서 정상 failover 검증

4. UX test
- 확인 UI 노출 조건
- 채널별 차단/승격 규칙 검증

5. Perf
- 프롬프트 토큰량, 첫 응답 지연, 캐시 히트율 비교

---

## 15) 완료 기준 (Definition of Done)

- `tools.list/enable`가 모델 실행 경로에서 완전히 사라진다.
- 모든 턴이 Capability 기반 `allowed_tools`로 실행된다.
- 디바이스 선택이 사용자 요청 맥락(워크스페이스/에이전트)에 맞게 자동으로 동작한다.
- loop abort rate가 목표치(<1%)를 안정적으로 만족한다.
- Desktop/Voice/Telegram 정책 차이가 UX로 명확히 드러난다.
- 실패 시 사용자에게 “왜 안 되는지 + 다음에 무엇을 하면 되는지”가 항상 노출된다.

---

## 부록 A) 레거시 -> 신규 매핑

- Legacy `baseline + conditional enable` -> `capability pack compile`
- Legacy `tools.list` -> (삭제) router 결정 결과만 사용
- Legacy `tools.enable` -> (삭제) policy-filtered preselection
- Legacy `tool loop max 10` -> 채널별 예산(6/3/2) + 중복 방지

## 부록 B) 즉시 실행 항목

1. `spec/tools.md`를 Capability Pack 기준으로 재구성
2. `flows.md`의 Tool Invocation Flow를 새 상태기계로 갱신
3. `project-context-proactive-ux.md`에 Capability 칩/확인 UI 반영
4. feature flag와 지표 필드 명세를 tech spec에 추가
