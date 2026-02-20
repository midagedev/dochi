# UX 명세: [K-6] 텔레그램 프로액티브 알림

> 상태: 설계 완료
> 관련: HeartbeatService, ProactiveSuggestionService, TelegramService, NotificationManager, AppSettings
> 이슈: #177

---

## 1. 개요

HeartbeatService와 ProactiveSuggestionService가 생성하는 프로액티브 메시지를 텔레그램 DM으로도 전달하는 기능. 현재는 앱 UI(대화 메시지 + macOS 알림 + 제안 버블)로만 전달되어, 앱을 열지 않으면 프로액티브 메시지를 받을 수 없다.

### 핵심 원칙
- **채널 확장**: 기존 앱 내 알림/제안 시스템을 변경하지 않고, 텔레그램을 추가 채널로 연결
- **중복 방지**: 앱이 포그라운드 활성 상태이면 텔레그램으로 보내지 않음 (설정 가능)
- **비침투적**: 텔레그램 메시지도 하트비트/제안의 방해 금지 시간, 하루 최대 횟수 제한 준수
- **응답 가능**: 사용자가 텔레그램에서 알림에 답장하면 대화로 이어짐

---

## 2. 알림 유형별 텔레그램 메시지 포맷

모든 메시지는 Telegram Markdown(parse_mode: "Markdown") 포맷. 각 유형별 이모지 접두사로 시각적 구분.

### 2-1. HeartbeatService 알림 (4 유형)

#### 캘린더 알림
```
📅 *일정 알림*
15:00 팀 미팅 — Zoom
16:30 코드리뷰 — 오피스

_2건의 일정이 2시간 내에 있습니다_
```

#### 칸반 알림
```
📋 *칸반 진행 상황*
- 🔴 디자인 시스템 구축 [프로젝트A]
- 🟡 API 리팩토링 [프로젝트B]

_2건의 카드가 진행 중입니다_
```

#### 미리알림 알림
```
⏰ *마감 임박 미리알림*
- 세금 신고 (마감: 15:00)
- 보고서 제출 (마감: 17:00)

_2건의 미리알림이 곧 마감됩니다_
```

#### 메모리 경고
```
💾 *메모리 정리 필요*
워크스페이스 메모리가 4,200자로 커졌습니다.

_"메모리 정리해줘"라고 답장하면 자동 정리합니다_
```

### 2-2. ProactiveSuggestionService 제안 (6 유형)

#### 트렌드 (newsTrend)
```
🌐 *관심있으실 만한 소식*
최근 'Swift 6.1' 관련 대화를 하셨습니다. 관련 최신 소식을 알아볼까요?

💡 "알아봐줘"라고 답장하세요
```

#### 심화 설명 (deepDive)
```
📖 *이전 대화 주제 심화*
'ONNX 런타임 최적화'에 대해 더 자세히 설명드릴까요?

💡 "설명해줘"라고 답장하세요
```

#### 관련 자료 (relatedResearch)
```
🔍 *관련 자료 조사*
'RAG 파이프라인' 관련 최신 자료를 조사해볼까요?

💡 "조사해줘"라고 답장하세요
```

#### 칸반 체크 (kanbanCheck)
```
✅ *칸반 진행 상황 체크*
'디자인 시스템 구축' 카드가 진행 중입니다. 도움이 필요하신가요?

💡 "확인해줘"라고 답장하세요
```

#### 메모리 리마인드 (memoryRemind)
```
🧠 *메모리에 기한 관련 메모*
'이번 주' 관련 메모를 확인해보세요: ...이번 주까지 리뷰 완료하기로 함...

💡 "리마인드해줘"라고 답장하세요
```

#### 비용 리포트 (costReport)
```
📊 *이번 주 AI 사용량*
이번 주 AI 사용 현황을 확인해보세요.

💡 "요약 보여줘"라고 답장하세요
```

---

## 3. 알림 채널 설정 UI

### 3-1. 위치: 설정 > 하트비트 (HeartbeatSettingsContent)

기존 HeartbeatSettingsContent에 "텔레그램 알림" Section을 추가한다. "알림 센터" Section 바로 아래에 배치.

