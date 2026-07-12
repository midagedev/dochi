# Native Agent Runtime Architecture

> 상태: **현행 정본**<br>
> 적용 대상: `Dochi` macOS 14+, `DochiMobile` iOS 17+, 로컬 package `../AgentRuntimeKit`<br>
> 마지막 코드 대조: 2026-07-12

이 문서는 Dochi의 인프로세스 Swift 에이전트 경계와 현재 보안 동작을 정의한다. macOS의 선택형
Hermes 경로는 [`../HermesBridge/README.md`](../HermesBridge/README.md)가 정본이다. 이 문서에
적혀 있지 않은 AgentRuntimeKit 기능은 Dochi에 연결된 것으로 간주하지 않는다.

## 1. 제품 경계

네이티브 에이전트가 기본 경로다. 모델 루프, 제공자 어댑터, 도구 정책, 기억, 체크포인트와 감사
이벤트는 앱 프로세스 안의 AgentRuntimeKit이 담당한다. 모델 추론은 사용자가 선택한 API 제공자
또는 OpenAI 호환 endpoint에서 수행한다.

```text
macOS
Speech/TTS/VRM/UI ─ DochiViewModel ─ AgentBackendProtocol ─ AgentBackendRouter
                                                             ├─ NativeAgentBackend ─ AgentRuntimeKit
                                                             └─ HermesAgentBridge ─ ws:// bridge

iOS
SwiftUI/Apple Speech/AVSpeechSynthesizer ─ MobileAgentController ─ AgentRuntimeKit
```

macOS의 `AgentBackendProtocol`은 UI가 어느 런타임을 쓰는지 알지 않게 하는 제품 경계다. 이
프로토콜에는 연결 상태, 대화 기록 교체/삭제, 사용자 입력과 스트리밍 제품 이벤트만 있다.
제공자 continuation, 기억 레코드와 도구 정책 타입은 `DochiViewModel`로 새지 않는다.

iOS는 Hermes를 포함하지 않으며 `MobileAgentController`가 AgentRuntimeKit host 역할을 직접 한다.
두 앱의 런타임 데이터는 서로 동기화하지 않는다.

## 2. 모듈과 host 책임

| 구성 요소 | 책임 | Dochi에서 사용하는 제품 |
| --- | --- | --- |
| `AgentRuntimeCore` | 제한된 모델/도구 루프, 스트림 이벤트, 도구 레지스트리·정책·승인, 체크포인트 계약 | macOS, iOS |
| `AgentRuntimeProviders` | 제공자 요청/스트림 파싱, 재시도, opaque continuation | macOS, iOS |
| `AgentRuntimeMemory` | exact-scope 기억, SQLite/FTS, 기억 도구와 보수적 저장 정책 | macOS, iOS |
| `AgentRuntimeApple` | Keychain, 보호 파일/SQLite, 축약 JSONL 감사 로그 | macOS, iOS |

`AgentRuntimeMCP`는 package에 존재하지만 현재 Dochi 네이티브 host는 MCP client나 MCP 도구를
등록하지 않는다. Hermes 백엔드의 도구·스킬은 Hermes가 별도로 관리하며 네이티브 host의 승인
정책이 적용된다고 가정하지 않는다.

Host가 반드시 소유하는 경계는 다음과 같다.

- 앱/사용자/대화/에이전트 식별자 생성과 전달
- provider, model, endpoint와 지침 설정
- Keychain 자격 증명 UI
- host에서 허용할 도구의 명시적 등록
- 승인 요청 표시와 결정 반환
- 대화의 표시용 영속화 및 provider 전환 시 기록 정리
- STT/TTS, 아바타, 햅틱, 접근성, 개인정보 권한

## 3. 제공자와 모델

두 네이티브 host가 연결한 제공자는 동일하다.

| Host 설정 값 | AgentRuntimeKit adapter | 편의 기본 모델 | 자격 증명 |
| --- | --- | --- | --- |
| `anthropic` | `AnthropicMessagesProvider` | `claude-sonnet-5` | 필수 |
| `openAI` | `OpenAIResponsesProvider` | `gpt-5.6` | 필수 |
| `gemini` | `GeminiGenerateContentProvider` | `gemini-3.5-flash` | 필수 |
| `openAICompatible` | `OpenAIChatCompletionsProvider` | 없음 | 선택 |

