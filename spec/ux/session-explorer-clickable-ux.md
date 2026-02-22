# UX 기획: Session Explorer Clickable UX

> Issue #444
> 작성일: 2026-02-22

## 1. 목표

`도구 > 세션 탐색기`에서 사용자가 "지금 어떤 코딩 에이전트가 무슨 작업을 하는지"를 한눈에 파악하고,
1~2 클릭 안에 상세 확인/조치까지 이어지도록 상호작용을 재설계한다.

핵심 원칙:
- 상태만 보여주지 말고 행동 가능한 단서(`현재 작업`, `업데이트 시각`, `다음 액션`)를 같이 보여준다.
- 클릭 가능한 영역은 시각적으로 분명해야 한다.
- 기존 구성(Repo Dashboard / Repo Session Explorer / Dashboard Detail)을 크게 흔들지 않고 강화한다.

## 2. 현재 문제

- Repo 카드/세션 행이 사실상 "정보 텍스트"로 보이며, 클릭 후 기대 동작이 약하다.
- 선택 상태와 상세 진입 상태가 연결되지 않아 사용자가 흐름을 잃는다.
- "세션 확인 → 상세 출력 보기"가 메뉴 탐색에 의존한다.

## 3. 정보 우선순위

세션 정보 노출 우선순위:
1. `현재 작업` (요약 1줄)
2. `상태 + freshness` (active/idle/stale/dead, 몇 초/분 전)
3. `식별자` (provider/session id)
4. `컨텍스트` (repo/branch/path)

Repo 카드 우선순위:
1. `활성도 배지`
2. `활성 세션 수 + 오류 수`
3. `대표 현재 작업`(해당 repo의 최고 우선 세션 1개)

## 4. 클릭 인터랙션 정의

| 요소 | 기본 클릭 | 보조 클릭/액션 | 시각 규칙 |
|---|---|---|---|
| Repo Dashboard 카드 | repo 필터 적용 + 그룹 자동 확장 + 대표 세션 포커스 | 우측 `...` 메뉴 유지 | hover 배경 강조 + pointer |
| Repo 그룹 헤더(텍스트 영역) | 대표 세션 선택(가능 시) | chevron 버튼은 접기/펼치기 전용 | 선택 시 배경/보더 강조 |
| Repo 그룹 chevron | 접기/펼치기만 수행 | 없음 | 현재 아이콘 유지 |
| Session Row (runtime 세션) | 우측 상세 패널로 진입 | 우측 `...` 메뉴 유지 | hover 배경 + 선택 하이라이트 |
| Session Row (file-only 세션) | 해당 세션 검색/필터 적용 + 히스토리/상태 영역 포커스 | 우측 `...` 메뉴 유지 | hover 배경 + 상태 설명 툴팁 |
| "상세 보기" CTA (선택) | 가능한 경우 즉시 상세 패널 이동 | 실패 시 안내 토스트 | 버튼형 affordance |

## 5. 상태별 표시 규칙

- `active`: 색상 강도 높음, 현재 작업 1줄 기본 노출
- `idle`: 현재 작업 노출 유지, 색상 강도 중간
- `stale`: 현재 작업 텍스트를 희미 처리, freshness 강조
- `dead`: 클릭 시 상세 진입 대신 "종료된 세션" 상태 안내 + 재시작 액션 제안

## 6. 사용자 여정

### 여정 A: 지금 작업 중인 세션 빠르게 확인
1. 사용자가 Repo Dashboard 카드 클릭
2. 해당 repo로 필터 전환 + 그룹 확장
3. 대표 active 세션이 선택되고 우측 상세 대시보드 표시
4. 필요 시 바로 `중단/재시작/터미널 열기`

### 여정 B: unassigned 세션 연결
1. 사용자가 Unassigned Queue에서 세션 확인
2. 세션 행 클릭으로 컨텍스트 정보 확인
3. `레포 연결` 액션 실행
4. 매핑 후 해당 repo 그룹으로 이동/하이라이트

### 여정 C: stale 세션 재확인
1. stale 뱃지가 보이는 세션 행 클릭
2. 최신 출력 미리보기/업데이트 시각 확인
3. 필요 시 `상태` 또는 `요약` 액션 실행
4. 필요하면 재시작 또는 attach 선택

## 7. 좁은 폭 대응

- 리스트 폭이 좁을 때는 `현재 작업` 1줄 + 상태/freshness만 유지하고 경로는 축약.
- 보조 텍스트(예: runtime/source/tier)는 두 번째 줄 또는 툴팁으로 전환.

## 8. 접근성

- 모든 클릭 영역에 명시적 접근성 라벨 부여:
  - 예: "Repo 카드 <name>, 활성 세션 N개, 클릭하여 세션 보기"
  - 예: "세션 <provider/id>, 상태 <state>, 클릭하여 상세 열기"
- 키보드 포커스 이동 순서:
  1) Repo 카드들
  2) 그룹 헤더
  3) 세션 행
  4) 행 내 액션 메뉴
- Enter/Space로 기본 클릭 동작 수행 가능해야 한다.

## 9. 구현 가이드 (컴포넌트 단위)

- `ExternalToolListView`
  - `repoDashboardSection`: 카드에 탭 제스처 + 선택/필터 반영
  - `repositoryGroupRow`: 헤더 영역 클릭과 chevron 클릭 분리
  - `unifiedSessionRow`: 행 클릭 시 세션 선택 콜백 연결
- `ContentView`
  - `selectedToolSessionId` 반영 시 우측 `ExternalToolDashboardView` 진입 보장
- `SessionExplorerViewStateBuilder`
  - 대표 세션 계산 로직(우선순위: active > idle > stale > dead, updatedAt desc)

## 10. 완료 기준

- 클릭 가능한 요소별 동작이 구현과 1:1 매핑된다.
- 사용자 여정 A/B/C가 실제 동작으로 재현된다.
- "현재 작업"을 포함한 세션 컨텍스트가 클릭 전/후 모두 인지 가능하다.