```
Section("텔레그램 알림") {
    // 전제 조건 체크: 텔레그램이 설정되어 있어야 함
    if !isTelegramConfigured:
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("텔레그램 봇이 설정되지 않았습니다")
                .font(.caption)
        }
        Button("텔레그램 설정으로 이동") {
            // selectedSection = .integrations
        }
    else:
        // -- 하트비트 알림 채널 --
        Picker("하트비트 알림 채널", selection: heartbeatNotificationChannel) {
            Text("앱만").tag("appOnly")
            Text("텔레그램만").tag("telegramOnly")
            Text("둘 다").tag("both")
            Text("끄기").tag("off")
        }
        .pickerStyle(.segmented)

        Text("캘린더/칸반/미리알림/메모리 알림의 전달 채널")
            .font(.caption)
            .foregroundStyle(.secondary)

        // -- 프로액티브 제안 채널 --
        Picker("프로액티브 제안 채널", selection: suggestionNotificationChannel) {
            Text("앱만").tag("appOnly")
            Text("텔레그램만").tag("telegramOnly")
            Text("둘 다").tag("both")
            Text("끄기").tag("off")
        }
        .pickerStyle(.segmented)

        Text("유휴 감지 기반 제안의 전달 채널")
            .font(.caption)
            .foregroundStyle(.secondary)

        // -- 중복 방지 --
        Toggle("앱 활성 시 텔레그램 전송 생략", isOn: $telegramSkipWhenAppActive)

        Text("앱이 포그라운드에 있으면 텔레그램으로 보내지 않습니다")
            .font(.caption)
            .foregroundStyle(.secondary)
}
.disabled(!settings.heartbeatEnabled)
```

### 3-2. 텔레그램 알림 채널 값 (NotificationChannel)

```swift
enum NotificationChannel: String, Codable, Sendable, CaseIterable {
    case appOnly        // macOS 알림 + 인앱 UI만
    case telegramOnly   // 텔레그램 DM만
    case both           // 둘 다
    case off            // 끄기
}
```

하트비트와 프로액티브 제안에 각각 독립 설정:
- `heartbeatNotificationChannel`: 기본 `appOnly`
- `suggestionNotificationChannel`: 기본 `appOnly`

### 3-3. 검색 키워드 추가

기존 `SettingsSection.heartbeat`의 `searchKeywords`에 추가:
```
"텔레그램 알림", "telegram", "프로액티브", "채널"
```

---

## 4. 앱 활성 상태 중복 방지

### 4-1. 감지 방법

`NSApp.isActive`를 사용하여 앱이 포그라운드에 있는지 판별한다.

```swift
// TelegramProactiveRelay 내부
private func shouldSendToTelegram(channel: NotificationChannel) -> Bool {
    guard channel == .telegramOnly || channel == .both else { return false }

    // 앱 활성 시 생략 옵션이 켜져 있고, 앱이 활성 상태이면 전송하지 않음
    if settings.telegramSkipWhenAppActive && NSApp.isActive {
        // "both"인 경우에도 앱이 활성이면 텔레그램 생략 (앱 알림만 전달)
        Log.telegram.debug("앱이 활성 상태이므로 텔레그램 전송 생략")
        return false
    }

    return true
}
```

### 4-2. 채널별 동작 매트릭스

| 설정 | 앱 활성 + 생략 ON | 앱 활성 + 생략 OFF | 앱 비활성 |
|------|-------------------|-------------------|-----------|
| `appOnly` | 앱 알림만 | 앱 알림만 | 앱 알림만 |
| `telegramOnly` | 전송 안 함 | 텔레그램만 | 텔레그램만 |
| `both` | 앱 알림만 | 앱 + 텔레그램 | 앱 + 텔레그램 |
| `off` | 전송 안 함 | 전송 안 함 | 전송 안 함 |

---

## 5. 텔레그램 응답 처리

### 5-1. 텍스트 답장 방식

인라인 키보드 대신 **텍스트 답장**을 사용한다. 이유:
- 텔레그램 인라인 키보드는 `sendMessage` 시점에 정의해야 하며, 동적 업데이트가 복잡
- 도치의 기존 텔레그램 DM 처리 파이프라인(`onMessage`)이 텍스트 입력을 이미 LLM으로 전달
- 사용자가 자유 형식으로 답장할 수 있어 자연스러운 대화 흐름 유지

### 5-2. 응답 흐름

