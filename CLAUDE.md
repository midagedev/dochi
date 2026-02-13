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
- 리라이트 계획: [spec/rewrite-plan.md](./spec/rewrite-plan.md)

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
