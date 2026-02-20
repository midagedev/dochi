# UX 기획: Runtime Sidecar 상태 표시 및 사용자 경험

> Issue #281 · Phase 0 — Agent Runtime Sidecar UX 설계

## 1. 개요

Claude Agent SDK 런타임(TypeScript sidecar)의 상태를 사용자에게 어떻게 보여줄지 정의한다.
기존 앱의 SystemHealthBarView, Banner, Settings 패턴을 그대로 확장하여 일관된 UX를 유지한다.

## 2. 런타임 상태 모델

`RuntimeStatus` enum (새로 정의):

| 상태 | 설명 | 진입 조건 |
|---|---|---|
| `notStarted` | 런타임 프로세스 미실행 | 앱 최초 기동, 또는 명시적 중지 |
| `starting` | 프로세스 실행 중 + initialize RPC 대기 | 앱 시작 시 자동 |
| `ready` | runtime.ready 이벤트 수신 완료 | initialize 성공 |
| `degraded` | 이벤트 스트림 단절, 프로세스는 생존 추정 | 이벤트 수신 중단 감지 |
| `recovering` | 프로세스 종료 감지 → 자동 재시작 시도 중 | 프로세스 exit/crash |
| `error` | 재시작 실패 (최대 재시도 초과) | backoff 소진 |

## 3. UI 배치

### 3.1 SystemHealthBarView — 런타임 인디케이터 (항상 표시)

기존 SystemHealthBarView에 **모델 인디케이터 좌측**에 런타임 상태 인디케이터를 추가한다.
런타임은 모든 AI 기능의 기반이므로, 가장 왼쪽(= 가장 중요한 위치)에 배치한다.

```
[ ● 런타임 | cpu 모델명 ▾ | ● 동기화 | ♥ 3분 전 | # 1.2K 토큰 ]
```

**상태→시각 매핑:**

| RuntimeStatus | 아이콘 | 색상 | 텍스트 | 비고 |
|---|---|---|---|---|
| `notStarted` | `circle.slash` | `.secondary` | `런타임 중지` | — |
| `starting` | `ProgressView` (spinning) | `.blue` | `런타임 시작 중...` | 0.4 스케일 스피너 |
| `ready` | `circle.fill` | `.green` | `런타임` | 기본 상태, 가장 조용한 표시 |
| `degraded` | `exclamationmark.circle.fill` | `.orange` | `런타임 불안정` | — |
| `recovering` | `ProgressView` (spinning) | `.orange` | `런타임 복구 중...` | — |
| `error` | `xmark.circle.fill` | `.red` | `런타임 오류` | — |

**인터랙션:** 클릭 시 `RuntimeStatusPopover` 표시 (3.3절 참조).

### 3.2 배너 (조건부 표시)

기존 `OfflineFallbackBannerView`, `TTSFallbackBannerView`와 동일한 패턴으로,
`ready`가 아닌 비정상 상태일 때 chatDetailView 상단에 배너를 표시한다.
배너는 StatusBarView 아래, SystemHealthBarView 아래에 위치한다 (기존 배너들과 동일 레벨).

#### 3.2.1 RuntimeStartingBannerView (`starting` 상태)

앱 시작 직후 런타임이 준비되기까지 표시. **1초 지연** 후 표시하여 빠른 시작 시 깜빡임 방지.

```
┌──────────────────────────────────────────────────────────────┐
│ ⟳  AI 런타임을 시작하고 있습니다...                              │
│    잠시만 기다려주세요. 대화 기록은 바로 확인할 수 있습니다.          │
└──────────────────────────────────────────────────────────────┘
```

- 배경: `Color.blue.opacity(0.08)`
- 아이콘: `ProgressView` (scaleEffect 0.6) + 텍스트
- 사용자 액션: 없음 (자동 해제)
- `ready` 전이 시 `withAnimation(.easeOut(duration: 0.3))` 사라짐

#### 3.2.2 RuntimeDegradedBannerView (`degraded` 상태)

```
┌──────────────────────────────────────────────────────────────┐
│ ⚠ AI 런타임 연결이 불안정합니다.                                  │
│   자동 복구를 시도 중이며, 일부 기능이 지연될 수 있습니다.            │
│                                               [재연결 시도]    │
└──────────────────────────────────────────────────────────────┘
```

- 배경: `Color.orange.opacity(0.08)`
- 아이콘: `exclamationmark.triangle.fill` (`.orange`)
- 버튼: "재연결 시도" (`.bordered`, `.controlSize(.small)`)
- `ready` 전이 시 자동 해제

