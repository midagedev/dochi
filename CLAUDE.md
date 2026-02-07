# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **See also:** [CONCEPT.md](./CONCEPT.md) for product vision, [ROADMAP.md](./ROADMAP.md) for planned features

## Build Commands

```bash
# Generate Xcode project from project.yml (required after changing project.yml)
xcodegen generate

# Build
xcodebuild -project Dochi.xcodeproj -scheme Dochi -configuration Debug build

# Run tests
xcodebuild -project Dochi.xcodeproj -scheme DochiTests -configuration Debug test

# Run the built app
open ~/Library/Developer/Xcode/DerivedData/Dochi-*/Build/Products/Debug/Dochi.app
```

## Architecture

Dochi is a macOS SwiftUI voice assistant with:
- Multi-provider LLM chat (OpenAI, Anthropic, Z.AI)
- Apple STT input
- Local Supertonic TTS output via ONNX Runtime

### Data Flow

```
Mic → SpeechService(STT) → LLMService(SSE stream) → SupertonicService(ONNX TTS) → AVAudioPlayerNode
```

TTS streams sentence-by-sentence: `LLMService.onSentenceReady` fires on each newline boundary during SSE streaming, feeding sentences into `SupertonicService.enqueueSentence()` which runs a queue-based synthesis/playback loop.

### Continuous Conversation Mode

When wake word is enabled, sessions follow this flow:

1. **Wake word detected** → `isSessionActive = true`, STT starts
2. **User speaks** → LLM processes → TTS plays response
3. **TTS complete** → Continuous STT starts (10s timeout, no wake word needed)
4. **User continues** → Loop back to step 2
5. **10s silence** → TTS asks "대화를 종료할까요?"
6. **Positive response** or **another 10s silence** → Session ends, context analyzed, wake word listening resumes
7. **User can also say** "대화 종료", "그만할게", etc. to end session directly

### Project Structure

```
Dochi/
├── Models/
│   ├── Settings.swift        # AppSettings with DI
│   ├── Conversation.swift
│   ├── Message.swift
│   └── Enums.swift           # LLMProvider, SupertonicVoice
├── ViewModels/
│   └── DochiViewModel.swift  # Central orchestrator
├── Views/
│   ├── ContentView.swift
│   ├── SettingsView.swift
│   ├── ConversationView.swift
│   └── ChangelogView.swift
├── Services/
│   ├── Protocols/            # Service protocols for DI
│   │   ├── ContextServiceProtocol.swift
│   │   ├── ConversationServiceProtocol.swift
│   │   ├── KeychainServiceProtocol.swift
│   │   └── SoundServiceProtocol.swift
│   ├── BuiltInTools/         # Built-in tool modules
│   │   ├── BuiltInToolProtocol.swift
│   │   ├── WebSearchTool.swift
│   │   ├── RemindersTool.swift
│   │   ├── AlarmTool.swift
│   │   └── ImageGenerationTool.swift
│   ├── BuiltInToolService.swift  # Tool router
│   ├── LLMService.swift
│   ├── SpeechService.swift
│   ├── SupertonicService.swift
│   ├── ContextService.swift
│   ├── ConversationService.swift
│   ├── KeychainService.swift
│   ├── SoundService.swift
│   ├── ChangelogService.swift
│   └── Supertonic/           # TTS helpers
└── Resources/
    └── CHANGELOG.md

DochiTests/
├── Mocks/                    # Mock implementations for testing
│   ├── MockContextService.swift
│   ├── MockConversationService.swift
│   ├── MockKeychainService.swift
│   └── MockSoundService.swift
└── Services/
    ├── ContextServiceTests.swift
    └── ConversationServiceTests.swift
```

### Key Components

**DochiViewModel** (`ViewModels/DochiViewModel.swift`) — Central orchestrator. Owns all services, manages `State` (idle/listening/processing/speaking) and `isSessionActive` for continuous conversation. Forwards child `objectWillChange` via Combine for SwiftUI reactivity.

**Services** — Each is `@MainActor ObservableObject` communicating via closure callbacks. Static services (ContextService, ConversationService, KeychainService, SoundService) are protocol-based for testability:

| Service | Protocol | Description |
|---------|----------|-------------|
| LLMService | - | SSE streaming for 3 providers |
| SupertonicService | - | ONNX TTS with queue-based playback |
| SpeechService | - | Apple STT with wake word detection |
| ContextService | ContextServiceProtocol | Prompt file management |
| ConversationService | ConversationServiceProtocol | Conversation history storage |
| KeychainService | KeychainServiceProtocol | API key storage |
| SoundService | SoundServiceProtocol | UI sound effects |
| ChangelogService | - | Version tracking and changelog |

**Callbacks in SpeechService:**
- `onQueryCaptured` — STT result ready
- `onWakeWordDetected` — Wake word matched
- `onSilenceTimeout` — Continuous listening timed out with no speech

### Dependency Injection

Services are injected via init parameters with default implementations:

```swift
// AppSettings
init(keychainService: KeychainServiceProtocol = KeychainService(),
     contextService: ContextServiceProtocol = ContextService())

// DochiViewModel
init(settings: AppSettings,
     contextService: ContextServiceProtocol = ContextService(),
     conversationService: ConversationServiceProtocol = ConversationService())

// SpeechService
init(soundService: SoundServiceProtocol = SoundService())
```

For testing, inject mock implementations:
```swift
let mockContext = MockContextService()
let settings = AppSettings(contextService: mockContext)
```

### Prompt Files

```
~/Library/Application Support/Dochi/
├── system.md    # Persona + behavior guidelines (manual edit)
├── memory.md    # User info (auto-accumulated)
└── conversations/
    └── {uuid}.json  # Saved conversations
```

**system.md** — AI identity and instructions, edited manually via sidebar
**memory.md** — User memory, auto-populated on session end:
1. `saveAndAnalyzeConversation()` sends conversation to LLM for analysis
2. Extracted info appended to `memory.md` with timestamp
3. `buildInstructions()` includes both files in system prompt
4. Auto-compression when exceeding `contextMaxSize` (default 15KB)

### LLM Provider Details

| Provider | Auth | Body quirk |
|----------|------|------------|
| OpenAI | `Bearer` header | Standard OpenAI chat format |
| Anthropic | `x-api-key` + `anthropic-version` headers | `system` as top-level field, no system role in messages |
| Z.AI | `Bearer` header | OpenAI-compatible; `"enable_thinking": false` to disable reasoning; model `glm-4.7` |

### Conventions

- All ViewModels and Services use `@MainActor`
- Swift concurrency with `async/await` and `Task` for background work; `Task.detached` for CPU-heavy ONNX inference
- UI language is Korean
- XcodeGen (`project.yml`) generates the `.xcodeproj` — edit `project.yml`, not the Xcode project directly
- External dependency: `microsoft/onnxruntime-swift-package-manager` v1.20.0, imported as `OnnxRuntimeBindings`
- Supertonic helpers (`SupertonicHelpers.swift`) prefix all types with `Supertonic` to avoid namespace collisions
- Wake word variations generated via LLM to improve STT matching accuracy
- Protocol-based services enable easy mocking for unit tests

### Testing

Tests are in `DochiTests/` target. Run with:
```bash
xcodebuild -project Dochi.xcodeproj -scheme DochiTests test
```

Current test coverage:
- ContextService: 10 tests (file operations, memory management)
- ConversationService: 7 tests (CRUD operations)

Mock services are provided in `DochiTests/Mocks/` for testing components that depend on services.
