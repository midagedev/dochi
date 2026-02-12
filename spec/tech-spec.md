# Dochi — Technical Spec

## Meta
- DRI: @hckim
- 상태: Draft
- 생성: 2026-02-12
- 갱신: 2026-02-12

---

## 요약

macOS 네이티브 SwiftUI 앱. 피어 모델(디바이스 자율) + Supabase 동기화 계층. 도구 실행은 로컬, 클라우드는 동기화 전용.

---

## Architecture

```
┌─────────────────────────────────────────────┐
│                   Views (SwiftUI)            │
├─────────────────────────────────────────────┤
│              DochiViewModel                  │
│   (State Machine · Orchestrator)             │
├──────┬──────┬──────┬──────┬─────┬───────────┤
│ LLM  │ STT  │ TTS  │ Tool │ Ctx │ Telegram  │
│  Svc │  Svc │  Svc │  Svc │ Svc │   Svc     │
├──────┴──────┴──────┴──────┴─────┴───────────┤
│         Supabase Sync (P4)                   │
└─────────────────────────────────────────────┘
```

### 핵심 설계 결정

| 결정 | 근거 |
|------|------|
| 명시적 상태 머신 | 이전 코드 버그의 주요 원인이 상태 불일치. [states.md](./states.md)에 전이 규칙 정의 |
| 프로바이더 어댑터 패턴 | 3개 LLM 프로바이더 차이를 어댑터에서 흡수. [llm-requirements.md](./llm-requirements.md#provider-adapter) |
| 프로토콜 기반 DI | 모든 서비스에 프로토콜. Mock 주입으로 테스트 용이 |
| 파일 기반 컨텍스트 | ~/Library/Application Support/Dochi/ 하위. 사람이 읽고 편집 가능 |
| 세션 기반 도구 레지스트리 | 토큰 절약. baseline만 노출, LLM이 필요 시 활성화 |

---

## Components

상세 인터페이스: [interfaces.md](./interfaces.md)

| 서비스 | 역할 | Phase |
|--------|------|-------|
| DochiViewModel | 상태 머신 + 오케스트레이션 | P1 |
| LLMService | SSE 스트리밍, 프로바이더 어댑터 | P1 |
| ContextService | 파일 기반 컨텍스트 관리 | P1 |
| ConversationService | 대화 CRUD | P1 |
| KeychainService | API 키 관리 | P1 |
| BuiltInToolService | 도구 라우터 + 레지스트리 | P1 (Safe), P3 (전체) |
| SpeechService | Apple STT + 웨이크워드 | P2 |
| SupertonicService | ONNX TTS + 큐 기반 재생 | P2 |
| SoundService | UI 효과음 | P2 |
| MCPService | MCP 서버 연결 + 도구 프록시 | P3 |
| TelegramService | DM 수신/스트리밍 응답 | P4 |
| SupabaseService | 인증/동기화 | P4 |
| DeviceService | 디바이스 등록/heartbeat | P4 |

---

## Data Model

상세: [models.md](./models.md)

파일 구조:
```
~/Library/Application Support/Dochi/
├── system_prompt.md
├── profiles.json
├── memory/{userId}.md
└── workspaces/{wsId}/
    ├── config.json
    ├── memory.md
    └── agents/{name}/
        ├── persona.md
        ├── memory.md
        └── config.json
```

---

## 동기화

상세: [supabase.md](./supabase.md)

- 피어 모델: 각 디바이스 독립 실행. 꺼져도 다른 피어에 영향 없음
- Supabase: 인증, 워크스페이스, 컨텍스트, 대화, 디바이스 동기화
- 충돌 해결: 라인 단위 병합 → 로컬 우선. 상세: [supabase.md](./supabase.md#충돌-해결)

---

## Security

상세: [security.md](./security.md)

- 에이전트별 권한 (safe/sensitive/restricted)
- 도구 목록 필터링 + 실행 전 이중 확인
- 원격 인터페이스는 기본 Safe만

---

## Performance

목표값: [rewrite-plan.md](./rewrite-plan.md#quality-targets-정본)

- SSE 스트리밍 파이프라인
- TTS 문장 단위 파이프라이닝 (합성과 재생 동시)
- 컨텍스트 압축으로 토큰 절약: [llm-requirements.md](./llm-requirements.md#context-compression)

---

## Testing

- 프로토콜 기반 DI → Mock 주입 단위 테스트
- 통합: 웨이크워드 → STT → LLM → 도구 → TTS 체인 검증
- 회귀: 도구 스키마 스냅샷 테스트, 마이그레이션 테스트
- 상태 머신: 전이 규칙 준수 테스트, 금지 조합 검증

---

## Dependencies

| 패키지 | 버전 | 용도 |
|--------|------|------|
| microsoft/onnxruntime-swift-package-manager | v1.20.0 | TTS (OnnxRuntimeBindings) |
| modelcontextprotocol/swift-sdk | v0.10.2 | MCP 서버 연동 |
| supabase/supabase-swift | v2.0.0+ | 클라우드 동기화 |

---

## Conventions

- `@MainActor` on all ViewModels and Services
- `async/await` + `Task` for concurrency; `Task.detached` for CPU-heavy ONNX
- `os.Logger` via `Log` enum — never `print()`
- UI language: Korean
- XcodeGen (`project.yml`) generates `.xcodeproj`
- Bundle ID: `com.hckim.dochi`
