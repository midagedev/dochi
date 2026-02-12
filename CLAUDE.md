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
├── App/                          # DochiApp.swift (entry point)
├── Models/                       # Data models (LLMProvider, Message, Conversation, etc.)
├── State/                        # State machine enums (InteractionState, SessionState, ProcessingSubState)
├── ViewModels/                   # DochiViewModel (orchestrator)
├── Views/                        # SwiftUI views (ContentView, ConversationView, SettingsView)
├── Services/
│   ├── Protocols/                # Service protocols (ContextService, Conversation, Keychain, LLM, BuiltInTool)
│   ├── LLM/                      # LLMService + provider adapters (P1)
│   ├── Context/                  # ContextService — file-based context (P1)
│   ├── Conversation/             # ConversationService — conversation CRUD (P1)
│   ├── Keychain/                 # KeychainService — API key management (P1)
│   ├── Tools/                    # BuiltInToolService + individual tools (P1/P3)
│   ├── Speech/                   # SpeechService — Apple STT + wake word (P2)
│   ├── TTS/                      # SupertonicService — ONNX TTS (P2)
│   ├── MCP/                      # MCPService — MCP server proxy (P3)
│   ├── Telegram/                 # TelegramService — DM + streaming (P4)
│   └── Cloud/                    # SupabaseService — auth + sync (P4)
└── Utilities/                    # Log enum (os.Logger)

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

- `microsoft/onnxruntime-swift-package-manager` v1.20.0 (TTS)
- `modelcontextprotocol/swift-sdk` v0.10.2 (MCP)
- `supabase/supabase-swift` v2.0.0+ (Cloud sync)

## Logging

Subsystem: `com.dochi.app`. Categories: App, LLM, STT, TTS, MCP, Tool, Storage, Cloud.

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
