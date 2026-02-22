# UX 명세: [K-4] 외부 AI 도구 세션 매니저

> 상태: 설계 완료
> 관련: TerminalService (K-1), HeartbeatService, DelegationManager (J-2), BuiltInToolService
> 이슈: #167
> 2026-02 레이아웃 업데이트: `spec/ux/k4-orchestration-console-layout.md` 참고

---

## 1. 개요

Claude Code, Codex CLI, aider 등 외부 AI 코딩 도구를 tmux 세션 기반으로 통합 관리하는 시스템. 도치 앱 하나에서 여러 외부 도구의 상태를 모니터링하고, 작업을 디스패치하며, 결과를 수집한다.

### 핵심 원칙
- **tmux 기반**: 각 외부 도구를 tmux 세션으로 운용. `send-keys`로 작업 전송, `capture-pane`으로 출력 캡처
- **프로파일 관리**: 도구별 실행 명령, 상태 감지 패턴, SSH 설정 등을 JSON 프로파일로 관리
- **헬스체크 통합**: HeartbeatService tick에서 등록된 세션의 상태를 주기적으로 점검
- **K-1 터미널과 분리**: K-1 TerminalService는 일반 셸 세션, K-4는 외부 AI 도구 전용 세션. UI/서비스 모두 별도

---

## 2. 외부 도구 상태 (ExternalToolStatus)

| 상태 | 의미 | 인디케이터 색상 |
|------|------|-----------------|
| `.idle` | 프롬프트 대기, 작업 할당 가능 | green |
| `.busy` | 작업 실행 중 | blue |
| `.waiting` | 사용자 입력/승인 대기 (`[Y/n]` 등) | orange |
| `.error` | 에러 감지 | red |
| `.dead` | 세션/프로세스 종료 | gray |
| `.unknown` | 초기 상태 또는 판별 불가 | gray (점멸) |

상태는 `tmux capture-pane` 출력을 프로파일에 정의된 정규식 패턴으로 매칭하여 판별.

---

## 3. 진입점 (Discoverability)

### 3-1. 사이드바 섹션 탭

현재 사이드바에 "대화 / 칸반" 탭이 있음. **"도구"** 탭을 추가:

```
사이드바 상단 섹션 피커:
[대화] [칸반] [도구]
```

"도구" 탭 선택 시 사이드바에 등록된 외부 도구 프로파일 목록 표시. 디테일 영역에는 선택한 도구의 대시보드 표시.

### 3-2. 설정

| 위치 | 그룹 "개발" → 새 섹션 "외부 도구" |
|------|------|
| SettingsSection | `.externalTool` (신규) |
| 그룹 | `.development` (terminal과 함께) |
| 파일 | `Views/Settings/ExternalToolSettingsView.swift` (신규) |

"개발" 그룹에 배치: K-1 터미널과 같은 개발 도구 범주.

### 3-3. 커맨드 팔레트 (Cmd+K)

| 명령 | ID | 동작 |
|------|-----|------|
| "외부 도구 대시보드" | `external-tool.dashboard` | 사이드바 "도구" 탭 전환 |
| "외부 도구 설정" | `settings.open.externalTool` | 외부 도구 설정 열기 |
| "외부 도구 헬스체크" | `external-tool.healthcheck` | 등록된 모든 세션 상태 체크 |
| "외부 도구 시작" | `external-tool.start` | 프로파일 선택 → 세션 시작 |

### 3-4. SystemHealthBarView 연동

SystemHealthBarView에 외부 도구 상태 요약 아이콘 추가:
- 등록된 외부 도구가 1개 이상일 때만 표시
- 아이콘: `hammer.fill` (모든 idle → green, 1개+ busy → blue, 1개+ error/waiting → orange)
- 클릭 시 사이드바 "도구" 탭으로 전환

---

## 4. 화면 상세

### 4-1. 사이드바 도구 목록 (ExternalToolListView)

새 파일: `Views/Sidebar/ExternalToolListView.swift`

> 참고: 아래 구조는 K-4 최초 릴리스 레이아웃(기록용)이다.  
> 2026-02 이후 오케스트레이션 콘솔 레이아웃 정본은 `spec/ux/k4-orchestration-console-layout.md`를 따른다.