#### 3.2.3 RuntimeRecoveringBannerView (`recovering` 상태)

```
┌──────────────────────────────────────────────────────────────┐
│ ⟳  AI 런타임이 재시작 중입니다... (시도 2/5)                      │
│    진행 중이던 요청은 자동 재시도됩니다.                             │
└──────────────────────────────────────────────────────────────┘
```

- 배경: `Color.orange.opacity(0.08)`
- 아이콘: `ProgressView` (scaleEffect 0.6)
- 텍스트에 재시도 횟수 표시: `(시도 {n}/{max})`
- `ready` 전이 시 자동 해제

#### 3.2.4 RuntimeErrorBannerView (`error` 상태)

```
┌──────────────────────────────────────────────────────────────┐
│ ✕  AI 런타임을 시작할 수 없습니다.                                │
│    {lastError 요약 메시지}                                     │
│                                   [설정 열기]  [다시 시작]       │
└──────────────────────────────────────────────────────────────┘
```

- 배경: `Color.red.opacity(0.08)`
- 아이콘: `xmark.circle.fill` (`.red`)
- 버튼 2개:
  - "설정 열기" — Settings > 런타임 섹션으로 이동
  - "다시 시작" (`.borderedProminent`, `.controlSize(.small)`) — 수동 재시작 트리거
- dismiss 불가 (오류 상태가 해결되어야 사라짐)

### 3.3 RuntimeStatusPopover (SystemHealthBar 인디케이터 클릭 시)

기존 `QuickModelPopoverView`와 동일한 팝오버 패턴.

```
┌─────────────────────────────────┐
│ AI 런타임                        │
│─────────────────────────────────│
│ 상태:   ● 실행 중                 │
│ 버전:   1.0.0                    │
│ 가동:   2시간 15분                │
│ 세션:   3개 활성                  │
│ 마지막 오류: 없음                  │
│─────────────────────────────────│
│ [재시작]         [설정 열기]       │
└─────────────────────────────────┘
```

**표시 항목:**

| 항목 | 소스 | 비고 |
|---|---|---|
| 상태 | `RuntimeStatus` | 색상 dot + 한국어 텍스트 |
| 버전 | `runtime.initialize` 응답의 `runtimeVersion` | — |
| 가동 시간 | `runtime.health` 응답의 `uptimeMs` → 상대 시간 표시 | — |
| 활성 세션 수 | `runtime.health` 응답의 `activeSessions` | — |
| 마지막 오류 | `runtime.health` 응답의 `lastError` | 없으면 "없음" 표시 |

**버튼:**
- "재시작" — 런타임 shutdown 후 재시작 (확인 알림 없이 즉시 실행)
- "설정 열기" — Settings > 런타임 섹션으로 딥링크

### 3.4 Settings — 런타임 섹션 (새 SettingsSection 추가)

`SettingsSection` enum에 `.runtime` 케이스 추가:

```swift
case runtime = "runtime"  // title: "런타임", icon: "server.rack", group: .development
```

**설정 화면 구성:**

```
┌─ 런타임 설정 ──────────────────────────────────────────────┐
│                                                            │
│ 상태                                                        │
│ ┌────────────────────────────────────────────────────────┐ │
│ │  ● 실행 중   ·   버전 1.0.0   ·   가동 2시간 15분        │ │
│ │  활성 세션: 3개   ·   마지막 오류: 없음                    │ │
│ │                                        [재시작]          │ │
│ └────────────────────────────────────────────────────────┘ │
│                                                            │
│ 자동 시작                                                    │
│  [✓] 앱 시작 시 런타임 자동 실행                               │
│                                                            │
│ 복구 정책                                                    │
│  최대 재시도 횟수:  [ 5 ▾ ]                                   │
│  재시작 대기 시간:  지수 백오프 (1s → 2s → 4s → ...)           │
│                                                            │
│ 진단                                                        │
│  런타임 로그 위치: ~/Library/Logs/Dochi/runtime.log            │
│  [로그 파일 열기]  [로그 폴더 열기]                              │
│                                                            │
│ 고급                                                        │
│  런타임 실행 경로: /path/to/dochi-agent-runtime                │
│  소켓 경로: /tmp/dochi-runtime.sock                           │
│  [런타임 재설치]                                               │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**설정 항목:**

| 항목 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `runtimeAutoStart` | `Bool` | `true` | 앱 시작 시 자동 실행 |
| `runtimeMaxRetries` | `Int` | `5` | 자동 재시작 최대 시도 횟수 |
| `runtimeLogLevel` | `String` | `"info"` | 런타임 로그 레벨 |

## 4. 앱 시작 시 UX 흐름 (Startup Flow)

```
앱 실행
  │
  ├─→ UI 즉시 표시 (사이드바, 대화 목록, 설정 — 모두 사용 가능)
  │
  ├─→ SystemHealthBar: [⟳ 런타임 시작 중... | cpu 모델명 ▾ | ...]
  │
  ├─→ (1초 경과 후, 아직 starting이면)
  │    └─→ RuntimeStartingBanner 표시
  │
  ├─→ runtime.ready 이벤트 수신
  │    ├─→ SystemHealthBar: [● 런타임 | cpu 모델명 ▾ | ...]
  │    ├─→ RuntimeStartingBanner 사라짐 (fade out 0.3s)
  │    └─→ 입력바 완전 활성화 (전송 버튼 활성)
  │
  └─→ (실패 시)
       ├─→ recovering 상태 → RuntimeRecoveringBanner 표시
       └─→ error 상태 → RuntimeErrorBanner 표시