모델 이름은 제공자별로 UserDefaults에 따로 저장한다. 제공자를 바꿨을 때 이전 제공자의 모델
이름을 새 제공자에 잘못 사용하는 것을 막기 위한 분리다. 기본 모델은 설정 초기값이며 서버 가용성을
보장하는 고정 계약이 아니다.

OpenAI 호환 URL 규칙은 macOS와 iOS가 같다.

- 외부 host는 `https`만 허용한다.
- `http`는 `localhost`, `*.localhost`, `127.0.0.0/8`, `::1`에만 허용한다.
- URL user/password, query와 fragment를 거부한다.
- 입력 경로가 이미 `chat/completions`로 끝나면 그대로 사용한다.
- 빈 경로에는 `v1/chat/completions`, 다른 경로에는 `chat/completions`를 붙인다.

Provider adapter가 반환한 continuation은 provider 소유의 opaque 데이터다. Anthropic thinking
signature, Gemini thought signature, OpenAI reasoning/function output 같은 데이터를 host가 해석하거나
재구성하지 않는다.

## 4. 자격 증명과 BYOK

| 대상 | Keychain service/namespace | account | 저장 특성 |
| --- | --- | --- | --- |
| macOS | `com.hckim.dochi` | `agent-provider-<provider>-api-key` | macOS login Keychain generic password |
| iOS | `com.hckim.dochi.mobile` | `agent-provider-<provider>-api-key` | `whenUnlockedThisDeviceOnly` |

설정 UI와 provider resolver는 같은 namespace/account를 사용한다. 키는 `SecureField`에서 입력하고
Keychain에 저장하거나 삭제한다. 키 본문은 UserDefaults, 대화 스냅샷, 기억, 승인 감사 로그에 넣지
않는다. 오류와 로그에도 키 값을 포함하지 않는다.

Anthropic, OpenAI와 Gemini는 키가 없으면 연결/실행을 거부한다. OpenAI 호환 경로는 인증 없는
loopback 서버를 지원하기 위해 키가 선택 사항이다. 배포 바이너리에 서비스 공용 키를 내장하는
경로는 없다.

## 5. 로컬 기억과 삭제 의미

### 5.1 저장과 가시성

- macOS app ID: `com.hckim.dochi`
- iOS app ID: `com.hckim.dochi.mobile`
- macOS agent ID: `도치 네이티브`
- iOS agent ID: `도치`
- session ID: macOS 대화 UUID, iOS의 영속 UUID
- user ID: macOS 대화에 캡처된 optional 값, iOS 설치에서 생성해 유지하는 UUID

각 `MemoryScope`는 level뿐 아니라 app/user/agent/workspace/session 식별자 전체가 일치해야 한다.
store가 부모, 자식, 다른 사용자나 다른 대화 범위로 검색을 넓히지 않는다. Dochi의 현재 기억 도구가
모델에 허용하는 쓰기/검색 level은 `user`, `agent`, `workspace`, `session`이다. workspace metadata를
host가 전달하지 않으므로 현재 일반 Dochi 실행에서 workspace scope 요청은 성립하지 않는다.

`MemoryContextProvider`는 현재 요청의 application, 해당 user, 해당 agent와 해당 session에 맞는
범위만 조합한다. 문맥 자동 주입과 `memory.search`의 최대 민감도는 `privateData`다. secret은 기억으로
저장할 수 없고 모델 문맥으로도 나오지 않는다.

기억 저장은 다음 정책을 거친다.

- provenance와 최소 confidence가 없거나 부족하면 거부한다.
- secret은 항상 거부한다.
- 지속 지침은 승인 후 저장한다.
- 건강·금융 정보는 24시간 이내 TTL을 가진 session 기억이 아니면 승인 후 저장한다.
- 승인 대기 중인 본문은 프로세스 메모리의 승인 요청에만 있고 승인 전에는 SQLite에 쓰지 않는다.