```
┌─────────────────────────────────┐
│  [검색...]                       │
│                                  │
│  ── 실행 중 ──────────────────   │
│  🔵 Claude Code     작업 중      │
│     ~/projects/dochi   로컬      │
│  🟢 Codex            유휴        │
│     ~/projects/api     로컬      │
│  🟠 원격 Claude       입력 대기   │
│     devserver:~/app    SSH       │
│                                  │
│  ── 중지됨 ──────────────────    │
│  ⚫ aider            종료        │
│     ~/projects/ml      로컬      │
│                                  │
│  ── 프로파일 ─────────────────   │
│  + Claude Code (미시작)           │
│  + Cursor (미시작)                │
│                                  │
│  [+ 프로파일 추가]                │
└─────────────────────────────────┘
```

목록 구성:
- **실행 중 세션**: 활성 tmux 세션이 있는 프로파일. 상태 인디케이터 + 이름 + 상태 텍스트. 작업 디렉토리 + 로컬/SSH 표시
- **중지됨**: 이전에 실행했으나 세션이 dead인 프로파일
- **프로파일**: 등록은 되었으나 아직 세션을 시작하지 않은 프로파일

선택 시 디테일 영역에 해당 도구의 대시보드 표시.

### 4-2. 외부 도구 대시보드 (ExternalToolDashboardView)

새 파일: `Views/ExternalToolDashboardView.swift`

선택된 외부 도구의 상세 정보 + 터미널 출력 + 작업 입력을 표시.

