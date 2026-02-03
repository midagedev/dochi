# MCP 연동 작업 계획

## 개요

Dochi에 Model Context Protocol (MCP)을 연동하여 도구 사용(tool use) 기능을 추가한다.

**목표**: 웹검색, 파일 접근 등의 도구를 MCP 서버를 통해 표준화된 방식으로 사용

**참고**: https://github.com/modelcontextprotocol/swift-sdk

---

## Phase 1: Swift 6 업그레이드 ✅ 완료

### 완료된 작업
- [x] `project.yml`에서 `SWIFT_VERSION`을 `"6.0"`으로 변경
- [x] `@preconcurrency import`로 ONNX Runtime Sendable 경고 해결
- [x] `SupertonicTTS`, `SupertonicStyle`에 `@unchecked Sendable` 추가
- [x] 빌드 및 테스트 통과 확인

### 수정된 파일
- `project.yml`
- `Dochi/Services/SupertonicService.swift`
- `Dochi/Services/Supertonic/SupertonicHelpers.swift`

---

## Phase 2: MCP SDK 추가 ✅ 완료

### 완료된 작업
- [x] `project.yml`에 MCP Swift SDK 의존성 추가 (v0.10.2)
- [x] 빌드 확인

### 수정된 파일
- `project.yml`

---

## Phase 3: MCPService 구현 ✅ 완료

### 완료된 작업
- [x] `MCPToolInfo`, `MCPToolResult`, `MCPServerConfig` 모델 정의
- [x] `MCPService` 클래스 구현
  - HTTP 기반 MCP 서버 연결
  - 도구 목록 조회 (`listTools`)
  - 도구 실행 (`callTool`)
  - MCP `Value` ↔ Swift `Any` 변환

### 새 파일
- `Dochi/Services/Protocols/MCPServiceProtocol.swift`
- `Dochi/Services/MCPService.swift`

### 제한사항
- 현재 HTTP 기반 MCP 서버만 지원
- Stdio 기반 (로컬 프로세스) 서버는 향후 추가 예정

---

## Phase 4: LLMService Tool Calling 지원 ✅ 완료

### 완료된 작업
- [x] `ToolCall`, `ToolResult` 모델 정의
- [x] `Message`에 `toolCalls` 필드 추가 (Codable 지원)
- [x] `sendMessage`에 `tools`, `toolResults` 파라미터 추가
- [x] OpenAI/Z.AI tool calling 요청/응답 파싱
- [x] Anthropic tool_use 요청/응답 파싱
- [x] `onToolCallsReceived` 콜백 추가

### 새 파일
- `Dochi/Models/ToolCall.swift`

### 수정된 파일
- `Dochi/Models/Message.swift`
- `Dochi/Services/LLMService.swift`

---

## Phase 5: Tool Loop 구현 ✅ 완료

### 완료된 작업
- [x] `DochiViewModel`에 MCPService 주입 (DI 패턴)
- [x] tool loop 로직 구현:
  - `handleQuery()`에서 MCP 도구 목록을 LLM에 전달
  - `onToolCallsReceived` 콜백으로 tool_calls 수신
  - `executeToolLoop()`에서 각 tool 실행 → 결과 수집 → LLM 재호출
  - 최대 10회 반복 제한
- [x] UI에 도구 실행 상태 표시
  - `State.executingTool(String)` 추가
  - 상태바에 실행 중인 도구 이름 표시

### 수정된 파일
- `Dochi/ViewModels/DochiViewModel.swift`
- `Dochi/Views/ContentView.swift`
- `Dochi/Services/Protocols/MCPServiceProtocol.swift` (프로토콜 @MainActor 지원)
- `Dochi/Services/MCPService.swift` (프로토콜 conformance)

### 흐름도
```
사용자 입력
    ↓
LLM 호출 (messages + tools)
    ↓
응답 확인 ──→ 텍스트만? ──→ 완료, UI 표시
    ↓
tool_calls 있음?
    ↓
각 tool_call에 대해:
    → MCPService.callTool()
    → 결과 수집
    ↓
tool 결과를 messages에 추가
    ↓
LLM 재호출 (반복)
```

---

## Phase 6: 테스트 추가 ✅ 완료

### 완료된 작업
- [x] `ToolCall` 모델 테스트 (10개 테스트)
  - 생성, JSON 파싱, 빈 arguments, 유효하지 않은 JSON 처리
- [x] `Message` + toolCalls Codable 테스트 (10개 테스트)
  - 인코딩/디코딩, round-trip, 중첩된 arguments
- [x] `MCPToolInfo`, `MCPServerConfig` 테스트 (11개 테스트)
  - asDictionary 변환, Codable
- [x] `MockMCPService` 구현 (테스트용)

### 새 파일
- `DochiTests/Models/ToolCallTests.swift`
- `DochiTests/Models/MessageTests.swift`
- `DochiTests/Models/MCPToolInfoTests.swift`
- `DochiTests/Mocks/MockMCPService.swift`

### 테스트 현황
- 총 48개 테스트, 전체 통과

---

## Phase 7: MCP 서버 연동 테스트 📝 예정

### 작업 내용
- [ ] 테스트용 MCP 서버 선택
- [ ] 연결 테스트
- [ ] 도구 실행 E2E 테스트

### 후보 MCP 서버
| 서버 | 기능 | 연결 방식 |
|------|------|----------|
| 자체 HTTP 서버 | 테스트용 | HTTP |
| mcp-server-fetch | 웹 가져오기 | Stdio (미지원) |

---

## Phase 8: 설정 UI 📝 예정

### 작업 내용
- [ ] MCP 서버 목록 관리 UI
- [ ] 서버 추가/제거/활성화
- [ ] 연결 상태 표시

### 수정 예정 파일
- `Dochi/Views/SettingsView.swift`
- `Dochi/Models/Settings.swift`

---

## 현재 상태 요약

| Phase | 상태 | 설명 |
|-------|------|------|
| 1. Swift 6 | ✅ 완료 | |
| 2. SDK 추가 | ✅ 완료 | |
| 3. MCPService | ✅ 완료 | HTTP만 지원 |
| 4. LLMService | ✅ 완료 | tool calling 파싱 |
| 5. Tool Loop | ✅ 완료 | ViewModel 통합 |
| 6. 테스트 | ✅ 완료 | 48개 테스트 |
| 7. 서버 연동 | 📝 예정 | |
| 8. 설정 UI | 📝 예정 | |

---

## 참고 자료

- [MCP 공식 문서](https://modelcontextprotocol.io/)
- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)
- [MCP 서버 목록](https://github.com/modelcontextprotocol/servers)
- [OpenAI Tool Calling](https://platform.openai.com/docs/guides/function-calling)
- [Anthropic Tool Use](https://docs.anthropic.com/en/docs/build-with-claude/tool-use)
