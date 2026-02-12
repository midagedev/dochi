# Dochi 리라이트 실행 프롬프트

아래 프롬프트를 새 Claude Code 세션에 붙여넣어 실행하세요.

---

## 프롬프트

```
너는 macOS SwiftUI 앱 "Dochi"를 처음부터 재작성하는 작업을 수행한다.

## 핵심 규칙
- 모든 설계 결정은 `spec/` 문서를 정본으로 따른다. 추측하지 말고 스펙을 읽어라.
- 각 Phase 완료 시 빌드 확인(`xcodegen generate && xcodebuild ...`)을 반드시 수행한다.
- 각 Phase 완료 시 git commit한다 (브랜치: `rewrite/phase-N`).
- 서브에이전트를 적극 활용하여 독립적인 파일들은 병렬로 작성한다.
- Swift 6.0, @MainActor, async/await, os.Logger(`Log` enum), 프로토콜 기반 DI를 준수한다.
- print() 금지. UI 언어 한국어. XcodeGen으로 프로젝트 생성.

## 사전 준비
1. 아래 스펙 문서를 모두 읽어라 (이 순서로):
   - spec/README.md (정본 규칙)
   - spec/states.md (상태 머신 — 가장 중요)
   - spec/flows.md (플로우 + 에러 케이스)
   - spec/models.md (데이터 모델 + Phase 태그)
   - spec/interfaces.md (서비스 인터페이스)
   - spec/llm-requirements.md (LLM 규칙 + 프로바이더 어댑터 + 컨텍스트 압축)
   - spec/tools.md (내장 도구 스키마)
   - spec/security.md (권한 분류)
   - spec/voice-and-audio.md (음성 + 에이전트 라우팅)
   - spec/supabase.md (클라우드 테이블)
   - spec/rewrite-plan.md (Phase별 계획 + 품질 목표)
   - spec/tech-spec.md (아키텍처 + 의존성)
   - CONCEPT.md (제품 비전)
   - project.yml (현재 프로젝트 설정 참고)
2. 기존 코드 폴더(Dochi/, DochiTests/)의 구조를 파악하되, 코드 내용은 참고만 하고 새로 작성한다.

## Phase 0 — 스캐폴딩

### 목표
기존 소스를 정리하고 새 모듈 구조를 생성. 빈 스텁으로 빌드 성공까지.

### 작업
1. 기존 `Dochi/` 소스 파일을 `_legacy/` 폴더로 이동 (참고용 보존)
2. 새 폴더 구조 생성:
   ```
   Dochi/
   ├── App/                    # App entry point
   ├── Models/                 # 데이터 모델
   ├── State/                  # 상태 머신
   ├── ViewModels/             # ViewModel
   ├── Views/                  # SwiftUI Views
   ├── Services/
   │   ├── Protocols/          # 서비스 프로토콜
   │   ├── LLM/                # LLMService + 프로바이더 어댑터
   │   ├── Context/            # ContextService
   │   ├── Conversation/       # ConversationService
   │   ├── Keychain/           # KeychainService
   │   ├── Tools/              # BuiltInToolService + 개별 도구
   │   ├── Speech/             # SpeechService (P2)
   │   ├── TTS/                # SupertonicService (P2)
   │   ├── MCP/                # MCPService (P3)
   │   ├── Telegram/           # TelegramService (P4)
   │   └── Cloud/              # SupabaseService (P4)
   └── Utilities/              # Log, JamoMatcher 등

   DochiTests/
   ├── Mocks/
   └── ...
   ```
3. `project.yml` 갱신 (새 경로 반영)
4. 빈 스텁 파일 생성 → `xcodegen generate && xcodebuild` 빌드 확인
5. `CLAUDE.md`를 새 구조에 맞게 갱신
6. git commit: `rewrite: phase 0 — scaffolding`

### 서브에이전트 활용
- Agent A: 폴더 생성 + project.yml 갱신
- Agent B: 빈 스텁 파일 생성 (Models, Protocols)
- Agent C: 빈 스텁 파일 생성 (Views, App entry)

---

## Phase 1 — 텍스트 플로우 MVP

### 목표
텍스트 입력 → LLM 스트리밍 → 도구 호출(Safe) → 대화 저장. spec/flows.md §1, §4, §5, §7 수용 기준 충족.

### 서브에이전트 구성 (병렬 그룹)

**그룹 A — 모델 + 유틸리티** (독립적, 먼저 시작)
- spec/models.md의 P1 모델 전체 구현:
  - Enums (LLMProvider, InteractionMode)
  - Settings (AppSettings — UserDefaults + Keychain 연동)
  - AgentConfig, UserProfile
  - Conversation, Message
  - ToolCall, ToolResult, LLMResponse
- Log enum (os.Logger, 기존 _legacy 참고)
- 빌드 확인

**그룹 B — 서비스 프로토콜 + 구현** (모델 완료 후)
- ContextServiceProtocol + ContextService (spec/interfaces.md P1 범위)
  - 파일 읽기/쓰기, 에이전트/프로필/메모리 관리
  - migrateIfNeeded() (레거시 파일 마이그레이션)
- ConversationServiceProtocol + ConversationService
- KeychainServiceProtocol + KeychainService
- Mock 구현 전부 (DochiTests/Mocks/)

**그룹 C — LLMService** (모델 완료 후)
- spec/llm-requirements.md 기반 구현:
  - LLMProviderAdapter 프로토콜 정의
  - OpenAIAdapter, AnthropicAdapter, ZAIAdapter
  - SSE 스트리밍 파싱
  - tool_calls 파싱 (OpenAI/Anthropic 양쪽)
  - 에러 정규화, 재시도 (2회, 250/750ms), 타임아웃 (20s/60s)
  - 취소 지원

**그룹 D — 상태 머신 + ViewModel** (모델 + 서비스 완료 후)
- spec/states.md 기반:
  - InteractionState enum (idle/listening/processing/speaking)
  - SessionState enum (inactive/active/ending)
  - ProcessingSubState enum (streaming/toolCalling/toolError/complete)
  - 금지 조합 검증
- DochiViewModel:
  - 상태 전이 로직
  - 컨텍스트 조합 (spec/flows.md §7 — 7단계 순서 정확히)
  - LLM 호출 + 응답 처리
  - Tool loop (최대 10회)
  - 대화 저장
  - 취소 처리

**그룹 E — BuiltInToolService (Safe)** (모델 완료 후)
- spec/tools.md baseline 도구:
  - BuiltInToolProtocol
  - ToolsRegistryTool (tools.list/enable/enable_ttl/reset)
  - RemindersTool (AppleScript 기반)
  - AlarmTool
  - MemoryTool (save_memory, update_memory)
  - ProfileTool (set_current_user)
  - WebSearchTool (Tavily, API 키 조건부)
  - ImageGenerationTool (fal.ai, 조건부)
  - BuiltInToolService (라우터 + 레지스트리)

**그룹 F — Views** (ViewModel 완료 후)
- ContentView (메인 레이아웃, 상태 표시)
- ConversationView (메시지 목록, 스트리밍 렌더링)
- SettingsView (API 키, 모델 선택, 기본 설정)
- 텍스트 입력 + 전송 + 취소 UI

### 완료 조건
- `xcodegen generate && xcodebuild` 빌드 성공
- 기본 단위 테스트 통과 (Context, Conversation, Settings, Tool 모델)
- git commit: `rewrite: phase 1 — text flow MVP`

---

## Phase 2 — 음성 플로우

### 목표
웨이크워드 → STT → LLM → TTS → 연속 대화. spec/flows.md §2 수용 기준 충족.

### 서브에이전트 구성

**그룹 A — SpeechService**
- Apple Speech STT
- JamoMatcher (웨이크워드 자모 매칭, _legacy 참고)
- 웨이크워드 → 에이전트 라우팅 (spec/voice-and-audio.md)
- 콜백: onQueryCaptured, onWakeWordDetected, onSilenceTimeout

**그룹 B — SupertonicService**
- ONNX Runtime TTS (_legacy의 SupertonicHelpers 참고)
- 큐 기반 재생 (enqueueSentence → processQueue)
- 문장 단위 스트리밍 파이프라인
- 모델 다운로드/로드/언로드

**그룹 C — 음성 통합**
- DochiViewModel에 음성 상태 통합:
  - SessionState 전이 (inactive → active → ending)
  - Barge-in 처리 (spec/states.md)
  - 연속 대화 루프
  - 침묵 타임아웃 → "종료할까요?"
- SoundService (확인음)
- 상태바 UI 업데이트 (listening/processing/speaking)

### 완료 조건
- 빌드 성공
- 웨이크워드 → 음성 대화 → 연속 대화 → 종료 흐름 동작
- git commit: `rewrite: phase 2 — voice flow`

---

## Phase 3 — 도구 & 권한

### 목표
전체 내장 도구 + MCP + 권한 시스템. spec/tools.md + spec/security.md 충족.

### 서브에이전트 구성

**그룹 A — Sensitive 도구**
- SettingsTool, AgentTool, AgentEditorTool
- ContextEditTool, ProfileAdminTool
- WorkspaceTool (로컬 동작만, Supabase는 P4)
- TelegramTool (스텁, P4에서 완성)

**그룹 B — MCPService**
- spec/interfaces.md MCPServiceProtocol 구현
- MCP 서버 연결/해제, 도구 조회/실행
- BuiltInToolService와 통합 (MCP + 내장 도구 합산)

**그룹 C — 권한 시스템**
- AgentConfig.permissions 기반 도구 필터링
- 권한 체크 2단계 (에이전트 → 인터페이스)
- 사용자 확인 UI (인라인 배너, 30s 타임아웃)
- 가드레일 (persona 대량 수정 시 confirm/preview)

**그룹 D — 테스트**
- 도구별 단위 테스트
- 권한 체크 테스트
- 설정/프로필/에이전트 CRUD 테스트

### 완료 조건
- 빌드 + 테스트 통과
- git commit: `rewrite: phase 3 — tools & permissions`

---

## Phase 4 — 원격 & 동기화

### 목표
텔레그램 DM + Supabase 동기화. spec/flows.md §3, §6 충족.

### 서브에이전트 구성

**그룹 A — TelegramService**
- Long polling (getUpdates)
- 워크스페이스/에이전트 resolve
- 스트리밍 응답 (메시지 편집)
- Progress snippet
- 보수적 권한 (Safe만)

**그룹 B — SupabaseService**
- 인증 (Apple Sign-In, Email)
- 워크스페이스 CRUD
- spec/supabase.md 테이블 기반

**그룹 C — 동기화**
- 컨텍스트/대화 push/pull
- 충돌 해결 (라인 단위 병합, 로컬 우선)
- Leader lock
- DeviceService (heartbeat)
- 오프라인 큐

### 완료 조건
- 빌드 + 테스트 통과
- git commit: `rewrite: phase 4 — remote & sync`

---

## Phase 5 — 마무리

### 작업
1. 관측 지표 로깅 (레이턴시, 도구 성공률, 웨이크워드 정확도)
2. CLAUDE.md를 최종 코드 구조에 맞게 완전 갱신
3. _legacy/ 폴더 제거
4. 전체 빌드 + 테스트
5. git commit: `rewrite: phase 5 — polish & cleanup`

---

## 실행 전략

1. Phase별로 순차 진행. 각 Phase 내에서는 서브에이전트 병렬 활용.
2. 각 Phase 시작 전에 관련 스펙 문서를 다시 읽어 정확성 확보.
3. 각 Phase 완료 시 반드시:
   - xcodegen generate
   - xcodebuild 빌드 확인
   - git commit
4. 에러 발생 시: 스펙 문서 재확인 → 수정 → 재빌드. 추측으로 우회하지 말 것.
5. _legacy/ 코드는 참고만. 복사하지 말고 스펙 기준으로 새로 작성.

Phase 0부터 시작하라.
```
