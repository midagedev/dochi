# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Generate Xcode project from project.yml (required after changing project.yml)
xcodegen generate

# Build
xcodebuild -project Dochi.xcodeproj -scheme Dochi -configuration Debug build

# Run the built app
open ~/Library/Developer/Xcode/DerivedData/Dochi-*/Build/Products/Debug/Dochi.app
```

No tests exist. No linter is configured.

## Architecture

Dochi is a macOS SwiftUI voice assistant with two operational modes:

- **Realtime mode**: OpenAI Realtime API via WebSocket — bidirectional audio streaming, server-side VAD, built-in transcription and voice synthesis
- **Text mode**: Multi-provider LLM chat (OpenAI, Anthropic, Z.AI) with Apple STT input and local Supertonic TTS output via ONNX Runtime

### Data Flow

```
Realtime:  Mic → AVAudioEngine → WebSocket (PCM16 base64) → OpenAI Realtime → Audio playback
Text:      Mic → SpeechService(STT) → LLMService(SSE stream) → SupertonicService(ONNX TTS) → AVAudioPlayerNode
```

Text mode streams TTS sentence-by-sentence: `LLMService.onSentenceReady` fires on each newline boundary during SSE streaming, feeding sentences into `SupertonicService.enqueueSentence()` which runs a queue-based synthesis/playback loop.

### Continuous Conversation Mode

When wake word is enabled, sessions follow this flow:

1. **Wake word detected** → `isSessionActive = true`, STT starts
2. **User speaks** → LLM processes → TTS plays response
3. **TTS complete** → Continuous STT starts (10s timeout, no wake word needed)
4. **User continues** → Loop back to step 2
5. **10s silence** → TTS asks "대화를 종료할까요?"
6. **Positive response** or **another 10s silence** → Session ends, context analyzed, wake word listening resumes
7. **User can also say** "대화 종료", "그만할게", etc. to end session directly

### Key Components

**DochiViewModel** (`ViewModels/DochiViewModel.swift`) — Central orchestrator. Owns all services, routes between modes, manages `TextModeState` (idle/listening/processing/speaking) and `isSessionActive` for continuous conversation. Forwards child `objectWillChange` via Combine for SwiftUI reactivity.

**Services** — Each is `@MainActor ObservableObject` communicating via closure callbacks:
- `RealtimeService` — WebSocket lifecycle, audio capture/playback at 24kHz PCM16
- `LLMService` — SSE streaming for 3 providers; sentence detection splits on `\n`
- `SupertonicService` — ONNX model loading (downloaded from HuggingFace on first use), queue-based TTS with configurable `speed` and `diffusionSteps`
- `SpeechService` — Apple Speech framework STT with wake word detection and continuous listening mode (`startContinuousListening` with timeout)
- `ContextService` — Prompt file management (`~/Library/Application Support/Dochi/system.md` for persona, `memory.md` for user info)
- `KeychainService` — File-based API key storage

**Callbacks in SpeechService:**
- `onQueryCaptured` — STT result ready
- `onWakeWordDetected` — Wake word matched
- `onSilenceTimeout` — Continuous listening timed out with no speech

**Models:**
- `Enums.swift` — `AppMode`, `LLMProvider` (with per-provider models, API URLs), `SupertonicVoice`
- `Settings.swift` — `AppSettings` persists to UserDefaults; includes `ttsSpeed`, `ttsDiffusionSteps`

### Prompt Files

```
~/Library/Application Support/Dochi/
├── system.md    # Persona + behavior guidelines (manual edit)
└── memory.md    # User info (auto-accumulated)
```

**system.md** — AI identity and instructions, edited manually via sidebar
**memory.md** — User memory, auto-populated on session end:
1. `extractAndSaveContext()` sends conversation to LLM for analysis
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
