# Dochi - 할 일 목록

## 완료됨 (v1.0.0)

- [x] 멀티 LLM 제공자 (OpenAI, Anthropic, Z.AI)
- [x] Apple STT 음성 입력
- [x] Supertonic TTS 로컬 음성 출력
- [x] 웨이크워드 감지 ("도치야")
- [x] 연속 대화 모드
- [x] 대화 히스토리 저장/관리
- [x] 시스템 프롬프트 (system.md)
- [x] 사용자 기억 자동 저장 (memory.md)
- [x] 메모리 자동 압축
- [x] 프로토콜 기반 DI 구조
- [x] 단위 테스트 인프라
- [x] Changelog 시스템

---

## 단기 할 일

### 테스트 확장

- [ ] KeychainService 테스트
- [ ] SoundService 테스트
- [ ] ChangelogService 테스트
- [ ] AppSettings 테스트

### 버그/개선

- [ ] 에러 핸들링 강화 (네트워크/API 오류)
- [ ] 로딩 상태 UI 개선

### 코드 품질

- [ ] SwiftLint 도입
- [ ] 하드코딩된 문자열 정리

---

## 다음 기능들

### 프로필 시스템

- [ ] `Profile` 모델 (이름, 아바타, 설정)
- [ ] 프로필별 `system.md`, `memory.md` 분리
- [ ] 프로필 선택 UI
- [ ] 아이용 프로필 프리셋

### UX

- [ ] 대화 중 인터럽트 (말하는 중 끊기)
- [ ] 테마 지원 (다크/라이트)
- [ ] VoiceOver 점검
- [ ] 키보드 단축키

---

## 나중에

- [ ] 간단한 빌트인 에이전트 (타이머, 리마인더)
- [ ] iOS 컴패니언 앱
- [ ] 단축어(Shortcuts) 연동
- [ ] 대화 내보내기

---

## 기술 부채

- [ ] `DochiViewModel`이 너무 큼 → 분리 필요
- [ ] 매직 넘버 정리 (타임아웃 값 등)
