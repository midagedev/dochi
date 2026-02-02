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

### Key Components

**DochiViewModel** (`ViewModels/DochiViewModel.swift`) — Central orchestrator. Owns all services, routes between modes, manages `TextModeState` (idle/listening/processing/speaking). Forwards child `objectWillChange` via Combine for SwiftUI reactivity.

**Services** — Each is `@MainActor ObservableObject` communicating via closure callbacks (`onResponseComplete`, `onSentenceReady`, `onSpeakingComplete`, `onQueryCaptured`):
- `RealtimeService` — WebSocket lifecycle, audio capture/playback at 24kHz PCM16
- `LLMService` — SSE streaming for 3 providers; sentence detection splits on `\n`
- `SupertonicService` — ONNX model loading (downloaded from HuggingFace on first use to `~/Library/Application Support/Dochi/supertonic/`), queue-based TTS with reusable AVAudioEngine
- `SpeechService` — Apple Speech framework STT with wake word detection
- `KeychainService` — File-based API key storage in `~/Library/Application Support/Dochi/key_<provider>`

**Models:**
- `Enums.swift` — `AppMode`, `LLMProvider` (with per-provider models, API URLs, keychain accounts), `SupertonicVoice`
- `Settings.swift` — `AppSettings` persists to UserDefaults; API keys via KeychainService

### LLM Provider Details

| Provider | Auth | Body quirk |
|----------|------|------------|
| OpenAI | `Bearer` header | Standard OpenAI chat format |
| Anthropic | `x-api-key` + `anthropic-version` headers | `system` as top-level field, no system role in messages |
| Z.AI | `Bearer` header | OpenAI-compatible; `"enable_thinking": false` to disable reasoning |

### Conventions

- All ViewModels and Services use `@MainActor`
- Swift concurrency with `async/await` and `Task` for background work; `Task.detached` for CPU-heavy ONNX inference
- UI language is Korean
- XcodeGen (`project.yml`) generates the `.xcodeproj` — edit `project.yml`, not the Xcode project directly
- External dependency: `microsoft/onnxruntime-swift-package-manager` v1.20.0, imported as `OnnxRuntimeBindings`
- Supertonic helpers (`SupertonicHelpers.swift`) prefix all types with `Supertonic` to avoid namespace collisions
