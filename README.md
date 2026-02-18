# Dochi (도치)

집 Mac에 상주하며 가족과 팀의 맥락을 이해하는 macOS 네이티브 AI 에이전트.

워크스페이스 단위로 기억을 관리하고, 에이전트마다 고유한 페르소나와 권한을 갖습니다. SwiftUI 네이티브 앱으로 FaceTime, 캘린더, 미리알림, Apple Shortcuts와 깊이 통합됩니다.

> 실행 정본: [spec/execution-context.md](./spec/execution-context.md) · 스펙 인덱스: [spec/README.md](./spec/README.md) · 비전: [CONCEPT.md](./CONCEPT.md) · 장기 로드맵: [ROADMAP.md](./ROADMAP.md)

## 핵심 기능

- **멀티 LLM** — OpenAI, Anthropic, Z.AI SSE 스트리밍
- **텍스트 + 음성** — 텍스트 입력 기본, 웨이크워드("도치야")로 음성 전환
- **멀티 TTS** — 시스템 TTS / Google Cloud TTS / ONNX 기반 로컬 TTS 경로
- **장기 기억** — 워크스페이스/에이전트/개인 컨텍스트 계층, 자동 압축
- **도구 실행** — 일정/칸반/파일/개발/GitHub/자동화 등 다수 내장 도구 + ([도구 스키마](spec/tools.md))
- **MCP 연동** — Model Context Protocol 서버로 도구 확장
- **클라우드 동기화** — Supabase 기반 컨텍스트·대화 동기화
- **텔레그램 연동** — 앱 실행 중 DM 수신/응답 및 호스트 디바이스 연계

```
"도치야, 민수 숙제 도와줘"      → 가족 워크스페이스 · 가족 기억으로 대화
"코디야, PR 리뷰해줘"           → 팀 워크스페이스 · Claude Code 세션
"도치야, 엄마한테 전화해줘"      → FaceTime 통화 시작
"도치야, 내 알러지 뭐였지?"      → 개인 컨텍스트 · 어디서든 동일
```

## 빠른 시작

```bash
brew install xcodegen       # 요구사항: macOS 14+, Xcode 15+
xcodegen generate
xcodebuild -project Dochi.xcodeproj -scheme Dochi build
open ~/Library/Developer/Xcode/DerivedData/Dochi-*/Build/Products/Debug/Dochi.app
```

1. 설정에서 API 키 입력 (OpenAI / Anthropic / Z.AI 중 하나 이상)
2. 텍스트로 바로 대화 시작
3. 음성: 웨이크워드 활성화 → "도치야" → 연속 대화

## CLI 빠른 시작

```bash
xcodegen generate
xcodebuild -project Dochi.xcodeproj -scheme DochiCLI -configuration Debug build

CLI_BIN="$(find ~/Library/Developer/Xcode/DerivedData -path '*Build/Products/Debug/dochi' -type f | head -n 1)"
"$CLI_BIN" doctor
```

- 기본 모드(`--mode auto`)는 실행 중인 Dochi 앱의 로컬 API(Control Plane)에 연결합니다.
- 기본 사용은 Host 연결 모드(`auto`/`app`)를 권장합니다.
- standalone은 디버그 전용이며 `--mode standalone --allow-standalone`으로만 활성화됩니다.
- 상세 명령/운영 가이드: [`DochiCLI/README.md`](./DochiCLI/README.md)

## 비-UI 기능 검증 가이드 (Host Mode CLI)

UI가 아닌 기능(로컬 API, 세션/대화, 로그, 도구 실행)은 Dochi 앱 + CLI를 같은 빌드 산출물로 맞춘 뒤 Host 모드(`--mode app`)로 검증하는 것을 기본 경로로 사용합니다.

```bash
APP_BIN="$(find ~/Library/Developer/Xcode/DerivedData -path '*Build/Products/Debug/Dochi.app' -type d | head -n 1)"
CLI_BIN="$(find ~/Library/Developer/Xcode/DerivedData -path '*Build/Products/Debug/dochi' -type f | head -n 1)"

open "$APP_BIN"
"$CLI_BIN" --mode app doctor
"$CLI_BIN" --mode app session list --json
"$CLI_BIN" --mode app dev log recent --minutes 5 --json
"$CLI_BIN" --mode app ask "host mode 연결 검증. OK만 답해줘" --json
```

- `doctor`에서 `app_running`, `control_plane_socket`, `control_plane_ping`이 모두 `OK`여야 합니다.
- `/Applications/Dochi.app`와 DerivedData 빌드 앱이 섞이면 연결 실패가 발생할 수 있으므로 한 쌍으로 고정해 사용합니다.
- `standalone`은 제품 동작 검증 경로가 아니라, LLM 직접 호출 디버깅용 보조 경로입니다.

## 컨텍스트 구조

```
~/Library/Application Support/Dochi/
├── system_prompt.md             # 앱 레벨 기본 규칙 (선택)
├── profiles.json                # 사용자 프로필
├── memory/{userId}.md           # 개인 기억
└── workspaces/{workspaceId}/
    ├── config.json
    ├── memory.md                # 워크스페이스 공유 기억
    └── agents/{name}/
        ├── persona.md           # 에이전트 페르소나
        ├── memory.md            # 에이전트 기억
        └── config.json          # 에이전트 설정
```

## 문서

| 문서 | 내용 |
|------|------|
| [spec/execution-context.md](./spec/execution-context.md) | 이슈 작업 정본 (완료 축약 + 구현 예정 상세 + UX 계약) |
| [DochiCLI/README.md](./DochiCLI/README.md) | CLI 사용법 (모드, 명령, 디버깅, 트러블슈팅) |
| [CONCEPT.md](./CONCEPT.md) | 제품 비전, 시나리오, 설계 원칙 |
| [spec/](./spec/README.md) | 설계 스펙 전체 (모델, 플로우, 상태, 권한 등) |
| [ROADMAP.md](./ROADMAP.md) | 장기 비전 (Phase 6+) |

## 라이선스

MIT License. [LICENSE](./LICENSE) 참조.