```
1. HeartbeatService/ProactiveSuggestionService → 알림 생성
2. TelegramProactiveRelay → 텔레그램 메시지 전송 (포맷 적용)
3. 사용자가 텔레그램에서 텍스트 답장
4. TelegramService.onMessage → DochiViewModel.handleTelegramMessage
5. 기존 LLM 파이프라인에서 처리 (이미 구현됨)
```

제안 메시지 하단의 "답장하세요" 안내는 사용자에게 힌트를 줄 뿐, 특별한 커맨드 파싱은 불필요하다. 사용자의 자유 응답이 LLM에 전달되어 자연스럽게 처리된다.

### 5-3. 컨텍스트 유지

프로액티브 제안을 텔레그램으로 보낸 경우, 사용자의 답장은 해당 텔레그램 chatId에 매핑된 대화에서 처리된다. 제안의 `suggestedPrompt`를 시스템 컨텍스트에 포함하여 LLM이 맥락을 파악할 수 있도록 한다.

```swift
// TelegramProactiveRelay에서 제안 전송 시, 최근 전송 제안을 기록
private var lastSentSuggestion: ProactiveSuggestion?

// 사용자 답장 수신 시, DochiViewModel에서 컨텍스트 힌트 추가
// 기존 handleTelegramMessage 흐름에서 자연스럽게 처리됨
```

---

## 6. 서비스 구조: TelegramProactiveRelay

### 6-1. 역할

HeartbeatService와 ProactiveSuggestionService의 출력을 텔레그램 메시지로 변환하여 전달하는 중계 서비스. 기존 서비스를 수정하지 않고, 콜백/관찰을 통해 연결.

### 6-2. 프로토콜

새 파일: `Services/Protocols/TelegramProactiveRelayProtocol.swift`

```swift
@MainActor
protocol TelegramProactiveRelayProtocol: AnyObject {
    var isActive: Bool { get }

    func start()
    func stop()

    /// 텔레그램으로 보낸 알림 수 (오늘)
    var todayTelegramNotificationCount: Int { get }
}
```

### 6-3. 구현

새 파일: `Services/Telegram/TelegramProactiveRelay.swift`

```swift
@MainActor
@Observable
final class TelegramProactiveRelay: TelegramProactiveRelayProtocol {
    // Dependencies
    private let settings: AppSettings
    private let telegramService: TelegramServiceProtocol
    private let keychainService: KeychainServiceProtocol

    // State
    private(set) var isActive: Bool = false
    private(set) var todayTelegramNotificationCount: Int = 0
    private var todayDateString: String = ""

    // 최근 전송한 제안 (응답 컨텍스트용)
    private(set) var lastSentSuggestion: ProactiveSuggestion?
}
```

### 6-4. HeartbeatService 연동

HeartbeatService에 새 콜백을 추가하지 않는다. 대신, 기존 `onProactiveMessage` 콜백과 NotificationManager의 개별 메서드를 활용하여 TelegramProactiveRelay가 같은 데이터를 받아 텔레그램으로 전송한다.

구체적으로: HeartbeatService에 `setTelegramRelay` 주입 메서드를 추가하고, `tick()` 내에서 텔레그램 전송을 호출.

```swift
// HeartbeatService에 추가
private var telegramRelay: TelegramProactiveRelayProtocol?

func setTelegramRelay(_ relay: TelegramProactiveRelayProtocol) {
    self.telegramRelay = relay
}

// tick() 내 알림 전송 부분에서:
// 기존 NotificationManager 호출 후, 텔레그램 릴레이에도 전달
if shouldSendToTelegram(channel: settings.heartbeatNotificationChannel) {
    await telegramRelay?.sendHeartbeatAlert(
        calendar: calendarContext,
        kanban: kanbanContext,
        reminder: reminderContext,
        memory: memoryWarning
    )
}
```

### 6-5. ProactiveSuggestionService 연동

ProactiveSuggestionService의 `currentSuggestion` 변화를 관찰하여 텔레그램으로 전달.

```swift
// TelegramProactiveRelay 내부
private var observationTask: Task<Void, Never>?

func start() {
    // ProactiveSuggestionService의 currentSuggestion을 관찰
    // 새 제안이 생성되면 텔레그램으로 전송
}
```

