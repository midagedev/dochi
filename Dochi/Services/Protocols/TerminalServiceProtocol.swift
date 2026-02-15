import Foundation

/// 터미널 서비스 프로토콜 — Process/Pipe 기반 쉘 세션 관리
@MainActor
protocol TerminalServiceProtocol: AnyObject {
    /// 현재 활성 세션 목록
    var sessions: [TerminalSession] { get }

    /// 현재 선택된 세션 ID
    var activeSessionId: UUID? { get set }

    /// 최대 세션 수
    var maxSessions: Int { get }

    /// 새 세션 생성
    @discardableResult
    func createSession(name: String?, shellPath: String?) -> UUID

    /// 세션 종료
    func closeSession(id: UUID)

    /// 명령 실행
    func executeCommand(_ command: String, in sessionId: UUID)

    /// 출력 지우기
    func clearOutput(for sessionId: UUID)

    /// 현재 실행 중인 프로세스 종료 (Ctrl+C)
    func interrupt(sessionId: UUID)

    /// 명령 히스토리 탐색 (direction: -1=이전, 1=다음)
    func navigateHistory(sessionId: UUID, direction: Int) -> String?

    /// LLM 도구용 명령 실행 및 결과 반환 (C-2)
    func runCommand(_ command: String, timeout: Int?) async -> (output: String, exitCode: Int32, isError: Bool)

    /// 세션 출력 변경 콜백
    var onOutputUpdate: ((UUID) -> Void)? { get set }

    /// 세션 종료 콜백
    var onSessionClosed: ((UUID) -> Void)? { get set }
}