```

**핵심 원칙:**
- UI는 런타임 준비를 기다리지 않고 즉시 표시한다.
- 사용자는 대화 목록 탐색, 설정 변경 등을 런타임 시작 전에도 할 수 있다.
- 메시지 전송만 런타임 `ready` 상태에서 가능하다.
- `starting` 상태에서 전송 버튼은 비활성이되, 입력 필드에는 타이핑 가능하다.

## 5. 런타임 장애/복구 UX 흐름

### 5.1 런타임 프로세스 크래시

```
ready 상태에서 사용 중
  │
  ├─→ 프로세스 종료 감지
  │    ├─→ SystemHealthBar: [⟳ 런타임 복구 중... | ...]
  │    ├─→ RuntimeRecoveringBanner 표시 ("시도 1/5")
  │    └─→ 진행 중이던 요청이 있었다면 → 대화에 시스템 메시지 삽입:
  │         "⚠ AI 런타임이 재시작되었습니다. 마지막 요청을 다시 시도합니다."
  │
  ├─→ 재시작 성공 (resume)
  │    ├─→ SystemHealthBar: [● 런타임 | ...] (green dot)
  │    ├─→ RuntimeRecoveringBanner 사라짐
  │    └─→ 중단된 요청 자동 재시도
  │
  └─→ 재시작 실패 (max retries 초과)
       ├─→ SystemHealthBar: [✕ 런타임 오류 | ...] (red)
       ├─→ RuntimeErrorBanner 표시
       └─→ 사용자 수동 개입 필요
```

### 5.2 브리지 연결 단절 (프로세스 생존)

```
ready 상태에서 사용 중
  │
  ├─→ 이벤트 스트림 끊김 감지
  │    ├─→ SystemHealthBar: [⚠ 런타임 불안정 | ...] (orange)
  │    ├─→ RuntimeDegradedBanner 표시
  │    └─→ 요청은 타임아웃까지 대기 후 실패 처리
  │
  ├─→ 재연결 성공
  │    ├─→ SystemHealthBar: [● 런타임 | ...] (green dot)
  │    └─→ RuntimeDegradedBanner 사라짐
  │
  └─→ 재연결 실패 → recovering으로 전이
```

## 6. 입력바 연동

`InputBarView`의 전송 가능 조건에 런타임 상태 검사를 추가한다.

```swift
// 기존
private var canSend: Bool {
    viewModel.interactionState == .idle &&
    (!viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
     || !viewModel.pendingImages.isEmpty)
}

