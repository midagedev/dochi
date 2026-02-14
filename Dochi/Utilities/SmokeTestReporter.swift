import Foundation

/// Writes key app state to /tmp/dochi_smoke.log on launch (DEBUG builds only).
/// CI or developer scripts can read this file to verify the app initialized correctly.
enum SmokeTestReporter {
    private static let path = "/tmp/dochi_smoke.log"

    static func report(
        profileCount: Int,
        currentUserId: String?,
        currentUserName: String?,
        conversationCount: Int,
        workspaceId: String,
        agentName: String
    ) {
        #if DEBUG
        var lines: [String] = []
        lines.append("timestamp=\(ISO8601DateFormatter().string(from: Date()))")
        lines.append("profile_count=\(profileCount)")
        lines.append("current_user_id=\(currentUserId ?? "nil")")
        lines.append("current_user_name=\(currentUserName ?? "nil")")
        lines.append("conversation_count=\(conversationCount)")
        lines.append("workspace_id=\(workspaceId)")
        lines.append("agent_name=\(agentName)")
        lines.append("status=ok")

        let content = lines.joined(separator: "\n") + "\n"
        FileManager.default.createFile(
            atPath: path,
            contents: content.data(using: .utf8)
        )
        #endif
    }
}
