import Foundation

/// 터미널 세션 모델
struct TerminalSession: Identifiable, Sendable {
    let id: UUID
    var name: String
    var currentDirectory: String
    var outputLines: [TerminalOutputLine]
    var isRunning: Bool
    var commandHistory: [String]
    var historyIndex: Int?

    init(
        id: UUID = UUID(),
        name: String = "터미널",
        currentDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        outputLines: [TerminalOutputLine] = [],
        isRunning: Bool = false,
        commandHistory: [String] = [],
        historyIndex: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.currentDirectory = currentDirectory
        self.outputLines = outputLines
        self.isRunning = isRunning
        self.commandHistory = commandHistory
        self.historyIndex = historyIndex
    }
}

/// 터미널 출력 라인 모델
struct TerminalOutputLine: Identifiable, Sendable {
    let id: UUID
    let text: String
    let type: OutputType
    let timestamp: Date

    init(
        id: UUID = UUID(),
        text: String,
        type: OutputType,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.type = type
        self.timestamp = timestamp
    }
}

/// 출력 유형
enum OutputType: Sendable {
    case stdout
    case stderr
    case system
    case llmCommand
    case llmPrompt
}