macOS는 `~/Library/Application Support/Dochi/AgentRuntime/agent-memory.sqlite`, iOS는 앱 sandbox의
`Application Support/DochiMobile/agent-memory.sqlite`를 사용한다. 보호 wrapper가 DB와 WAL/SHM
sidecar의 권한과 Apple 파일 보호 속성을 다시 적용한다.

### 5.2 현재 삭제 동작

삭제 의미를 UI 문구에서 과장하지 않는다.

| 사용자 동작 | 실제 결과 |
| --- | --- |
| 기억 토글 끄기 | 기억 context와 `memory.save/search/archive` 등록을 해제한다. 저장된 레코드는 유지한다. |
| macOS 대화 삭제 | 표시용 대화 JSON과 exact app/user/session/agent 체크포인트를 삭제한다. 장기 기억은 유지한다. |
| iOS 새 대화 | 표시용 snapshot을 새 session으로 교체한다. 안전한 이전 체크포인트는 정리하지만 장기 기억은 유지한다. |
| iOS 기억 하나 영구 삭제 | 현재 app/user가 소유한 exact scope와 UUID를 다시 검증한 뒤 레코드·이벤트·FTS 흔적을 hard purge한다. |
| iOS 사용자 기억 전체 삭제 | 같은 app/user에 명시적으로 귀속된 과거 user/agent/workspace/session 레코드를 hard purge한다. application·user-unbound·다른 app/user 범위는 유지한다. |
| 제공자 API 키 삭제 | 선택한 provider의 Keychain 항목을 삭제한다. 대화/기억은 유지한다. |

iOS 설정의 `저장된 기억 관리`는 `recordsOwned(appID:userID:)`, exact `purge(id:scope:)`,
`purgeOwned(appID:userID:)`를 호출한다. 삭제 전 확인을 요구하고, agent run이나 다른 기억 작업 중에는
조회·삭제를 차단한다. SQLite는 secure delete, FTS rebuild와 WAL truncate를 수행한다. macOS에는 아직
동등한 장기 기억 목록·hard-delete UI가 없다.

## 6. 대화, 체크포인트와 continuation

Runtime instructions와 기억 context block은 각 provider 요청에만 임시로 합성하며 결과나 checkpoint
메시지에 복제하지 않는다.

### macOS

- 표시용 사용자/assistant 대화는 `Application Support/Dochi/conversations/<UUID>.json`에 저장한다.
- 런타임은 `Application Support/Dochi/AgentRuntime/checkpoints/`에 보호 checkpoint를 저장한다.
- 재시작 후 checkpoint를 재사용하려면 app/user/session/agent, provider, model이 모두 일치하고,
  모든 도구 실행이 완료되어 있으며, 마지막 메시지가 완결된 assistant 응답이고, 표시용 transcript가
  checkpoint transcript와 같아야 한다.
- 조건이 하나라도 다르면 provider-neutral 사용자/assistant 텍스트로 다시 구성한다.
- 대화를 삭제하면 해당 identity의 checkpoint를 삭제한다.

### iOS

- `Application Support/DochiMobile/conversation.json`은 전체 `AgentMessage` 기록과 provider/model ID를
  파일 보호로 저장하므로 같은 provider/model의 opaque continuation을 보존한다.
- provider 또는 model이 바뀌면 표시용 사용자/assistant 텍스트만 남기고 continuation, tool call과 tool
  result를 제거한 뒤 새 adapter에 전달한다.
- 실행은 checkpoint persistence를 필수로 요청한다. 성공한 run에서 관찰한 checkpoint ID만 정확히
  삭제하고, 중단된 run의 unresolved/non-idempotent ledger는 자동 재실행하거나 넓은 삭제로 지우지 않는다.
- 현재 mobile host는 남은 checkpoint를 `resumeFrom`으로 자동 재개하지 않는다.

두 host 모두 continuation 본문을 UI, 일반 대화 모델 또는 redacted audit detail로 노출하지 않는다.

## 7. 도구와 승인

현재 등록된 네이티브 도구는 의도적으로 작다.

