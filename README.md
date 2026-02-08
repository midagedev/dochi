# Dochi (도치)

사용자, 디바이스, AI가 하나의 워크스페이스에서 연결되는 LLM 인터페이스.

macOS 앱에서 시작하여 CLI, 텔레그램, 슬랙으로 확장됩니다. 어디서든 같은 AI, 같은 기억, 같은 컨텍스트. `system.md` 하나로 가족 대화 상대, 개발 보조, 업무 어시스턴트를 오갑니다.

> 자세한 비전은 [CONCEPT.md](./CONCEPT.md), 개발 계획은 [ROADMAP.md](./ROADMAP.md) 참조.

## 특징

- **멀티 LLM** — OpenAI, Anthropic, Z.AI 중 선택. API 키만 입력하면 바로 사용
- **텍스트 + 음성** — 기본은 텍스트 입력, 웨이크워드로 음성 모드 전환
- **로컬 TTS** — Supertonic ONNX 엔진, 10종 한국어 음성, 문장 단위 스트리밍
- **장기 기억** — 대화에서 중요 정보를 자동 추출하여 다음 세션에 반영
- **다중 사용자** — 프로필별 기억 분리, 음성으로 사용자 자동 식별
- **도구 확장** — 내장 도구 + MCP 서버 연동으로 기능 확장

## 빠른 시작

```bash
# 요구사항: macOS 14+, Xcode 15+, XcodeGen
brew install xcodegen

# 빌드
xcodegen generate
xcodebuild -project Dochi.xcodeproj -scheme Dochi build

# 실행
open ~/Library/Developer/Xcode/DerivedData/Dochi-*/Build/Products/Debug/Dochi.app
```

1. 설정에서 API 키 입력 (OpenAI / Anthropic / Z.AI 중 하나 이상)
2. 텍스트로 바로 대화 시작
3. 음성 사용 시: 웨이크워드 활성화 → "도치야" 호출 → 연속 대화

## 커스터마이징

`~/Library/Application Support/Dochi/` 아래 마크다운 파일로 동작을 정의합니다.

| 파일 | 역할 | 편집 |
|------|------|------|
| `system.md` | 페르소나, 행동 규칙, 톤 | 사이드바 또는 직접 편집 |
| `memory.md` | 사용자 정보 장기 기억 | 자동 축적 (수동 편집 가능) |

예시: 아이 대화 상대로 쓰려면 `system.md`에 "초등학생 눈높이로 대화해줘"를 적으면 됩니다.

## 음성 모드

- **웨이크워드**: 한글 자모 유사도 매칭 — "도치야"를 "토치야", "도시야"로 발음해도 인식
- **연속 대화**: 웨이크워드로 세션 시작 후 웨이크워드 없이 대화 지속
- **세션 종료**: "대화 종료", "그만할게" 등 직접 종료 또는 10초 무응답 시 자동 확인

## 내장 도구

| 도구 | API 키 | 기능 |
|------|--------|------|
| 웹검색 | Tavily | 실시간 웹 검색 |
| 미리알림 | - | Apple 미리알림 생성/조회/완료 |
| 알람 | - | TTS로 알림 메시지를 읽어주는 타이머 |
| 이미지 생성 | fal.ai | FLUX 기반 AI 이미지 생성 |

MCP(Model Context Protocol) 서버를 추가로 연결하여 도구를 확장할 수 있습니다.

## 라이선스

MIT License. [LICENSE](./LICENSE) 참조.
