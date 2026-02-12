# Dochi — TODO

현재까지 구현된 것과 앞으로 해야 할 것을 정리한 문서.
갱신: 2026-02-13

---

## 현재 상태 요약

### 구현 완료

| 영역 | 구현 내용 | 상태 |
|------|----------|------|
| **텍스트 채팅** | LLM SSE 스트리밍, 3 프로바이더(OpenAI/Anthropic/Z.AI), 대화 저장/불러오기 | 동작 |
| **음성** | Apple STT, 웨이크워드 감지(JamoMatcher), 연속 대화, barge-in | 동작 |
| **TTS** | SupertonicService 프레임워크, ONNX 파이프라인 코드, KoreanG2P, placeholder 모드 | 코드 완료, 모델 없음 |
| **도구** | 13개 내장 도구 (설정/에이전트/프로필/워크스페이스/미리알림/알람/검색/이미지/메모리/컨텍스트/MCP/텔레그램/레지스트리) | 동작 |
| **MCP** | MCPService (stdio transport), BuiltInToolService에서 MCP 도구 LLM 노출 | 동작 |
| **권한** | safe/sensitive/restricted 분류, ToolConfirmation UI | 동작 |
| **컨텍스트** | 워크스페이스/에이전트/개인 3계층, 자동 압축, 컨텍스트 인스펙터 | 동작 |
| **Supabase** | 인증(Email), 워크스페이스 CRUD, 리더락, DB 스키마(7 테이블) | 기본 동작 |
| **텔레그램** | 봇 폴링, DM 수신, LLM 응답 전송 | 기본 동작 |
| **UI** | 6탭 설정, 사이드바(워크스페이스/에이전트 피커), 상태바, 대화 뷰, 빈 상태 안내 | 동작 |
| **모델 라우팅** | ModelRouter, ExchangeMetrics, MetricsCollector | 기본 동작 |
| **빌드** | 110 테스트 통과, BUILD SUCCEEDED | 통과 |

---

## 앞으로 해야 할 것

### 우선순위 높음 (핵심 기능 완성)