| 도구 | macOS | iOS | 정책 |
| --- | --- | --- | --- |
| `current_time` | 예 | 아니요 | safe, 자동 허용 |
| `memory.save` | 예 | 예 | runtime preapproved 후 기억 content policy 적용 |
| `memory.search` | 예 | 예 | exact scope와 sensitivity 상한 안에서 허용 |
| `memory.archive` | 예 | 예 | sensitive + non-idempotent, host 승인과 durable ledger 필요 |

Runtime 기본 정책은 safe를 허용하고, preapproved되지 않은 sensitive 도구는 승인을 요구하며,
host allowlist에 없는 restricted 도구를 거부한다. 비멱등 도구는 실행 전후 durable checkpoint ledger가
필수이고 결과가 불명확하면 자동 재실행하지 않는다.

승인 UI는 도구 이름, 설명, risk, side effect, 사유와 허용된 인수만 표시한다. 알 수 없는 인수는
숨긴다. 민감 기억은 사용자가 판단할 수 있도록 실제 저장 본문을 로컬 승인 화면에서 보여주지만 그
본문은 감사 로그에 쓰지 않는다.

결정은 `allowOnce`, 조건부 `allowForSession`, `deny`다. `memory.persist_sensitive`, restricted,
non-idempotent 요청은 session 승인을 제공하지 않는다. 승인 화면 dismiss, run 취소, 새 대화와 앱
종료로 broker가 해제되면 pending 요청을 거부/취소한다.

## 8. iOS 개인정보와 음성

- `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`을 선언하고 실제 음성 입력을
  시작할 때 권한을 요청한다.
- `SFSpeechRecognizer`가 on-device recognition을 지원하면 `requiresOnDeviceRecognition = true`로
  설정한다. 지원하지 않는 경우 Apple Speech framework의 처리 경로를 따른다.
- 음성 입력 오디오는 선택한 LLM provider로 보내지 않는다. 인식된 텍스트는 사용자가 전송하면
  메시지로 provider에 전달된다.
- scene이 inactive가 되거나 화면이 사라지면 녹음과 TTS를 중단한다.
- 최종 assistant 답변 읽기는 `AVSpeechSynthesizer` 한국어 음성을 사용한다.
- `PrivacyInfo.xcprivacy`는 tracking 없음, 기능/개인화 목적의 user content, UserDefaults와 file
  timestamp required-reason API를 선언한다.
- 외부 OpenAI 호환 endpoint는 HTTPS만 허용하고, local network 용도 설명과 loopback HTTP 예외만 둔다.
- 대화/continuation/tool result snapshot, checkpoint, memory와 audit 파일에는 파일 보호를 적용하고
  API 키는 `whenUnlockedThisDeviceOnly` Keychain에 둔다.

iOS의 7종 2D 아바타는 macOS에 포함된 CC0 VRM의 preview다. iOS target은 현재 VRM 3D 렌더링이나
얼굴 추적을 포함하지 않는다.

## 9. 감사와 로그

네이티브 runtime audit은 redaction policy를 적용한 JSON Lines로 저장한다.

- macOS: `~/Library/Application Support/Dochi/AgentRuntime/agent-audit.jsonl`
- iOS: app sandbox `Application Support/DochiMobile/agent-audit.jsonl`

Audit write 실패는 앱 실행을 중단하지 않으며 레코드 내용이나 underlying error text를 다시 로그하지
않는다. 일반 앱 로그는 `Log.*`/`os.Logger`를 사용한다. API 키, 민감 기억 본문과 provider continuation을
로그하면 안 된다.

## 10. 검증 명령

`project.yml` 변경 후 먼저 Xcode project를 재생성한다.

```bash
xcodegen generate
```

```bash
# macOS build + tests
xcodebuild -project Dochi.xcodeproj -scheme Dochi \
  -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Dochi.xcodeproj -scheme Dochi \
  -configuration Debug -destination 'platform=macOS' test

# iOS simulator-compatible build
xcodebuild -project Dochi.xcodeproj -scheme DochiMobile \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

# macOS startup verification
./script/build_and_run.sh --verify
```

Hermes protocol 검증 명령은 [`../HermesBridge/README.md`](../HermesBridge/README.md)에만 유지한다.