또는 ProactiveSuggestionService에도 HeartbeatService와 동일하게 `setTelegramRelay` 주입 메서드를 추가하여, `generateSuggestion()` 내에서 제안 생성 시 텔레그램 릴레이에 전달.

```swift
// ProactiveSuggestionService에 추가
private var telegramRelay: TelegramProactiveRelayProtocol?

func setTelegramRelay(_ relay: TelegramProactiveRelayProtocol) {
    self.telegramRelay = relay
}

// generateSuggestion() 내에서:
if shouldSendToTelegram(channel: settings.suggestionNotificationChannel) {
    await telegramRelay?.sendSuggestion(selected)
}
```

### 6-6. 텔레그램 chatId 결정

텔레그램 알림을 보낼 chatId는 `settings.telegramChatMappingJSON`에서 현재 워크스페이스에 매핑된 chatId를 사용한다. 매핑이 없으면 텔레그램 전송을 건너뛴다.

```swift
private func resolveChatId() -> Int64? {
    let mapping = TelegramChatMapping.parse(json: settings.telegramChatMappingJSON)
    let workspaceId = settings.currentWorkspaceId
    return mapping.chatId(for: workspaceId)
}
```

---

## 7. AppSettings 추가

```swift
// MARK: - Telegram Proactive Notifications (K-6)

/// 하트비트 알림 텔레그램 채널: appOnly / telegramOnly / both / off
var heartbeatNotificationChannel: String =
    UserDefaults.standard.string(forKey: "heartbeatNotificationChannel") ?? "appOnly" {
    didSet { UserDefaults.standard.set(heartbeatNotificationChannel, forKey: "heartbeatNotificationChannel") }
}

/// 프로액티브 제안 텔레그램 채널: appOnly / telegramOnly / both / off
var suggestionNotificationChannel: String =
    UserDefaults.standard.string(forKey: "suggestionNotificationChannel") ?? "appOnly" {
    didSet { UserDefaults.standard.set(suggestionNotificationChannel, forKey: "suggestionNotificationChannel") }
}

/// 앱 활성 시 텔레그램 전송 생략
var telegramSkipWhenAppActive: Bool =
    UserDefaults.standard.object(forKey: "telegramSkipWhenAppActive") as? Bool ?? true {
    didSet { UserDefaults.standard.set(telegramSkipWhenAppActive, forKey: "telegramSkipWhenAppActive") }
}
```

---

## 8. 상태별 처리

### 8-1. 텔레그램 미설정 상태

텔레그램 봇 토큰이 등록되지 않은 경우:
- 설정 UI의 "텔레그램 알림" Section에 경고 + 설정 바로가기 버튼 표시
- 채널 Picker는 비활성(disabled) 상태로 표시
- HeartbeatService/ProactiveSuggestionService는 텔레그램 전송을 건너뜀 (에러 없이)

### 8-2. 텔레그램 폴링 미시작 상태

봇 토큰은 있으나 폴링/웹훅이 비활성인 경우:
- 메시지 전송은 가능 (`sendMessage`는 폴링 상태와 무관)
- 사용자 답장은 수신 불가 - 별도 경고 불필요 (전송만 하는 것이므로)

### 8-3. chatId 미매핑 상태

현재 워크스페이스에 텔레그램 chatId 매핑이 없는 경우:
- 텔레그램 전송을 조용히 건너뜀
- `Log.telegram.debug`로 기록만 수행
- 설정 UI에 알림: "현재 워크스페이스에 텔레그램 채팅이 매핑되지 않았습니다. 텔레그램에서 먼저 메시지를 보내주세요."

### 8-4. 전송 실패 (네트워크 오류)

- 실패 시 재시도하지 않음 (프로액티브 알림이므로 한 번 놓쳐도 치명적이지 않음)
- `Log.telegram.warning`으로 기록
- 앱 UI에 에러 표시하지 않음 (사용자가 요청한 동작이 아니므로)

### 8-5. 방해 금지 시간

HeartbeatService와 ProactiveSuggestionService가 이미 방해 금지 시간을 체크하므로, TelegramProactiveRelay에서 별도 체크 불필요. 방해 금지 시간에는 tick/제안 자체가 발생하지 않는다.

---

## 9. ViewModel 연동

### DochiViewModel 추가 사항

