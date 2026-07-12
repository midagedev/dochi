# CLAUDE.md

## 제품 정의

**Dochi는 [Hermes Agent](https://github.com/NousResearch/hermes-agent)의 음성·캐릭터 프론트엔드입니다.**

- Dochi가 담당: 한국어 STT(웨이크워드 포함), TTS(시스템/Google Cloud/Typecast/로컬 ONNX), VRM 3D 아바타와 립싱크, macOS 네이티브 UI.
- Hermes가 담당: 추론(LLM 루프), 영속 메모리, 스킬, 도구 실행, MCP.
- 둘을 잇는 것: 로컬 WebSocket 브리지 (`HermesBridge/` — Python). Dochi는 음성을 텍스트로 바꿔 보내고, 스트리밍 응답(델타/도구 이벤트)을 받아 말하고 표정짓습니다.

> 과거 Dochi는 자체 LLM 루프·도구(35+)·칸반·텔레그램·클라우드 동기화까지 떠안아 ~102K줄로 비대해졌습니다. 그 "두뇌" 영역을 Hermes에 위임하고 음성/캐릭터 인터페이스에 집중하도록 ~8K줄로 전면 재작성했습니다.

## Build Commands

```bash
# project.yml 변경 후 Xcode 프로젝트 재생성
xcodegen generate

# 빌드 / 테스트 / 실행
xcodebuild -project Dochi.xcodeproj -scheme Dochi -configuration Debug build
xcodebuild -project Dochi.xcodeproj -scheme Dochi -configuration Debug -destination 'platform=macOS' test
open ~/Library/Developer/Xcode/DerivedData/Dochi-*/Build/Products/Debug/Dochi.app
```

### Hermes 브리지 (백엔드)

```bash
cd HermesBridge
python -m venv .venv && source .venv/bin/activate
pip install -e .                      # 브리지만 (echo 모드 가능)
pip install hermes-agent              # 실제 Hermes (Nous Research, 검증: 0.15.2)
python -m dochi_hermes_bridge --echo  # Hermes 없이 음성 파이프라인 검증
hermes setup                          # Hermes에 LLM 프로바이더 1회 설정 (또는 hermes model)
python -m dochi_hermes_bridge         # 설치/설정된 Hermes Agent 구동
# 프로바이더를 직접 지정 (config 없이):
#   python -m dochi_hermes_bridge --base-url http://127.0.0.1:11434/v1 --provider openai --model qwen2.5 --api-key x
PYTHONPATH=. python tests/test_echo_roundtrip.py     # 프로토콜 라운드트립
PYTHONPATH=. python tests/test_hermes_roundtrip.py   # 풀스택: 브리지→실제 Hermes→(목)모델
```

실제 연동은 `run_agent.AIAgent(...).run_conversation(...)`를 사용하며 Hermes의
`stream_delta_callback`/`tool_start_callback`/`tool_complete_callback`을 브리지 이벤트로 매핑(`runtime.py`).
LLM 프로바이더 미설정 시 `No LLM provider configured. Run \`hermes model\`…` 에러로 안내됩니다.

## Code Structure

```
Dochi/                               # ~9K줄, 56 Swift 파일
├── App/DochiApp.swift               # 진입점 + AppDelegate (최소 wiring)
├── Models/                          # 값 타입: Message, Conversation, AppSettings,
│                                    #   TTSProvider, SupertonicVoice, AvatarModelCatalog,
│                                    #   ToolExecution/ToolResult/ToolCategory, FeedbackModels 등
├── State/                           # InteractionState / SessionState / ProcessingSubState
├── ViewModels/DochiViewModel.swift  # 음성 오케스트레이터 (STT→Hermes→TTS→아바타)
├── Views/                           # ContentView, ConversationView, MessageBubbleView,
│                                    #   AvatarView, SettingsView + 메시지 배지/카드 뷰
├── Services/
│   ├── Protocols/                   # Speech/TTS/Conversation/Keychain/FeedbackStore 프로토콜
│   ├── Hermes/HermesAgentBridge.swift   # Hermes 브리지 WebSocket 클라이언트 (핵심 seam)
│   ├── Speech/                      # SpeechService — Apple STT + 웨이크워드
│   ├── TTS/                         # TTSRouter + System/GoogleCloud/Typecast/Supertonic(ONNX)
│   ├── Avatar/                      # AvatarManager + FaceTrackingService — VRM 3D 아바타
│   ├── Conversation/                # ConversationService — 대화 CRUD (파일 기반)
│   ├── Sound/ Keychain/             # 효과음, API 키 보관
│   └── FeedbackStore.swift          # 메시지 피드백 저장(선택)
├── Resources/ (Assets, Models[VRM, gitignored])
└── Utilities/                       # Log, SentenceChunker, JamoMatcher

HermesBridge/                        # Python: Dochi↔Hermes 게이트웨이 어댑터
└── dochi_hermes_bridge/             # protocol / runtime / server / token + tests

DochiTests/                          # XCTest + Mocks (음성 루프, 브리지, 청커, 대화 CRUD)
```

## Architecture

```
사용자 ──말──▶ SpeechService(STT) ──텍스트──▶ DochiViewModel ──▶ HermesAgentBridge ──ws──▶ dochi-hermes-bridge ──▶ Hermes Agent
사용자 ◀─말/표정─ AvatarView + TTSRouter ◀─문장(SentenceChunker)─ DochiViewModel ◀─델타/도구 이벤트◀──────────────────────┘
```

핵심 설계:
- **명시적 상태 머신**: `InteractionState`(idle/listening/processing/speaking) + `SessionState` + `ProcessingSubState`. 전환 검증은 `DochiViewModel.validateTransition`.
- **음성 루프 seam**: `DochiViewModel.processHermesPath` 가 텍스트를 Hermes로 보내고 `HermesEvent` 스트림(delta/toolStarted/toolFinished/done)을 소비. 음성 모드에서는 델타를 `SentenceChunker`로 문장 단위로 끊어 `TTSRouter.enqueueSentence`에 흘리고, TTS `onComplete`가 다시 청취로 전환.
- **연결 진실 원천**: `HermesAgentBridge.connectionState` (UI 미러는 `DochiViewModel.hermesConnection`).
- **프로액티브**: Hermes가 보낸 `proactive` 프레임 → `injectProactiveMessage`.
- **와이어 프로토콜**: `HermesBridge/dochi_hermes_bridge/protocol.py` 가 정본.

## Conventions

- `@MainActor` on ViewModels/Services; Swift 6.0 `SWIFT_STRICT_CONCURRENCY: targeted`
- `async/await` + 구조적 동시성; `Task.detached`는 CPU-heavy(ONNX)에만
- 로깅은 `Log.*` (os.Logger) — `print()` 금지
- UI 언어: 한국어
- XcodeGen(`project.yml`)이 `.xcodeproj` 생성 — `project.yml`을 편집. `Dochi/` 하위 파일은 자동 포함
- Protocol 기반 DI — 테스트는 Mock 주입
- macOS 14+ (아바타 렌더링 경로는 macOS 15+ `@available` 게이트)
- **기능 구현 = 코드 + 테스트**: 빌드 후 `xcodebuild test` 통과 필수
- **설계 원칙**: 레거시 보존보다 구조 개선 우선. 두뇌(추론/도구/메모리)는 Dochi에 다시 들이지 말고 Hermes에 둘 것

## Testing

```bash
xcodebuild -project Dochi.xcodeproj -scheme Dochi -destination 'platform=macOS' test \
  -only-testing:DochiTests/DochiViewModelTests
```

- `DochiTests/Mocks/MockServices.swift` — 보존 프로토콜 + `MockHermesBridge`
- `DochiViewModelTests` — 텍스트/음성 전송, 연결 끊김 에러, 도구 이벤트, 프로액티브
- `ConversationServiceTests` — 저장/로드/삭제 (`ConversationService(baseURL:)` 임시 디렉토리)
- `SentenceChunkerTests` — 문장 경계/소수점/flush
- 날짜는 ISO 8601, 저장→로드 roundtrip 커버

## External Dependencies

- `microsoft/onnxruntime-swift-package-manager` v1.20.0 (로컬 TTS ONNX)
- `tattn/VRMKit` v0.5.0 (VRM 3D 아바타 — VRMKit + VRMRealityKit)
- (Python) `websockets` — 브리지 서버

## Logging

Subsystem: `com.dochi.app`. Categories: App, STT, TTS, Avatar, Storage.

```bash
log show --predicate 'subsystem == "com.dochi.app"' --last 5m --style compact
```

## Context Structure

```
~/Library/Application Support/Dochi/
└── conversations/{id}.json          # 로컬 대화 기록 (기억/프로필은 Hermes가 보관)
~/.hermes/dochi_bridge_token         # 브리지 공유 토큰 (0600)
```
