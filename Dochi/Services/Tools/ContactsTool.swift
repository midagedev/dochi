import Foundation
import os

// MARK: - Search Contacts

@MainActor
final class ContactsSearchTool: BuiltInToolProtocol {
    let name = "contacts.search"
    let category: ToolCategory = .safe
    let description = "Apple 연락처에서 이름으로 검색합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "query": ["type": "string", "description": "검색할 이름 (부분 일치)"],
                "limit": ["type": "integer", "description": "최대 결과 수 (기본: 10)"],
            ] as [String: Any],
            "required": ["query"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            return ToolResult(toolCallId: "", content: "query 파라미터가 필요합니다.", isError: true)
        }
        let limit = arguments["limit"] as? Int ?? 10

        let script = """
        tell application "Contacts"
            set matchedPeople to (every person whose name contains "\(CreateReminderTool.escapeAppleScript(query))")
            set output to ""
            set counter to 0
            repeat with p in matchedPeople
                if counter ≥ \(limit) then exit repeat
                set pLine to name of p
                set phoneNums to value of phones of p
                if (count of phoneNums) > 0 then
                    set pLine to pLine & " | 전화: " & (item 1 of phoneNums)
                end if
                set emailAddrs to value of emails of p
                if (count of emailAddrs) > 0 then
                    set pLine to pLine & " | 이메일: " & (item 1 of emailAddrs)
                end if
                set output to output & pLine & linefeed
                set counter to counter + 1
            end repeat
            return output
        end tell
        """

        let result = await runAppleScript(script)
        switch result {
        case .success(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return ToolResult(toolCallId: "", content: "'\(query)' 검색 결과가 없습니다.")
            }
            Log.tool.info("Searched contacts: \(query)")
            return ToolResult(toolCallId: "", content: "연락처 검색 결과:\n\(trimmed)")
        case .failure(let error):
            Log.tool.error("Failed to search contacts: \(error.message)")
            return ToolResult(toolCallId: "", content: "연락처 검색 실패: \(error.message). 연락처 앱 접근 권한을 확인해주세요.", isError: true)
        }
    }
}

// MARK: - Get Contact Detail

@MainActor
final class ContactsGetDetailTool: BuiltInToolProtocol {
    let name = "contacts.get_detail"
    let category: ToolCategory = .safe
    let description = "Apple 연락처에서 특정 사람의 상세 정보를 조회합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "조회할 사람의 이름 (정확히 일치)"],
            ] as [String: Any],
            "required": ["name"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let name = arguments["name"] as? String, !name.isEmpty else {
            return ToolResult(toolCallId: "", content: "name 파라미터가 필요합니다.", isError: true)
        }

        let script = """
        tell application "Contacts"
            set matchedPeople to (every person whose name is "\(CreateReminderTool.escapeAppleScript(name))")
            if (count of matchedPeople) is 0 then
                return "NOT_FOUND"
            end if

            set p to item 1 of matchedPeople
            set output to "이름: " & (name of p)

            if organization of p is not missing value then
                set output to output & linefeed & "회사: " & (organization of p)
            end if
            if job title of p is not missing value then
                set output to output & linefeed & "직책: " & (job title of p)
            end if

            set phoneNums to phones of p
            repeat with ph in phoneNums
                set output to output & linefeed & "전화 (" & (label of ph) & "): " & (value of ph)
            end repeat

            set emailAddrs to emails of p
            repeat with em in emailAddrs
                set output to output & linefeed & "이메일 (" & (label of em) & "): " & (value of em)
            end repeat

            set addrs to addresses of p
            repeat with addr in addrs
                set output to output & linefeed & "주소 (" & (label of addr) & "): " & (formatted address of addr)
            end repeat

            if birth date of p is not missing value then
                set output to output & linefeed & "생일: " & (birth date of p as string)
            end if

            if note of p is not missing value then
                set output to output & linefeed & "메모: " & (note of p)
            end if

            return output
        end tell
        """

        let result = await runAppleScript(script)
        switch result {
        case .success(let output):
            if output.contains("NOT_FOUND") {
                return ToolResult(toolCallId: "", content: "'\(name)'을(를) 연락처에서 찾을 수 없습니다.", isError: true)
            }
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            Log.tool.info("Got contact detail: \(name)")
            return ToolResult(toolCallId: "", content: trimmed)
        case .failure(let error):
            Log.tool.error("Failed to get contact detail: \(error.message)")
            return ToolResult(toolCallId: "", content: "연락처 조회 실패: \(error.message)", isError: true)
        }
    }
}