// 변경
private var canSend: Bool {
    viewModel.interactionState == .idle &&
    viewModel.runtimeStatus == .ready &&   // ← 추가
    (!viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
     || !viewModel.pendingImages.isEmpty)
}
```

**전송 버튼 상태:**
- `runtimeStatus != .ready` 일 때: 전송 버튼 비활성 (`.secondary.opacity(0.3)` 색상)
- 플레이스홀더 텍스트는 그대로 유지 (타이핑은 허용)
- 툴팁 변경: "런타임 준비 중... 잠시 후 전송할 수 있습니다"

## 7. 시스템 메시지

런타임 상태 변경 시 대화에 삽입할 시스템 메시지 (Korean):

| 이벤트 | 메시지 |
|---|---|
| 복구 성공 (대화 중) | "AI 런타임이 복구되었습니다. 이전 요청을 다시 시도합니다." |
| 복구 성공 (요청 없음) | — (시스템 메시지 없음, 배너만 해제) |
| 복구 실패 | "AI 런타임을 시작할 수 없습니다. 설정에서 상태를 확인해주세요." |
| resume 실패 → 새 세션 | "이전 세션을 복구할 수 없어 새 세션으로 시작합니다." |

## 8. 애니메이션/전환 사양

| 전환 | 애니메이션 | 지속 시간 |
|---|---|---|
| 배너 표시 | `.transition(.move(edge: .top).combined(with: .opacity))` | 0.3s |
| 배너 해제 | `.transition(.opacity)` + `withAnimation(.easeOut)` | 0.3s |
| 상태 아이콘 변경 | `.animation(.easeInOut, value: runtimeStatus)` | 0.2s |
| 색상 전환 | `.animation(.easeInOut(duration: 0.3), value: runtimeStatus)` | 0.3s |
| Starting 배너 지연 | 1초 `Task.sleep` 후 표시 | — |
| Ready 전이 후 green dot | 2초간 pulse 효과 (`scaleEffect` 1.0→1.3→1.0) | 0.6s × 2회 |

## 9. 접근성 (Accessibility)

- 모든 인디케이터에 `.accessibilityLabel` 제공
  - 예: "AI 런타임 상태: 실행 중"
  - 예: "AI 런타임 상태: 오류 — 설정에서 확인 필요"
- VoiceOver 공지: 상태 변경 시 `.accessibilityAnnouncement` 사용
  - `ready`: "AI 런타임이 준비되었습니다"
  - `error`: "AI 런타임 오류가 발생했습니다"
- 배너의 버튼에 `.accessibilityHint` 제공

## 10. 구현 컴포넌트 목록

| 컴포넌트 | 파일 (신규/수정) | 설명 |
|---|---|---|
| `RuntimeStatus` enum | `Dochi/State/RuntimeStatus.swift` (신규) | 6가지 런타임 상태 |
| `RuntimeStatusIndicatorView` | `Dochi/Views/RuntimeStatusIndicatorView.swift` (신규) | SystemHealthBar 내 인디케이터 |
| `RuntimeStatusPopoverView` | `Dochi/Views/RuntimeStatusPopoverView.swift` (신규) | 인디케이터 클릭 시 팝오버 |
| `RuntimeStartingBannerView` | `Dochi/Views/RuntimeBannerViews.swift` (신규) | starting 배너 |
| `RuntimeDegradedBannerView` | 위 파일에 포함 | degraded 배너 |
| `RuntimeRecoveringBannerView` | 위 파일에 포함 | recovering 배너 |
| `RuntimeErrorBannerView` | 위 파일에 포함 | error 배너 |
| `RuntimeSettingsView` | `Dochi/Views/Settings/RuntimeSettingsView.swift` (신규) | 설정 탭 뷰 |
| `SystemHealthBarView` | 수정 | 런타임 인디케이터 슬롯 추가 |
| `ContentView` | 수정 | 배너 + 팝오버 상태 변수 추가 |
| `DochiViewModel` | 수정 | `runtimeStatus` 프로퍼티 + 재시작 메서드 |
| `SettingsSection` | 수정 | `.runtime` 케이스 추가 |
| `SettingsView` | 수정 | RuntimeSettingsView 라우팅 |
| `InputBarView` (ContentView 내) | 수정 | `canSend` 조건 추가 |
| `AppSettings` | 수정 | `runtimeAutoStart`, `runtimeMaxRetries` 프로퍼티 |

## 11. 설계 결정 근거

1. **SystemHealthBar에 통합**: 새로운 UI 영역을 만들지 않고, 기존 패턴(모델/동기화/하트비트)에 통합하여 학습 부담 제거.
2. **배너 패턴 재사용**: OfflineFallbackBanner, TTSFallbackBanner와 동일한 레이아웃/색상 체계로 일관성 유지.
3. **UI 비차단 시작**: 런타임 준비 중에도 UI를 표시하여, 사용자가 대화 기록이나 설정을 즉시 활용 가능.
4. **1초 지연 배너**: 대부분 1초 이내 시작 완료 예상 → 불필요한 배너 깜빡임 방지.
5. **Settings 별도 섹션**: 런타임은 독립 프로세스이므로 전용 관리 화면이 필요. 기존 "개발" 그룹(터미널, 외부 도구)에 배치.
6. **수동 재시작 제공**: 자동 복구가 실패해도 사용자가 직접 제어할 수 있는 탈출구 보장.