```
┌──────────────────────────────────────────────────────────────┐
│  ┌─ 헤더 ────────────────────────────────────────────────┐   │
│  │  [terminal.fill] Claude Code              ● 작업 중   │   │
│  │  ~/projects/dochi  |  로컬  |  2분 경과               │   │
│  │                    [정지] [재시작] [설정]              │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─ 출력 (tmux capture) ─────────────────────────────────┐   │
│  │  > claude                                              │   │
│  │  Claude Code v1.0.0                                    │   │
│  │  Working directory: ~/projects/dochi                    │   │
│  │                                                        │   │
│  │  > fix the failing tests in DochiTests                 │   │
│  │  I'll analyze the test failures...                     │   │
│  │  Reading DochiTests/...                                │   │
│  │  ...                                                   │   │
│  │  ▼ (자동 스크롤)                                       │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─ 작업 입력 ───────────────────────────────────────────┐   │
│  │  [TextField: 작업 내용을 입력하세요...]     [전송]     │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─ 알림 배너 (상태 = waiting 시) ───────────────────────┐   │
│  │  ⚠️ 사용자 입력 대기 중: "[Y/n] Apply changes?"       │   │
│  │  [터미널에서 직접 응답]                                 │   │
│  └────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

구성:
- **헤더**: 도구 아이콘 + 이름, 상태 인디케이터, 작업 디렉토리, 로컬/SSH, 경과 시간, 액션 버튼 (정지/재시작/설정)
- **출력 영역**: `tmux capture-pane` 결과를 ScrollView로 표시. 모노스페이스 폰트. 자동 스크롤. 새로고침 간격 = `externalToolHealthCheckIntervalSeconds`
- **작업 입력**: TextField + 전송 버튼. 전송 시 `tmux send-keys` 실행. Enter로 전송
- **알림 배너**: 상태가 `.waiting`일 때만 표시. 입력 대기 중인 프롬프트 텍스트 표시

### 4-3. 프로파일 편집 시트 (ExternalToolProfileEditorView)

새 파일: `Views/ExternalToolProfileEditorView.swift`

"+ 프로파일 추가" 또는 기존 프로파일 "설정" 버튼 클릭 시 시트로 표시.

```
┌──────────────────────────────────────────────────────────┐
│  외부 AI 도구 프로파일                                     │
│                                                           │
│  ── 기본 ──────────────────────────────────────────────   │
│  이름:        [TextField: Claude Code                 ]   │
│  아이콘:      [Picker: terminal.fill ▼                ]   │
│  실행 명령:   [TextField: claude                      ]   │
│  인자:        [TextField: --model opus                ]   │
│  작업 디렉토리: [TextField: ~/projects/dochi  ] [선택]    │
│                                                           │
│  ── 연결 ──────────────────────────────────────────────   │
│  [Picker: 로컬 / SSH]                                     │
│                                                           │
│  (SSH 선택 시)                                             │
│  호스트:      [TextField: devserver                   ]   │
│  포트:        [TextField: 22                          ]   │
│  사용자:      [TextField: user                        ]   │
│  SSH 키 경로: [TextField: ~/.ssh/id_rsa      ] [선택]     │
│                                                           │
│  ── 헬스체크 패턴 ─────────────────────────────────────   │
│  유휴 패턴:   [TextField: ^>\s*$                      ]   │
│  작업 중 패턴: [TextField: (Thinking|Writing|Reading)  ]   │
│  입력 대기 패턴: [TextField: \[Y/n\]|\[y/N\]          ]   │
│  에러 패턴:   [TextField: (Error|error|FAILED)        ]   │
│                                                           │
│  ── 프리셋 ───────────────────────────────────────────    │
│  [Claude Code] [Codex CLI] [aider] [커스텀]               │
│  (프리셋 선택 시 패턴/명령 자동 채움)                      │
│                                                           │
│                          [취소]  [저장]                    │
└──────────────────────────────────────────────────────────┘
```

프리셋:
- **Claude Code**: command `claude`, idle `^>\\s*$`, busy `(Thinking|Writing|Reading|Editing)`
- **Codex CLI**: command `codex`, idle `^\\$\\s*$`, busy `(Running|Generating)`
- **aider**: command `aider`, idle `^>\\s*$`, busy `(Thinking|Editing|Committing)`

### 4-4. ExternalToolSettingsView

새 파일: `Views/Settings/ExternalToolSettingsView.swift`

```
┌───────────────────────────────────────────────────────────┐
│  [Form]                                                    │
│                                                            │
│  ── 외부 AI 도구 ─────────────────────────────────────    │
│  [Toggle] 외부 도구 관리 활성화                             │
│  (caption) tmux를 통해 Claude Code, Codex 등 외부 AI      │
│           도구를 관리합니다.                                │
│                                                            │
│  ── 헬스체크 ──────────────────────────────────────────    │
│  상태 확인 간격: [30]초  (Slider 10~120)                   │
│  출력 캡처 줄 수: [100]줄  (Slider 20~500)                 │
│  [Toggle] 자동 재시작 (세션 종료 시)                        │
│                                                            │
│  ── 등록된 프로파일 ──────────────────────────────────     │
│  ┌ Claude Code  |  로컬  |  claude        [편집] [삭제] ┐  │
│  ┌ Codex        |  로컬  |  codex         [편집] [삭제] ┐  │
│  ┌ 원격 Claude  |  SSH   |  devserver     [편집] [삭제] ┐  │
│                                                            │
│  [+ 프로파일 추가]                                          │
│                                                            │
│  ── tmux ──────────────────────────────────────────────    │
│  tmux 경로: [/usr/bin/tmux          ]                      │
│  세션 접두사: [dochi-               ]                       │
│  (caption) 도치가 생성하는 세션 이름에 이 접두사가 붙습니다  │
│                                                            │
└───────────────────────────────────────────────────────────┘
```

---

## 5. 빈 상태 / 에러 상태 / 로딩 상태

### 빈 상태
- **프로파일 없음** (도구 목록):
  ```
  등록된 외부 AI 도구가 없습니다.
  Claude Code, Codex, aider 등을 추가하여
  도치에서 통합 관리하세요.
  [+ 프로파일 추가]
  ```
  폰트: `.callout`, 색상: `.secondary`, 가운데 정렬

- **대시보드 미선택** (디테일 영역):
  ```
  외부 도구를 선택하세요.
  ```

### 에러 상태
- **tmux 미설치**: 설정 뷰 상단에 경고 배너
  ```
  ⚠️ tmux가 설치되어 있지 않습니다. `brew install tmux`로 설치하세요.
  ```
  노란 배경, `exclamationmark.triangle.fill` 아이콘

- **SSH 연결 실패**: 해당 도구 대시보드 헤더에 에러 배지 표시. 출력 영역에 에러 메시지
- **세션 생성 실패**: 토스트로 에러 알림, `Log.app.error` 기록

### 로딩 상태
- **헬스체크 중**: 도구 목록의 상태 인디케이터가 점멸 (opacity animation)
- **세션 시작 중**: 대시보드 헤더에 ProgressView (indeterminate)
- **출력 캡처 중**: 별도 표시 없음 (백그라운드 갱신)

---

## 6. 키보드 단축키

| 단축키 | 동작 | 컨텍스트 |
|--------|------|----------|
| Cmd+Shift+T | 사이드바 "도구" 탭 전환 | 전역 |
| Enter | 작업 전송 | 대시보드 입력 필드 포커스 시 |

---

## 7. 데이터 모델

### ExternalToolProfile (Codable, Identifiable, Sendable)

```swift
struct ExternalToolProfile: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var icon: String                     // SF Symbol name
    var command: String                  // 실행 명령 (예: "claude")
    var arguments: [String]             // 추가 인자 (예: ["--model", "opus"])
    var workingDirectory: String        // 작업 디렉토리 경로
    var sshConfig: SSHConfig?           // nil이면 로컬
    var healthCheckPatterns: HealthCheckPatterns
}

