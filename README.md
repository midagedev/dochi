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

- OpenAI Realtime API 실시간 음성 대화 (서버 VAD, Whisper 트랜스크립션)
- 텍스트 모드: OpenAI / Anthropic / Z.AI SSE 스트리밍
- Supertonic ONNX 로컬 TTS (한국어, 영어 등 다국어 지원, 10종 음성)
- Apple Speech 프레임워크 STT
- 웨이크워드 감지 ("도치야")
- 컨텍스트 파일 첨부
- 문장 단위 스트리밍 TTS (LLM 응답 중 즉시 음성 재생)
