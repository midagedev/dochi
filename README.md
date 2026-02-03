# Dochi (도치)

macOS 음성 비서 앱. 두 가지 모드를 지원합니다.

- **리얼타임 모드**: OpenAI Realtime API (WebSocket) 기반 실시간 음성 대화
- **텍스트 모드**: 멀티 LLM (OpenAI, Anthropic, Z.AI) + Supertonic 로컬 TTS

## 요구사항

- macOS 14.0+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## 빌드

```bash
xcodegen generate
xcodebuild -project Dochi.xcodeproj -scheme Dochi build
```

## 기능

### 음성 대화
- OpenAI Realtime API 실시간 음성 대화 (서버 VAD, Whisper 트랜스크립션)
- 텍스트 모드: OpenAI / Anthropic / Z.AI SSE 스트리밍
- Supertonic ONNX 로컬 TTS (한국어, 영어 등 다국어 지원, F1~F5/M1~M5 10종 음성)
- Apple Speech 프레임워크 STT
- 문장 단위 스트리밍 TTS (LLM 응답 중 즉시 음성 재생)

### 웨이크워드 & 연속 대화
- 웨이크워드 감지 (기본: "도치야")
- LLM 기반 발음 유사 변형 자동 생성으로 인식률 향상
- 실시간 웨이크워드 모니터 (등록된 변형 목록 + 인식 텍스트 표시)
- **연속 대화 모드**: 웨이크워드로 세션 시작 후 웨이크워드 없이 대화 지속
- 10초 무응답 시 "대화를 종료할까요?" 질문
- 직접 종료 요청 지원 ("대화 종료", "그만할게", "잘가" 등)

### 프롬프트 파일 관리
```
~/Library/Application Support/Dochi/
├── system.md    # 페르소나 + 행동 지침 (수동 편집)
└── memory.md    # 사용자 기억 (자동 누적)
```
- **system.md**: AI의 정체성과 행동 지침 정의
- **memory.md**: 세션 종료 시 LLM이 대화 분석하여 중요 정보 자동 추출
- 다음 세션 시작 시 두 파일 모두 시스템 프롬프트에 포함
- 사이드바에서 확인/편집 가능
- 자동 압축: memory.md 크기 초과 시 LLM으로 요약 (기본 15KB)

### TTS 설정
- 속도 조절 (0.8x ~ 1.5x)
- 표현력/품질 조절 (디퓨전 스텝 4~20)

## 사용법

1. 설정에서 API 키 입력 (OpenAI / Anthropic / Z.AI 중 하나 이상)
2. 텍스트 모드 선택 → "연결" 클릭 (TTS 모델 로드)
3. 웨이크워드 활성화 시: "도치야" 호출 → 대화 시작
4. 대화 종료: "대화 종료", "그만할게" 등 또는 10초 무응답 후 확인

## 파일 구조

```
Dochi/
├── Models/
│   ├── Enums.swift          # AppMode, LLMProvider, SupertonicVoice
│   ├── Message.swift        # 대화 메시지 모델
│   └── Settings.swift       # 앱 설정 (UserDefaults 기반)
├── Services/
│   ├── ContextService.swift # system.md, memory.md 파일 관리
│   ├── KeychainService.swift # API 키 저장
│   ├── LLMService.swift     # LLM SSE 스트리밍
│   ├── RealtimeService.swift # OpenAI Realtime WebSocket
│   ├── SoundService.swift   # UI 효과음
│   ├── SpeechService.swift  # Apple STT + 웨이크워드
│   ├── SupertonicService.swift # ONNX TTS
│   └── Supertonic/
│       └── SupertonicHelpers.swift # ONNX 추론 헬퍼
├── ViewModels/
│   └── DochiViewModel.swift # 메인 뷰모델
└── Views/
    ├── ContentView.swift    # 메인 레이아웃 + 사이드바
    ├── ConversationView.swift # 대화 표시 + 웨이크워드 모니터
    └── SettingsView.swift   # 설정 시트
```