```swift
// MARK: - Telegram Proactive (K-6)
private(set) var telegramProactiveRelay: TelegramProactiveRelayProtocol?

func configureTelegramProactiveRelay(_ relay: TelegramProactiveRelayProtocol) {
    self.telegramProactiveRelay = relay
}
```

### DI 흐름 (DochiApp.swift)

```swift
// 1. TelegramProactiveRelay 생성
let telegramRelay = TelegramProactiveRelay(
    settings: settings,
    telegramService: telegramService,
    keychainService: keychainService
)

// 2. HeartbeatService에 주입
heartbeatService.setTelegramRelay(telegramRelay)

// 3. ProactiveSuggestionService에 주입
proactiveSuggestionService.setTelegramRelay(telegramRelay)

// 4. ViewModel에 주입
viewModel.configureTelegramProactiveRelay(telegramRelay)

// 5. 텔레그램 설정 변경 시 릴레이 상태 갱신
// (TelegramProactiveRelay가 settings를 @Observable로 관찰하므로 자동)
```

---

## 10. 설정 뷰 통합 위치

### 10-1. HeartbeatSettingsContent (기존 파일: `Views/SettingsView.swift`)

기존 "알림 센터" Section 바로 아래에 "텔레그램 알림" Section 추가 (3 참조).

### 10-2. IntegrationsSettingsView (기존 파일)

변경 없음. 텔레그램 봇 토큰/연결 설정은 기존 통합 서비스 섹션에서 관리. K-6는 전달 채널 선택만 HeartbeatSettingsContent에 추가.

### 10-3. 설정 검색 키워드

`SettingsSection.heartbeat`의 `searchKeywords`에 추가:
```swift
"텔레그램", "telegram", "알림 채널", "프로액티브 알림"
```

---

## 11. UI 인벤토리 업데이트 (머지 시 반영)

### 앱 구조 트리 변경

없음. K-6은 새로운 뷰를 추가하지 않고, 기존 HeartbeatSettingsContent에 Section을 추가하는 것만으로 충분.

### DochiViewModel 속성 추가

| 속성 | 타입 | 설명 | 사용처 |
|------|------|------|--------|
| `telegramProactiveRelay` | `TelegramProactiveRelayProtocol?` | 텔레그램 프로액티브 릴레이 (K-6) | HeartbeatService, ProactiveSuggestionService |

### AppSettings 추가

| 기능 | 키 |
|------|-----|
| 텔레그램 프로액티브 알림 (K-6) | `heartbeatNotificationChannel`, `suggestionNotificationChannel`, `telegramSkipWhenAppActive` |

### 플로우 추가

```
텔레그램 프로액티브 알림 (K-6 추가)
HeartbeatService tick → 알림 생성 → NotificationManager (macOS 알림)
  + TelegramProactiveRelay.sendHeartbeatAlert (채널 설정에 따라)
  → 텔레그램 DM 전송 (Markdown 포맷)
ProactiveSuggestionService → 제안 생성 → SuggestionBubbleView (인앱)
  + TelegramProactiveRelay.sendSuggestion (채널 설정에 따라)
  → 텔레그램 DM 전송 (Markdown 포맷 + 답장 안내)
사용자 텔레그램 답장 → onMessage → DochiViewModel.handleTelegramMessage (기존 흐름)
중복 방지: telegramSkipWhenAppActive + NSApp.isActive 체크
설정: 설정 > 하트비트 > 텔레그램 알림 Section
AppSettings: heartbeatNotificationChannel, suggestionNotificationChannel, telegramSkipWhenAppActive
```

---

## 12. 파일 목록

