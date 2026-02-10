# Feature: 내장 도구로 컨텍스트/설정 편집 기능 추가 (LLM 모델 변경, 에이전트/프로필/워크스페이스 관리)

## 배경
- 현재 Dochi는 내장 도구(웹검색, 미리알림, 이미지 생성, 기억 관리, 사용자 식별)와 MCP 도구를 통해 외부 작업을 수행합니다.
- 컨텍스트 파일(`system_prompt.md`, `agents/*/persona.md`, `memory/*.md`, `profiles.json`)과 앱 설정(AppSettings: LLM 제공자/모델, 활성 에이전트 등)은 사용자 UI에서 변경하지만, LLM 스스로 도구 호출로 갱신할 수 없습니다.
- 대화 흐름 안에서 “모델 바꿔줘”, “새 에이전트 만들어줘”, “OOO와 △△△ 프로필 합쳐줘”, “이 초대 코드로 워크스페이스 참여해” 같은 요청을 도구 호출로 처리할 수 있으면 자율성이 커집니다.

## 목표
- 내장 도구로 컨텍스트·설정 파일을 안전하게 편집/관리할 수 있게 합니다.
- 대표 시나리오: LLM 모델 변경, 에이전트 생성/전환, 프로필 추가/병합/개명/별칭 추가, 워크스페이스 생성/참여/전환/초대 코드 재발급.
- 워크스페이스 관련 동작은 Supabase 설정/인증이 된 경우에만 노출합니다.

## 제안 도구 목록 (초안)
1) 설정
- `settings.set_llm`
  - 입력: `{ provider: "openai|anthropic|zai", model?: string }`
  - 동작: 제공자 변경 후 모델 유효성 검사. `model` 생략 시 해당 제공자의 첫 모델로 설정.
- `settings.set_active_agent`
  - 입력: `{ name: string }`
  - 동작: `AppSettings.activeAgentName` 갱신. 존재하지 않으면 에러.

2) 에이전트 관리 (로컬/워크스페이스 인식)
- `agent.create`
  - 입력: `{ name: string, wake_word?: string, description?: string, workspace_id?: string }`
  - 동작: `ContextService.createAgent(...)` 호출. 워크스페이스 지정 시 해당 경로에 `config.json`/`persona.md` 생성.
- `agent.list`
  - 입력: `{ workspace_id?: string }`
  - 동작: 에이전트 이름 목록 반환.

3) 컨텍스트 편집
- `context.update_base_system_prompt`
  - 입력: `{ mode: "replace|append", content: string }`
  - 동작: `system_prompt.md` 교체 또는 덧붙이기.

4) 프로필 관리
- `profile.create`
  - 입력: `{ name: string, alias?: string[] }`
  - 동작: 새 `UserProfile` 추가, `profiles.json` 저장.
- `profile.merge`
  - 입력: `{ source: string, target: string, merge_memory: "append|skip|replace" }`
  - 동작: 이름/별칭 기준으로 두 프로필 병합. 개인 기억(`memory/{userId}.md`)은 전략에 따라 병합. 대화의 `userId`(문자열)도 target로 이관.
- `profile.rename`
  - 입력: `{ from: string, to: string }`
  - 동작: 이름 변경 및 `profiles.json` 반영.
- `profile.add_alias`
  - 입력: `{ name: string, alias: string }`
  - 동작: 해당 프로필에 별칭 추가.

5) 워크스페이스 (Supabase 구성 시)
- `workspace.create`
  - 입력: `{ name: string }`
  - 동작: `SupabaseService.createWorkspace` 호출, 생성된 초대 코드 반환.
- `workspace.join_by_invite`
  - 입력: `{ invite_code: string }`
  - 동작: `SupabaseService.joinWorkspace` 호출, 현재 워크스페이스로 전환.
- `workspace.list`
  - 입력: `{}`
  - 동작: 현재 사용자가 속한 워크스페이스 목록 반환.
- `workspace.switch`
  - 입력: `{ id: string }`
  - 동작: `SupabaseService.setCurrentWorkspace` 호출.