struct SSHConfig: Codable, Sendable {
    var host: String
    var port: Int                       // default: 22
    var user: String
    var keyPath: String?                // SSH 키 경로
}

struct HealthCheckPatterns: Codable, Sendable {
    var idlePattern: String             // 정규식
    var busyPattern: String
    var waitingPattern: String
    var errorPattern: String
}
```

### ExternalToolSession (Observable)

```swift
@Observable
class ExternalToolSession: Identifiable, Sendable {
    let id: UUID
    let profileId: UUID
    var tmuxSessionName: String
    var status: ExternalToolStatus
    var lastOutput: [String]            // capture-pane 캡처 결과
    var lastHealthCheckDate: Date?
    var startedAt: Date?
    var lastActivityText: String?       // 최근 활동 요약 (busy 시 표시)
}
```

### ExternalToolStatus

```swift
enum ExternalToolStatus: String, Codable, Sendable {
    case idle
    case busy
    case waiting
    case error
    case dead
    case unknown
}
```

### 저장 위치

```
~/Library/Application Support/Dochi/external-tools/
├── profiles/
│   ├── {profileId}.json
│   └── ...
└── presets/                            // 빌트인 프리셋 (앱 번들 내)
```

---

## 8. 서비스 구조

### ExternalToolSessionManager

새 파일: `Services/ExternalToolSessionManager.swift`

```swift
@MainActor
protocol ExternalToolSessionManagerProtocol: AnyObject {
    var profiles: [ExternalToolProfile] { get }
    var sessions: [ExternalToolSession] { get }
    var isTmuxAvailable: Bool { get }

    // Profile CRUD
    func loadProfiles()
    func saveProfile(_ profile: ExternalToolProfile)
    func deleteProfile(id: UUID)

    // Session lifecycle
    func startSession(profileId: UUID) async throws
    func stopSession(id: UUID) async
    func restartSession(id: UUID) async throws

    // Work dispatch
    func sendCommand(sessionId: UUID, command: String) async throws

    // Health check
    func checkHealth(sessionId: UUID) async
    func checkAllHealth() async

    // Output
    func captureOutput(sessionId: UUID, lines: Int) async -> [String]
}
```

### tmux 명령 실행

모든 tmux 명령은 `Process`를 통해 실행 (K-1 TerminalService와 동일 패턴):
- 로컬: `Process` 직접 실행 (`/usr/bin/tmux`)
- SSH: `Process`로 `ssh` 명령 래핑 (`ssh host "tmux ..."`)

### 세션 이름 규칙

`{prefix}{profileName}` — 예: `dochi-claude-code`, `dochi-codex`
설정의 `externalToolSessionPrefix` (기본 `dochi-`) 사용.

---

## 9. ViewModel 연동

### DochiViewModel 추가 사항

```swift
// 프로퍼티
var externalToolManager: ExternalToolSessionManagerProtocol?

