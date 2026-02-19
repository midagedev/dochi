# CLAUDE.md

## 스펙 문서 (정본)

- 전체 스펙: [spec/README.md](./spec/README.md)
- 상태 머신: [spec/states.md](./spec/states.md)
- 플로우: [spec/flows.md](./spec/flows.md)
- 데이터 모델: [spec/models.md](./spec/models.md)
- 서비스 인터페이스: [spec/interfaces.md](./spec/interfaces.md)
- 도구 스키마: [spec/tools.md](./spec/tools.md)
- LLM 규칙: [spec/llm-requirements.md](./spec/llm-requirements.md)
- 보안/권한: [spec/security.md](./spec/security.md)
- 실행 컨텍스트: [spec/execution-context.md](./spec/execution-context.md)

## Build Commands

```bash
# Generate Xcode project from project.yml (required after changing project.yml)
xcodegen generate

# Build
xcodebuild -project Dochi.xcodeproj -scheme Dochi -configuration Debug build

# Run tests
xcodebuild -project Dochi.xcodeproj -scheme Dochi -configuration Debug -destination 'platform=macOS' test

# Run the built app
open ~/Library/Developer/Xcode/DerivedData/Dochi-*/Build/Products/Debug/Dochi.app
```

## Code Structure

```
Dochi/
├── App/                          # DochiApp.swift (entry point + AppDelegate)
├── Models/                       # Data models (LLMProvider, Message, Conversation, TTSProvider, KanbanBoard, etc.)
├── State/                        # State machine enums (InteractionState, SessionState, ProcessingSubState)
├── ViewModels/                   # DochiViewModel (orchestrator)
├── Views/                        # SwiftUI views (ContentView, ConversationView, SettingsView, AvatarView, KanbanWorkspaceView)
│   ├── Settings/                 # 설정 탭 뷰 (VoiceSettingsView, ToolsSettingsView, etc.)
│   └── Sidebar/                  # 사이드바 관련 뷰 (AgentCreationView, WorkspaceManagementView, etc.)
├── Services/
│   ├── Protocols/                # Service protocols (10개: Context, Conversation, Keychain, LLM, Speech, TTS, BuiltInTool, MCP, Supabase, Telegram)
│   ├── LLM/                      # LLMService + provider adapters (OpenAI, Anthropic, Z.AI) + ModelRouter
│   ├── Context/                  # ContextService — file-based context
│   ├── Conversation/             # ConversationService — conversation CRUD
│   ├── Keychain/                 # KeychainService — API key management
│   ├── Tools/                    # BuiltInToolService + 35개 도구 + ToolRegistry
│   ├── Speech/                   # SpeechService — Apple STT + wake word
│   ├── TTS/                      # TTSRouter + SystemTTS + GoogleCloudTTS + SupertonicService (ONNX)
│   ├── Sound/                    # SoundService — UI 효과음
│   ├── Avatar/                   # AvatarManager + FaceTrackingService — VRM 3D 아바타
│   ├── MCP/                      # MCPService — MCP server proxy
│   ├── Telegram/                 # TelegramService — DM + streaming
│   ├── Cloud/                    # SupabaseService — auth + sync
│   ├── HeartbeatService.swift    # 프로액티브 에이전트 (캘린더/칸반/미리알림 주기 점검)
│   └── MetricsCollector.swift    # LLM 교환 메트릭 수집
├── Resources/
│   ├── Assets.xcassets/          # 앱 아이콘
│   └── Models/                   # VRM 아바타 모델 (gitignored)
└── Utilities/                    # Log enum, SentenceChunker, JamoMatcher

DochiTests/
├── Mocks/                        # Mock service implementations
└── DochiTests.swift

DochiUITests/
└── DochiUITests.swift
```

## Testing

### 단위 테스트

```bash
# 전체 테스트 실행
xcodebuild -project Dochi.xcodeproj -scheme Dochi -configuration Debug -destination 'platform=macOS' test

# 특정 테스트 클래스만 실행
xcodebuild test -project Dochi.xcodeproj -scheme Dochi -destination 'platform=macOS' \
  -only-testing:DochiTests/ProfilePersistenceTests
```

테스트 구조:
- `DochiTests/Mocks/MockServices.swift` — 모든 서비스 프로토콜의 Mock 구현
- `DochiTests/ContextServiceTests.swift` — ContextService 파일 I/O (임시 디렉토리 사용)
- `DochiTests/FamilyFeatureTests.swift` — 프로필 CRUD, ViewModel 사용자 전환, 시스템 프롬프트
- `DochiTests/ConversationServiceTests.swift` — 대화 저장/로드/삭제
- `DochiTests/ModelTests.swift`, `ToolRegistryTests.swift`, `LLMAdapterTests.swift` 등

테스트 작성 규칙:
- **기능 구현 시 반드시 단위 테스트를 쌍으로 작성할 것.** 테스트 없는 기능 구현은 완료로 간주하지 않음
- **ContextService 테스트**: `ContextService(baseURL: tempDir)` 사용 — 실제 앱 데이터 건드리지 않음
- **ViewModel 테스트**: `MockContextService` + `MockKeychainService` 등 Mock 주입
- **JSON 파일 포맷**: 날짜는 ISO 8601 (`encoder.dateEncodingStrategy = .iso8601`). 기존 데이터와 호환성 테스트 반드시 포함
- 핵심 데이터 경로(저장→로드 roundtrip, 상태 전환, 에러 케이스) 커버
- 구현 완료 후 `xcodebuild test` 통과 확인 필수

### 스모크 테스트