- `workspace.regenerate_invite_code`
  - 입력: `{ id: string }`
  - 동작: 새 초대 코드 발급(권한 체크 필요).

## 기술 설계
- 구조 확장
  - `Dochi/Services/BuiltInTools/`에 새 모듈 추가: `SettingsTool.swift`, `AgentTool.swift`, `ContextEditTool.swift`, `ProfileAdminTool.swift`, `WorkspaceTool.swift`.
  - 각 모듈은 `BuiltInTool` 프로토콜을 준수하고 `tools: [MCPToolInfo]`와 `callTool(...)` 구현.
  - `BuiltInToolService`에 위 모듈을 보유하고 `availableTools`에 조건부로 노출.
- 상태/저장소 연동
  - 설정: `AppSettings` 인스턴스 참조를 `BuiltInToolService`에 주입하거나, 각 Tool에 의존성 주입. 모델-제공자 유효성 검사(`LLMProvider.models`) 적용.
  - 에이전트/컨텍스트: `ContextServiceProtocol`을 사용, 워크스페이스 ID가 있으면 워크스페이스 경로 사용.
  - 프로필 병합: `profiles.json` 로드/저장 + 개인 기억 파일 이동/머지 + `Conversation.userId` 매핑 업데이트.
  - 워크스페이스: `SupabaseServiceProtocol` 사용. 미구성/미인증 시 도구 비노출 또는 에러 반환.
- LLM 도구 사양
  - 각 도구는 `MCPToolInfo(name, description, inputSchema)`로 스키마 정의(OpenAI/Anthropic 양쪽 호환).
  - 반환은 사용자 가독성 중심의 요약 문자열. 필요 시 구조화된 텍스트(JSON snippet)를 포함.
- 통합 포인트
  - `DochiViewModel.sendLLMRequest(...)` 경로에서 이미 `BuiltInToolService.availableTools`를 합성 중 — 새 도구 자동 반영.

## 보안/가드레일
- 위험 작업(프로필 병합/삭제, 워크스페이스 전환)은 확인 플래그가 없으면 no-op 또는 미리보기만 반환 후 재호출 시 적용.
- 워크스페이스 도구는 인증 필요. 권한(Owner/Member)에 따라 제한.
- 파일 입출력은 앱 전용 디렉토리 하위만 허용.

## 수락 기준
- 대화에서 “모델을 anthropic/claude-haiku-4-5-20251001로 바꿔” → `settings.set_llm` 실행, `AppSettings` 반영, 이후 요청에 새 모델 사용.
- “에이전트 ‘여행도치’ 만들어줘” → `agent.create`로 디렉토리/설정/기본 페르소나 생성.
- “민수와 민서 프로필 합쳐줘, 기억은 append” → `profile.merge` 수행, 개인 기억 병합 및 대화 userId 이관.
- Supabase 구성 시 “초대 코드 ABCD1234로 참여해” → `workspace.join_by_invite` 성공, 현재 워크스페이스 전환.

## 작업 항목
1. Tool 모듈 스캐폴딩 및 `BuiltInToolService` 통합
2. `SettingsTool`: 제공자/모델 변경, 활성 에이전트 전환
3. `AgentTool`: 생성/목록(워크스페이스 인식)
4. `ContextEditTool`: base system prompt 교체/추가
5. `ProfileAdminTool`: 생성/병합/개명/별칭 추가 + 기억/대화 이관 로직
6. `WorkspaceTool`: 생성/참여/목록/전환/초대코드 재발급(권한체크)
7. 에러/권한/확인 플래그 처리, 로깅
8. 기본 단위 테스트(프로필 병합, 에이전트 생성, 설정 변경)

## 오픈 이슈
- 프로필 병합 시 충돌 해결 정책(동명이인, 별칭 중복) 세부 규칙 확정 필요.
- 대화 `userId`가 문자열인 현 구조에서 UUID 안정성/마이그레이션 여부.
- 워크스페이스 권한 모델(Owner만 초대코드 재발급 등) UI/도구 일관화.