// 사이드바 탭
var sidebarTab: SidebarTab = .conversations  // .conversations, .kanban, .tools

// 시스템 프롬프트에 외부 도구 상태 추가
func buildSystemPrompt() -> String {
    // ... 기존 로직 ...
    if let manager = externalToolManager, !manager.sessions.isEmpty {
        let toolStatus = manager.sessions.map { session in
            let profile = manager.profiles.first { $0.id == session.profileId }
            return "- \(profile?.name ?? "??"): \(session.status.rawValue)"
        }.joined(separator: "\n")
        parts.append("## 외부 AI 도구 현황\n\(toolStatus)")
    }
}
```

---

## 10. AppSettings 추가

```swift
// 외부 도구 관리 활성화
var externalToolEnabled: Bool                    // default: true
// 헬스체크 간격 (초)
var externalToolHealthCheckIntervalSeconds: Int   // default: 30
// 출력 캡처 줄 수
var externalToolOutputCaptureLines: Int           // default: 100
// 자동 재시작
var externalToolAutoRestart: Bool                // default: false
// tmux 경로
var externalToolTmuxPath: String                 // default: "/usr/bin/tmux"
// 세션 접두사
var externalToolSessionPrefix: String            // default: "dochi-"
```

---

## 11. SettingsSection 추가

```swift
case externalTool = "external-tool"