```bash
# 빌드 → 앱 실행 → 상태 검증 (자동)
./scripts/smoke_test.sh
```

동작 방식:
1. `SmokeTestReporter` (DEBUG 빌드 전용)가 앱 시작 시 `/tmp/dochi_smoke.log`에 주요 상태 기록
2. `scripts/smoke_test.sh`가 로그 파일을 파싱하여 기대값 검증
3. 검증 항목: 프로필 수, 현재 사용자 ID/이름, 대화 수, 워크스페이스, 에이전트

기능 구현 후 UI 동작까지 확인할 때 사용. 단위 테스트로 못 잡는 **앱 초기화 흐름** 검증에 유용.

## Conventions

- `@MainActor` on all ViewModels and Services
- Swift 6.0 with `SWIFT_STRICT_CONCURRENCY: targeted`
- `async/await` + `Task` for concurrency; `Task.detached` for CPU-heavy ONNX
- Logging via `Log.*` (os.Logger) — never use `print()`
- UI language: Korean
- XcodeGen (`project.yml`) generates `.xcodeproj` — edit `project.yml`, not Xcode project
- Protocol-based DI for all services — mock injection for tests
- macOS 14+ deployment target
- `project.yml` auto-includes all files under `Dochi/` path — no need to add new files manually
- **기능 구현 = 코드 + 테스트**: 모든 기능은 단위 테스트와 쌍으로 작성. 빌드 후 `xcodebuild test` 통과 필수

## Swift Code Quality Rules

### Concurrency (Swift 6.0, strict targeted)
- `@MainActor`는 진짜 UI 관련 코드에만 사용. "일단 붙이기" 금지 — 왜 main-actor isolation이 맞는지 근거 필요
- 구조적 동시성 우선: `TaskGroup`/child task > 비구조적 `Task {}`. `Task.detached`는 CPU-heavy 작업(ONNX 등)에만 명확한 이유와 함께 사용
- `@preconcurrency`, `@unchecked Sendable`, `nonisolated(unsafe)` 사용 시: 안전 불변조건(safety invariant) 주석 필수 + 제거 계획 TODO 추가
- isolation 경계를 넘기 전에 먼저 식별: `@MainActor`, custom actor, `nonisolated` 중 어디에 속하는지 확인
- suspension point 최소화 — actor-isolated 구간을 짧게 유지하여 context switch 줄이기
- `async` 컨텍스트에서 semaphore/lock으로 블로킹 금지 — deadlock 위험
- `Task.isCancelled` 검사: 장시간 실행 작업에서 반드시 cancellation 처리

### API Design (Apple Swift API Design Guidelines)
- **사용 시점의 명확성**(clarity at point of use) 최우선. 간결성보다 명확성
- 역할로 이름 짓기, 타입 반복 금지: `var greeting: String` (O) / `var greetingString` (X)
- 부작용 기준 네이밍: 부작용 없으면 명사구(`x.distance(to:)`), 부작용 있으면 명령형 동사(`x.sort()`)
- mutating/nonmutating 쌍: 동사 → `sort()` / `sorted()`, 명사 → `union()` / `formUnion()`
- Bool 프로퍼티/메서드는 단언문으로 읽히게: `isEmpty`, `intersects(line2)`
- Factory 메서드는 `make` 접두사: `makeIterator()`
- 약어 금지, 기술 용어는 정확히 사용

### Code Style
- 타입/프로토콜: `UpperCamelCase`, 그 외: `lowerCamelCase`
- 약어 대소문자 통일: `utf8Bytes`, `ASCII` (혼합 금지)
- 기본값 있는 파라미터는 파라미터 목록 뒤쪽에 배치
- O(1)이 아닌 computed property는 복잡도 문서화
- free function은 `self`가 없거나 제약 없는 제네릭일 때만

## External Dependencies

- `microsoft/onnxruntime-swift-package-manager` v1.20.0 (TTS ONNX)
- `modelcontextprotocol/swift-sdk` v0.10.2 (MCP)
- `supabase/supabase-swift` v2.0.0+ (Cloud sync)
- `tattn/VRMKit` v0.5.0 (3D 아바타 — VRMKit + VRMRealityKit)

## Logging

Subsystem: `com.dochi.app`. Categories: App, LLM, STT, TTS, MCP, Tool, Storage, Cloud, Telegram, Avatar.

```bash
log show --predicate 'subsystem == "com.dochi.app"' --last 5m --style compact
log show --predicate 'subsystem == "com.dochi.app" AND category == "Tool"' --last 5m
```

## Context Structure

```
~/Library/Application Support/Dochi/
├── system_prompt.md
├── profiles.json
├── conversations/{id}.json
├── memory/{userId}.md
├── kanban/                       # 칸반 보드 데이터
│   └── {boardId}.json
└── workspaces/{wsId}/
    ├── config.json
    ├── memory.md
    └── agents/{name}/
        ├── persona.md
        ├── memory.md
        └── config.json
```

## Architecture

상세: [spec/tech-spec.md](./spec/tech-spec.md)

핵심 설계:
- **명시적 상태 머신**: [spec/states.md](./spec/states.md) — InteractionState / SessionState / ProcessingSubState
- **프로바이더 어댑터**: [spec/llm-requirements.md](./spec/llm-requirements.md#provider-adapter) — OpenAI/Anthropic/Z.AI 차이 흡수
- **세션 기반 도구 레지스트리**: baseline만 노출, LLM이 `tools.enable`으로 추가 활성화
- **권한 시스템**: [spec/security.md](./spec/security.md) — safe/sensitive/restricted, 에이전트별 선언