| 구분 | 파일 | 설명 |
|------|------|------|
| 신규 | `Services/Protocols/TelegramProactiveRelayProtocol.swift` | 프로토콜 |
| 신규 | `Services/Telegram/TelegramProactiveRelay.swift` | 텔레그램 프로액티브 릴레이 서비스 |
| 수정 | `Models/AppSettings.swift` | 3개 설정 추가 (heartbeatNotificationChannel, suggestionNotificationChannel, telegramSkipWhenAppActive) |
| 수정 | `Services/HeartbeatService.swift` | setTelegramRelay 주입 + tick에서 텔레그램 전달 |
| 수정 | `Services/ProactiveSuggestionService.swift` | setTelegramRelay 주입 + 제안 생성 시 텔레그램 전달 |
| 수정 | `Views/SettingsView.swift` (HeartbeatSettingsContent) | "텔레그램 알림" Section 추가 |
| 수정 | `Views/Settings/SettingsSidebarView.swift` | heartbeat 검색 키워드에 텔레그램 관련 추가 |
| 수정 | `ViewModels/DochiViewModel.swift` | TelegramProactiveRelay 연동 |
| 수정 | `App/DochiApp.swift` | TelegramProactiveRelay 생성 + DI |
| 신규 | `DochiTests/TelegramProactiveRelayTests.swift` | 유닛 테스트 |
| 수정 | `DochiTests/Mocks/MockServices.swift` | MockTelegramProactiveRelay 추가 |

---

## 13. 테스트 계획

| 테스트 | 검증 항목 |
|--------|-----------|
| `testHeartbeatTelegramRelay` | heartbeatNotificationChannel = both일 때 텔레그램 메시지 전송 |
| `testSuggestionTelegramRelay` | suggestionNotificationChannel = telegramOnly일 때 텔레그램 전송 |
| `testAppActiveSkip` | telegramSkipWhenAppActive = true + 앱 활성 → 텔레그램 미전송 |
| `testAppActiveNoSkip` | telegramSkipWhenAppActive = false + 앱 활성 → 텔레그램 전송 |
| `testAppOnlyChannel` | channel = appOnly → 텔레그램 미전송 |
| `testOffChannel` | channel = off → 앱 알림도 텔레그램도 미전송 |
| `testNoTelegramToken` | 토큰 미설정 → 텔레그램 전송 건너뜀 (에러 없이) |
| `testNoChatMapping` | chatId 미매핑 → 조용히 건너뜀 |
| `testCalendarMessageFormat` | 캘린더 알림의 Markdown 포맷 검증 |
| `testKanbanMessageFormat` | 칸반 알림의 Markdown 포맷 검증 |
| `testReminderMessageFormat` | 미리알림 알림의 Markdown 포맷 검증 |
| `testMemoryMessageFormat` | 메모리 경고의 Markdown 포맷 검증 |
| `testSuggestionMessageFormat` | 6가지 제안 유형별 Markdown 포맷 검증 |
| `testQuietHoursRespected` | 방해 금지 시간에는 HeartbeatService tick 자체가 안 되므로 텔레그램도 미전송 |
| `testNotificationChannelEnum` | NotificationChannel enum rawValue roundtrip |
| `testDailyCount` | todayTelegramNotificationCount 일별 리셋 |
| `testSendFailureGraceful` | 네트워크 오류 시 예외 없이 로그만 |

---

## 14. 구현 참고 사항

### 14-1. TelegramService.sendMessage 호출

`TelegramProactiveRelay`는 `TelegramServiceProtocol.sendMessage(chatId:text:)`를 직접 호출한다. 이미 `parse_mode: "Markdown"`이 기본 설정되어 있으므로 별도 포맷 파라미터는 불필요.

### 14-2. Markdown 이스케이프

텔레그램 Markdown에서 특수문자(`_`, `*`, `` ` ``, `[`)는 이스케이프 필요. 사용자 데이터(카드 제목, 일정 이름 등)를 삽입할 때 특수문자를 이스케이프하는 유틸리티 함수가 필요하다.

```swift
/// Telegram Markdown 특수문자 이스케이프
private func escapeMarkdown(_ text: String) -> String {
    text.replacingOccurrences(of: "_", with: "\\_")
        .replacingOccurrences(of: "*", with: "\\*")
        .replacingOccurrences(of: "`", with: "\\`")
        .replacingOccurrences(of: "[", with: "\\[")
}
```

### 14-3. 기존 시스템 변경 최소화

- HeartbeatService: `setTelegramRelay` 주입 + tick 내 3줄 추가
- ProactiveSuggestionService: `setTelegramRelay` 주입 + generateSuggestion 내 3줄 추가
- NotificationManager: 변경 없음
- TelegramService: 변경 없음
- DochiViewModel: configureTelegramProactiveRelay 메서드 1개 추가

핵심 로직(포맷 변환, 채널 판별, 중복 방지)은 모두 TelegramProactiveRelay에 캡슐화.