// title: "외부 도구"
// icon: "hammer"
// group: .development
// searchKeywords: ["외부", "도구", "external", "tool", "tmux", "Claude Code", "Codex", "aider", "세션", "session", "SSH", "원격", "헬스체크"]
```

---

## 12. 커맨드 팔레트 항목

| ID | title | category | action |
|----|-------|----------|--------|
| `external-tool.dashboard` | "외부 도구 대시보드" | .navigation | 사이드바 "도구" 탭 전환 |
| `settings.open.externalTool` | "외부 도구 설정" | .settings | `.openSettingsSection(section: "external-tool")` |
| `external-tool.healthcheck` | "외부 도구 상태 확인" | .action | 전체 헬스체크 실행 |
| `external-tool.start` | "외부 도구 시작" | .action | 프로파일 목록 표시 → 세션 시작 |

---

## 13. HeartbeatService 연동

HeartbeatService의 tick에서 외부 도구 헬스체크 추가:

```swift
// tick() 내부
if settings.externalToolEnabled {
    checksPerformed.append("external-tools")
    await externalToolManager?.checkAllHealth()
    // 상태 변경 시 알림 (waiting/error → 사용자 개입 필요)
}
```

이슈 감지 시 NotificationManager를 통해 알림:
- `.waiting` → "Claude Code가 입력을 기다리고 있습니다"
- `.error` → "Codex에서 에러가 발생했습니다"
- `.dead` + autoRestart → 자동 재시작 시도

---

## 14. LLM 도구 (BuiltInToolService)

6개 도구 등록:

| 도구 | category | 설명 |
|------|----------|------|
| `external_tool.register` | sensitive | 프로파일 등록/수정 |
| `external_tool.start` | restricted | 세션 시작 (프로세스 실행) |
| `external_tool.status` | safe | 상태 조회 |
| `external_tool.dispatch` | sensitive | 작업 전송 |
| `external_tool.read_output` | safe | 출력 읽기 |
| `external_tool.stop` | restricted | 세션 종료 |

`start`와 `stop`은 프로세스 생성/종료이므로 `restricted`, `dispatch`는 외부 도구에 명령을 보내므로 `sensitive`.

---

## 15. K-1 TerminalService와의 관계

| | K-1 TerminalService | K-4 ExternalToolSessionManager |
|-|---------------------|-------------------------------|
| 목적 | 일반 셸 세션 (ls, git 등) | 외부 AI 도구 전용 |
| 세션 관리 | `Process` + `Pipe` 직접 관리 | `tmux` 세션 기반 |
| 출력 | 실시간 Pipe 읽기 | `capture-pane` 주기적 캡처 |
| UI 위치 | 하단 터미널 패널 | 사이드바 "도구" 탭 + 디테일 대시보드 |
| 입력 | TerminalSessionView 입력 라인 | 대시보드 작업 입력 |

별도 서비스/뷰로 완전 분리. K-1 터미널에서 tmux 세션에 attach하는 것은 가능하나, K-4 대시보드와 별개.

---

## 16. 기존 시스템 연동

| 시스템 | 연동 방법 |
|--------|----------|
| HeartbeatService | tick에서 `checkAllHealth()` 호출 |
| NotificationManager | 상태 변경(waiting/error/dead) 시 알림 |
| SystemHealthBarView | 외부 도구 상태 요약 아이콘 |
| BuiltInToolService | 6개 도구 등록 |
| 시스템 프롬프트 | 외부 도구 상태 정보 포함 |

---

## 17. 파일 목록

| 파일 | 상태 | 설명 |
|------|------|------|
| `Dochi/Models/ExternalToolModels.swift` | 신규 | ExternalToolProfile, SSHConfig, HealthCheckPatterns, ExternalToolSession, ExternalToolStatus |
| `Dochi/Services/ExternalToolSessionManager.swift` | 신규 | 핵심 서비스 (프로토콜 + 구현) |
| `Dochi/Views/Sidebar/ExternalToolListView.swift` | 신규 | 사이드바 도구 목록 |
| `Dochi/Views/ExternalToolDashboardView.swift` | 신규 | 도구 대시보드 (출력 + 작업 입력) |
| `Dochi/Views/ExternalToolProfileEditorView.swift` | 신규 | 프로파일 편집 시트 |
| `Dochi/Views/Settings/ExternalToolSettingsView.swift` | 신규 | 설정 뷰 |
| `Dochi/Services/Tools/ExternalToolTools.swift` | 신규 | 6개 LLM 도구 |
| `Dochi/Views/Settings/SettingsSidebarView.swift` | 수정 | `.externalTool` 섹션 추가, `.development` 그룹 |
| `Dochi/Views/SettingsView.swift` | 수정 | ExternalToolSettingsView 라우팅 |
| `Dochi/Views/ContentView.swift` | 수정 | 사이드바 "도구" 탭 추가 |
| `Dochi/ViewModels/DochiViewModel.swift` | 수정 | ExternalToolSessionManager 연동, sidebarTab |
| `Dochi/Models/AppSettings.swift` | 수정 | 6개 설정 추가 |
| `Dochi/Models/CommandPaletteItem.swift` | 수정 | 4개 팔레트 항목 추가 |
| `Dochi/Services/HeartbeatService.swift` | 수정 | 외부 도구 헬스체크 tick 추가 |
| `Dochi/App/DochiApp.swift` | 수정 | 서비스 생성 및 DI |
| `DochiTests/ExternalToolTests.swift` | 신규 | 모델, 서비스, 헬스체크 테스트 |
| `DochiTests/Mocks/MockServices.swift` | 수정 | MockExternalToolSessionManager 추가 |
| `spec/ui-inventory.md` | 수정 | K-4 항목 추가 |

---

## 18. 테스트 계획

| 테스트 | 커버리지 |
|--------|----------|
| ExternalToolProfile Codable roundtrip | 모델 직렬화/역직렬화 (SSHConfig 포함/미포함) |
| ExternalToolStatus rawValues | 상태 enum 값 |
| HealthCheckPatterns 기본값 | 프리셋별 패턴 유효성 |
| Profile CRUD | 저장/로드/삭제 |
| 상태 판별 (패턴 매칭) | idle/busy/waiting/error 패턴별 매칭 |
| SSH config 유효성 | host/port/user 필수값 검증 |
| 세션 이름 생성 | prefix + profileName 조합 |
| tmux 미설치 감지 | isTmuxAvailable false 시 동작 |
| 도구 등록 도구 권한 | sensitive 카테고리 확인 |
| SettingsSection count | 기존 23 → 24개 확인 |
| SettingsSectionGroup development | terminal, externalTool 포함 |
| 시스템 프롬프트 외부 도구 포함 | 세션 있을 때 상태 정보 포함 |
