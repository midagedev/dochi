# Dochi (도치)

**Dochi는 macOS와 iPhone에서 동작하는 음성·아바타 AI 동반자입니다.** 기본 경로는
[AgentRuntimeKit](https://github.com/midagedev/AgentRuntimeKit)을 앱 프로세스 안에서 실행하는 순수 Swift 에이전트이며,
macOS에서는 기존 Hermes WebSocket 브리지를 선택 백엔드로 계속 사용할 수 있습니다.

```text
macOS: 말/텍스트 ─▶ DochiViewModel ─▶ AgentBackendRouter ─┬─▶ AgentRuntimeKit (기본)
                                                           └─▶ HermesBridge (선택)
          답변 ◀─ TTS + VRM 아바타 ◀─ 스트리밍 델타/도구 상태 ─┘

iOS:   말/텍스트 ─▶ MobileAgentController ─▶ AgentRuntimeKit ─▶ 선택한 모델 제공자
          답변 ◀─ 시스템 TTS + 2D 아바타 ◀─ 스트리밍 답변/도구 상태 ─┘
```

네이티브 경로에는 Python이나 별도 에이전트 서버가 필요하지 않습니다. 모델 추론 자체는 사용자가
선택한 API 제공자 또는 OpenAI 호환 서버에서 수행됩니다.

## 현재 기능

| 영역 | macOS `Dochi` | iOS `DochiMobile` |
| --- | --- | --- |
| 에이전트 | 인프로세스 Swift 기본, Hermes 브리지 선택 가능 | 인프로세스 Swift |
| 모델 | Anthropic, OpenAI, Gemini, OpenAI 호환 | Anthropic, OpenAI, Gemini, OpenAI 호환 |
| 입력 | 텍스트, Apple STT, 웨이크워드 | 텍스트, Apple Speech |
| 출력 | 스트리밍 텍스트, 시스템/Google Cloud/Typecast/Supertonic TTS | 스트리밍 텍스트, 시스템 TTS |
| 아바타 | 7종 CC0 VRM 3D 모델, 표정·립싱크 | 같은 모델의 7종 2D 미리보기 |
| 기억 | 범위가 분리된 로컬 SQLite 기억 | 범위가 분리된 로컬 SQLite 기억 |
| 도구 | 현재 시각, 기억 저장·검색·보관 | 기억 저장·검색·보관 |

## 빠른 시작

### 요구 사항

- macOS 14 이상, iOS 17 이상
- Xcode와 [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- 이 저장소와 `AgentRuntimeKit`이 같은 상위 디렉터리에 있는 체크아웃

```text
repo/
├── AgentRuntimeKit/
└── dochi/
```

`project.yml`은 공개 Swift package `AgentRuntimeKit`의 `0.1.x` 릴리스를 참조합니다.

### 프로젝트 생성과 macOS 실행

```bash
brew install xcodegen
cd /path/to/dochi
xcodegen generate
xcodebuild -project Dochi.xcodeproj -scheme Dochi \
  -configuration Debug -destination 'platform=macOS' build
./script/build_and_run.sh --verify
```

전체 macOS 테스트:

```bash
xcodebuild -project Dochi.xcodeproj -scheme Dochi \
  -configuration Debug -destination 'platform=macOS' test
```

### iPhone 빌드와 실행

서명 없이 시뮬레이터용 빌드를 확인할 수 있습니다.

```bash
xcodebuild -project Dochi.xcodeproj -scheme DochiMobile \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

실행하려면 `Dochi.xcodeproj`를 Xcode에서 열고 `DochiMobile` scheme과 iOS 17 이상 시뮬레이터를
선택한 뒤 Run을 누릅니다. 실제 iPhone 배포에는 자신의 Development Team과 서명 설정이 필요합니다.

## 처음 설정하기

### macOS

1. **설정 → 에이전트 → 실행 방식**에서 기본값인 **기기 내 Swift 에이전트**를 선택합니다.
2. Anthropic, OpenAI, Google Gemini 또는 OpenAI 호환 제공자를 선택합니다.
3. 모델 이름과 개인 API 키를 입력하고 **키 저장**, **설정 적용**을 누릅니다.
4. 필요에 따라 **로컬 장기 기억**과 에이전트 지침을 조정합니다.
5. **말하기/아바타**에서 TTS와 VRM 아바타를 선택합니다.

### iOS

대화 화면의 아바타/설정 버튼을 열어 제공자, 모델, API 키, 기억, 음성 입력, 답변 읽기와
아바타를 설정합니다. 마이크와 음성 인식 권한은 음성 입력을 실제로 시작할 때 요청합니다.

기본 모델 이름은 제공자별 편의 기본값일 뿐이며 설정에서 바꿀 수 있습니다.

| 제공자 | 기본 모델 | API 경로 |
| --- | --- | --- |
| Anthropic | `claude-sonnet-5` | Messages API |
| OpenAI | `gpt-5.6` | Responses API |
| Google Gemini | `gemini-3.5-flash` | GenerateContent API |
| OpenAI 호환 | 사용자가 입력 | Chat Completions API |

OpenAI 호환 서버는 외부 주소일 때 HTTPS만 허용합니다. HTTP는 `localhost`, `127.0.0.0/8`,
`::1` 같은 loopback 주소에만 허용되며, Base URL만 입력하면 앱이 `chat/completions` 경로를 붙입니다.

## BYOK, 기억과 승인

- **BYOK:** API 키는 제공자별 Keychain 항목에만 저장합니다. UserDefaults, 대화 파일, 기억 DB,
  감사 로그에 키를 저장하지 않습니다. 서비스 공용 키를 앱에 넣는 배포 방식은 지원하지 않습니다.
- **전송 범위:** 메시지 텍스트, 필요한 로컬 기억 문맥과 도구 결과는 답변 생성을 위해 선택한 모델
  제공자로 전송됩니다. iOS 음성 입력의 원본 오디오는 선택한 모델 제공자에 보내지 않습니다.
- **로컬 기억:** 기억은 앱·사용자·에이전트·대화 식별자로 범위를 나눠 로컬 SQLite에 저장합니다.
  비밀값은 기억으로 저장할 수 없고, 건강·금융 정보나 지속 지침 같은 민감한 장기 기억은 저장 전에
  앱 안에서 내용을 보여주고 승인을 받습니다.
- **도구 승인:** safe 도구와 host가 좁게 사전 허용한 기억 검색·정책 제어 저장만 자동으로
  진행합니다. 그 밖에 승인이 필요한 도구는 이름, 위험도, 부작용과 안전하게 요약한 인수를 보여주며
  **한 번 허용**, 조건을 만족할 때만 **이번 대화에서 허용**, 또는 **거부**를 선택하게 합니다.
  승인 화면을 닫아도 거부로 처리합니다.
- **삭제와 관리:** 기억 토글을 끄면 검색·저장 도구와 문맥 주입만 비활성화되고 기존 기억은
  유지됩니다. iOS의 **저장된 기억 관리**에서는 현재 사용자에게 귀속된 과거 대화 기억까지 열람하고,
  한 레코드 또는 사용자 소유 전체를 확인 후 물리 삭제할 수 있습니다. 이 삭제는 SQLite 본문·이벤트·
  검색 색인과 WAL을 정리하면서 다른 앱·사용자·앱 전체 범위는 보존합니다. macOS에는 아직 같은
  장기 기억 관리 화면이 없으며, 대화 삭제는 대화 파일과 그 대화의 체크포인트만 지웁니다.

런타임의 SQLite DB/WAL/SHM, 체크포인트와 축약 감사 로그에는 제한된 파일 권한과 Apple 파일 보호를
적용합니다. iOS 대화 스냅샷도 파일 보호로 저장합니다. macOS의 표시용 대화 기록은
`~/Library/Application Support/Dochi/conversations/` 아래 JSON 파일입니다.

## 음성과 아바타

- macOS는 Apple STT와 웨이크워드(기본값 `도치야`), 시스템/Google Cloud/Typecast/로컬
  Supertonic TTS, RealityKit 기반 VRM 아바타와 립싱크를 제공합니다.
- iOS는 Apple Speech를 사용하며 기기가 지원하면 on-device recognition을 요구합니다. 최종 답변은
  `AVSpeechSynthesizer`의 한국어 음성으로 읽을 수 있습니다.
- 7종 아바타의 원본, 라이선스와 SHA-256은
  [`Dochi/Resources/Models/README.md`](./Dochi/Resources/Models/README.md)에 기록되어 있습니다.
  iOS 미리보기 출처는 [`DochiMobile/Resources/README.md`](./DochiMobile/Resources/README.md)를 참고하세요.

## 선택 경로: Hermes 브리지

Hermes 경로는 macOS에서만 제공되는 선택 백엔드입니다. 기존 Hermes의 도구·스킬이 필요할 때
**설정 → 에이전트 → Hermes 원격 브리지**로 전환합니다.

```bash
cd HermesBridge
python -m venv .venv && source .venv/bin/activate
pip install -e .
python -m dochi_hermes_bridge --echo
```

실제 Hermes 설치와 프로토콜 테스트는 [`HermesBridge/README.md`](./HermesBridge/README.md)를
따릅니다. 클라이언트는 `ws://`를 localhost/127.0.0.0/8/::1에만 허용합니다. LAN이나 인터넷의
브리지는 loopback에 그대로 두고 TLS reverse proxy를 앞에 배치한 뒤 설정에 `wss://` 주소를
입력해야 합니다. 외부 호스트를 scheme 없이 입력해도 안전한 기본값인 `wss://`로 해석합니다.
공유 토큰은 `~/.hermes/dochi_bridge_token` 또는 `DOCHI_BRIDGE_TOKEN`에서 읽습니다.

## 저장소 구조

```text
Dochi/                    macOS 앱: 음성/TTS/VRM/UI + 백엔드 라우터
DochiMobile/              iOS 앱: 채팅/음성/2D 아바타 + 네이티브 런타임 호스트
DochiTests/               macOS XCTest
DochiMobileTests/         iOS XCTest
HermesBridge/             선택형 Python WebSocket 브리지
spec/native-agent-runtime.md  현행 네이티브 에이전트 아키텍처 정본
project.yml               XcodeGen 정본
```

아키텍처와 보안 경계는 [`spec/native-agent-runtime.md`](./spec/native-agent-runtime.md),
문서의 현행/역사적 구분은 [`spec/README.md`](./spec/README.md)를 참고하세요.
