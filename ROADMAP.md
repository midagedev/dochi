# Dochi - 로드맵

## 완료됨

- [x] 멀티 LLM (OpenAI, Anthropic, Z.AI) SSE 스트리밍
- [x] Apple STT 음성 입력
- [x] Supertonic ONNX 로컬 TTS (10종 음성)
- [x] 텍스트 + 음성 입력 통합 UI
- [x] 웨이크워드 자모 유사도 매칭
- [x] 연속 대화 모드
- [x] 대화 히스토리 저장/관리
- [x] system.md / memory.md 컨텍스트 관리
- [x] 메모리 자동 압축
- [x] 다중 사용자 프로필 (별칭, 기억 분리)
- [x] 내장 도구: 웹검색, 미리알림, 알람, 이미지 생성
- [x] MCP 서버 연동
- [x] 프로토콜 기반 DI + 단위 테스트

---

## 단기

- [ ] 테스트 확장 (KeychainService, AppSettings 등)
- [ ] 에러 핸들링 강화 (네트워크/API 오류 시 사용자 피드백)
- [ ] SwiftLint 도입
- [ ] 하드코딩된 문자열 정리

## 중기

- [ ] 대화 내보내기 (마크다운/JSON)
- [ ] 테마 지원 (다크/라이트)
- [ ] 키보드 단축키 확충
- [ ] VoiceOver 접근성 점검

## 장기

- [ ] iOS 컴패니언 앱
- [ ] 단축어(Shortcuts) 연동
- [ ] 에이전트 워크플로우 (다단계 작업 자동화)

---

## 기술 부채

- [ ] `DochiViewModel` 분리 (현재 1000줄 이상)
- [ ] 매직 넘버 정리 (타임아웃 값 등)