#### 1. 클라우드 동기화 실제 구현
> 현재: syncContext/syncConversations가 타임스탬프 마커만 upsert
- [ ] 워크스페이스 메모리 양방향 동기화 (push/pull)
- [ ] 에이전트 메모리/페르소나 양방향 동기화
- [ ] 대화 로그 양방향 동기화 (Conversation 모델 ↔ conversations 테이블)
- [ ] 프로필 동기화
- [ ] 충돌 해결 구현 (last-write-wins 기본, 메모리는 라인 병합)
- [ ] 오프라인 큐 (변경사항 로컬 적재 → 복구 시 push)
- [ ] 앱 시작 시 자동 동기화
- 참조: [spec/supabase.md](./spec/supabase.md#동기화-정책)

#### 2. TTS ONNX 모델 준비 & 통합
> 현재: 코드는 완성되었으나 ONNX 모델 파일이 없어 placeholder 모드로 동작
- [ ] Supertonic 한국어 TTS ONNX 모델 확보 (duration, acoustic, vocoder)
- [ ] 모델 다운로드 메커니즘 (설정에서 URL 입력 또는 번들)
- [ ] 음소 → 토큰 ID 매핑 vocab 테이블 구현
- [ ] ONNX 추론 파이프라인 실제 연결 (runInferencePipeline 내부 TODO)
- [ ] Float32 waveform → PCM 재생 검증
- [ ] 음성 속도 조절 동작 확인

#### 3. 텔레그램 스트리밍 응답
> 현재: 최종 응답만 전송
- [ ] 첫 청크에서 sendMessage → 이후 editMessage로 스트리밍 업데이트
- [ ] 디바운싱 (500ms 간격)
- [ ] settings.telegramStreamReplies 토글 연동

#### 4. 디바이스 관리
> 현재: Device 모델과 DB 테이블만 존재
- [ ] 디바이스 등록 (앱 시작 시 upsert)
- [ ] Heartbeat 주기적 전송 (30초)
- [ ] 디바이스 목록 UI
- [ ] 오프라인 판정 (2분 미갱신)

---

### 우선순위 중간 (품질 & 사용성)

#### 5. Conversation 모델 CodingKeys
> 현재: Conversation에 CodingKeys가 없어 Supabase JSON 컬럼(snake_case)과 불일치
- [ ] Conversation에 CodingKeys 추가 (created_at, updated_at, user_id)
- [ ] Message에도 필요 시 CodingKeys 확인

#### 6. Apple Sign-In 완성
> 현재: OAuth 플로우 코드만 존재, ASAuthorizationController 연동 미완
- [ ] ASAuthorizationController 구현 (macOS)
- [ ] ID Token → Supabase signInWithIdToken
- [ ] 설정 UI에 "Apple로 로그인" 버튼 추가

#### 7. 텔레그램 대화 저장
> 현재: 텔레그램 DM은 LLM 응답만 생성, 로컬 대화에 미저장
- [ ] 텔레그램 전용 대화 생성/관리 여부 결정
- [ ] 대화 컨텍스트 유지 (멀티턴)

#### 8. MCP 서버 연결 상태 관리
> 현재: 서버 추가/설정 UI 있으나, 연결 상태 도트가 실제 연결 상태와 미연동
- [ ] MCPService.isServerConnected(name:) 구현
- [ ] 설정 UI에서 실시간 연결 상태 표시
- [ ] 연결 실패 시 재연결 로직

#### 9. UI 개선
- [ ] 대화 검색 기능
- [ ] 대화 이름 변경 (현재 자동 제목만)
- [ ] 마크다운 렌더링 개선 (코드 블록, 테이블)
- [ ] 다크 모드 최적화
- [ ] 키보드 단축키 (Cmd+N 새 대화, Cmd+, 설정 등)

#### 10. 에러 처리 개선
- [ ] LLM API 에러 시 사용자 친화적 메시지 (rate limit, 잘못된 키 등)
- [ ] 네트워크 연결 끊김 감지 및 UI 표시
- [ ] 도구 실행 실패 시 재시도 옵션

---

### 우선순위 낮음 (향후)

#### 11. 성능 최적화
- [ ] 대화 목록 lazy loading (대화 수가 많을 때)
- [ ] 컨텍스트 압축 성능 측정 및 튜닝
- [ ] LLM 레이턴시 목표 달성 확인 (p50 ≤ 1.0s, p95 ≤ 2.5s)

#### 12. 테스트 보강
- [ ] 도구 실행 단위 테스트
- [ ] 컨텍스트 압축 테스트
- [ ] 워크스페이스/에이전트 전환 통합 테스트
- [ ] 텔레그램 메시지 처리 테스트
- [ ] MCP 도구 라우팅 테스트

#### 13. 보안 강화
- [ ] API 키 유효성 검증 (설정 저장 시)
- [ ] 텔레그램 발신자 화이트리스트
- [ ] MCP 서버 샌드박싱 검토

#### 14. 접근성
- [ ] VoiceOver 지원
- [ ] 폰트 크기 조절 범위 확대
- [ ] 고대비 모드

---

## 장기 비전 (Phase 6+)

[ROADMAP.md](./ROADMAP.md) 참조.

- Phase 6: 멀티 인터페이스 (슬랙, CLI, 피어 라우팅)
- Phase 7: 자동화 (태스크 큐, 백그라운드 에이전트, 워크플로우)
- Phase 8: 경험 (3D 아바타, iOS 컴패니언)

---

## 파일 구조 참조

```
Dochi/
├── App/                          # DochiApp.swift
├── Models/                       # 18개 데이터 모델
├── State/                        # InteractionState, SessionState, ProcessingSubState
├── ViewModels/                   # DochiViewModel
├── Views/
│   ├── ContentView.swift         # 메인 레이아웃 (사이드바 + 디테일)
│   ├── ConversationView.swift    # 대화 메시지 목록
│   ├── MessageBubbleView.swift   # 메시지 버블
│   ├── ContextInspectorView.swift# 컨텍스트 인스펙터 시트
│   ├── SettingsView.swift        # 6탭 설정 (540×420)
│   ├── Settings/                 # VoiceSettings, Integrations, Account, Login, MCPServerEdit
│   └── Sidebar/                  # SidebarHeader, WorkspaceManagement, AgentCreation
├── Services/
│   ├── Protocols/                # 10개 서비스 프로토콜
│   ├── LLM/                      # LLMService + 3 어댑터 + ModelRouter
│   ├── Context/                  # ContextService (파일 기반)
│   ├── Conversation/             # ConversationService
│   ├── Keychain/                 # KeychainService
│   ├── Tools/                    # BuiltInToolService + 13개 도구
│   ├── Speech/                   # SpeechService (Apple STT)
│   ├── TTS/                      # SupertonicService + KoreanG2P + ONNXModelManager
│   ├── MCP/                      # MCPService (stdio)
│   ├── Telegram/                 # TelegramService (HTTP 폴링)
│   ├── Cloud/                    # SupabaseService
│   └── Sound/                    # SoundService
└── Utilities/                    # Log, JamoMatcher, SentenceChunker

supabase/
└── migrations/
    └── 20260212173816_initial_schema.sql  # 7 테이블, RLS, Realtime
```
