import Foundation
import os

// MARK: - Now Playing

@MainActor
final class MusicNowPlayingTool: BuiltInToolProtocol {
    let name = "music.now_playing"
    let category: ToolCategory = .safe
    let description = "Apple Music에서 현재 재생 중인 곡 정보를 조회합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [:] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let script = """
        tell application "Music"
            if player state is not stopped then
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                set trackDuration to duration of current track
                set trackPosition to player position

                set mins to (trackDuration div 60) as integer
                set secs to (trackDuration mod 60) as integer
                set posMins to (trackPosition div 60) as integer
                set posSecs to (trackPosition mod 60) as integer

                set stateText to "재생 중"
                if player state is paused then set stateText to "일시정지"

                set output to stateText & linefeed
                set output to output & "곡: " & trackName & linefeed
                set output to output & "아티스트: " & trackArtist & linefeed
                set output to output & "앨범: " & trackAlbum & linefeed
                set output to output & "진행: " & posMins & ":" & (text -2 thru -1 of ("0" & posSecs)) & " / " & mins & ":" & (text -2 thru -1 of ("0" & secs))
                return output
            else
                return "STOPPED"
            end if
        end tell
        """

        let result = await runAppleScript(script)
        switch result {
        case .success(let output):
            if output.contains("STOPPED") {
                return ToolResult(toolCallId: "", content: "현재 재생 중인 곡이 없습니다.")
            }
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            Log.tool.info("Got now playing info")
            return ToolResult(toolCallId: "", content: trimmed)
        case .failure(let error):
            Log.tool.error("Failed to get now playing: \(error.message)")
            return ToolResult(toolCallId: "", content: "Music 정보 조회 실패: \(error.message)", isError: true)
        }
    }
}

// MARK: - Play/Pause

@MainActor
final class MusicPlayPauseTool: BuiltInToolProtocol {
    let name = "music.play_pause"
    let category: ToolCategory = .safe
    let description = "Apple Music 재생/일시정지를 토글합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "enum": ["toggle", "play", "pause"],
                    "description": "toggle (기본), play, pause",
                ],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let action = arguments["action"] as? String ?? "toggle"

        let command: String
        let description: String

        switch action {
        case "play":
            command = "play"
            description = "재생"
        case "pause":
            command = "pause"
            description = "일시정지"
        default:
            command = "playpause"
            description = "재생/정지 토글"
        }

        let script = """
        tell application "Music"
            \(command)
            delay 0.3
            if player state is playing then
                return "PLAYING"
            else if player state is paused then
                return "PAUSED"
            else
                return "STOPPED"
            end if
        end tell
        """

        let result = await runAppleScript(script)
        switch result {
        case .success(let output):
            let state = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let stateText: String
            switch state {
            case "PLAYING": stateText = "재생 중"
            case "PAUSED": stateText = "일시정지"
            default: stateText = "정지"
            }
            Log.tool.info("Music \(description): \(stateText)")
            return ToolResult(toolCallId: "", content: "Music: \(stateText)")
        case .failure(let error):
            Log.tool.error("Failed to control music: \(error.message)")
            return ToolResult(toolCallId: "", content: "Music 제어 실패: \(error.message)", isError: true)
        }
    }
}

// MARK: - Next Track

@MainActor
final class MusicNextTrackTool: BuiltInToolProtocol {
    let name = "music.next"
    let category: ToolCategory = .safe
    let description = "Apple Music에서 다음 곡으로 넘깁니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "direction": [
                    "type": "string",
                    "enum": ["next", "previous"],
                    "description": "next (다음 곡, 기본) 또는 previous (이전 곡)",
                ],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let direction = arguments["direction"] as? String ?? "next"
        let command = direction == "previous" ? "previous track" : "next track"
        let label = direction == "previous" ? "이전" : "다음"

        let script = """
        tell application "Music"
            \(command)
            delay 0.5
            if player state is not stopped then
                return name of current track & " — " & artist of current track
            else
                return "STOPPED"
            end if
        end tell
        """

        let result = await runAppleScript(script)
        switch result {
        case .success(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "STOPPED" {
                return ToolResult(toolCallId: "", content: "\(label) 곡이 없습니다.")
            }
            Log.tool.info("Music \(label) track: \(trimmed)")
            return ToolResult(toolCallId: "", content: "\(label) 곡: \(trimmed)")
        case .failure(let error):
            Log.tool.error("Failed music next/prev: \(error.message)")
            return ToolResult(toolCallId: "", content: "Music 제어 실패: \(error.message)", isError: true)
        }
    }
}

// MARK: - Search & Play

@MainActor
final class MusicSearchPlayTool: BuiltInToolProtocol {
    let name = "music.search_play"
    let category: ToolCategory = .safe
    let description = "Apple Music 라이브러리에서 검색하여 재생합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "query": ["type": "string", "description": "검색할 곡명, 아티스트, 또는 앨범명"],
            ] as [String: Any],
            "required": ["query"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            return ToolResult(toolCallId: "", content: "query 파라미터가 필요합니다.", isError: true)
        }

        let script = """
        tell application "Music"
            set matchedTracks to (every track whose name contains "\(CreateReminderTool.escapeAppleScript(query))" or artist contains "\(CreateReminderTool.escapeAppleScript(query))")
            if (count of matchedTracks) is 0 then
                return "NOT_FOUND"
            end if
            play item 1 of matchedTracks
            delay 0.5
            return name of current track & " — " & artist of current track
        end tell
        """

        let result = await runAppleScript(script)
        switch result {
        case .success(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "NOT_FOUND" {
                return ToolResult(toolCallId: "", content: "'\(query)'에 해당하는 곡을 라이브러리에서 찾을 수 없습니다.")
            }
            Log.tool.info("Music search & play: \(trimmed)")
            return ToolResult(toolCallId: "", content: "재생 중: \(trimmed)")
        case .failure(let error):
            Log.tool.error("Failed music search: \(error.message)")
            return ToolResult(toolCallId: "", content: "Music 검색 실패: \(error.message)", isError: true)
        }
    }
}
