import Foundation
import os

@MainActor
final class ToolsListTool: BuiltInToolProtocol {
    let name = "tools.list"
    let category: ToolCategory = .safe
    let description = "사용 가능한 도구 목록을 조회합니다."
    let isBaseline = true

    private let registry: ToolRegistry

    init(registry: ToolRegistry) {
        self.registry = registry
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [String: Any]()
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let allNames = registry.allToolNames
        let enabledNames = registry.enabledToolNames

        var lines: [String] = []
        for toolName in allNames {
            guard let tool = registry.tool(named: toolName) else { continue }
            let status: String
            if tool.isBaseline {
                status = "[기본]"
            } else if enabledNames.contains(toolName) {
                status = "[활성]"
            } else {
                status = "[비활성]"
            }
            lines.append("\(status) \(toolName) — \(tool.description) [\(tool.category.rawValue)]")
        }

        Log.tool.info("Listed \(allNames.count) tools")
        return ToolResult(toolCallId: "", content: "도구 목록 (\(allNames.count)개):\n\(lines.joined(separator: "\n"))")
    }
}

@MainActor
final class ToolsEnableTool: BuiltInToolProtocol {
    let name = "tools.enable"
    let category: ToolCategory = .safe
    let description = "도구를 이름으로 활성화합니다."
    let isBaseline = true

    private let registry: ToolRegistry

    init(registry: ToolRegistry) {
        self.registry = registry
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "names": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "활성화할 도구 이름 목록"
                ]
            ],
            "required": ["names"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let names = arguments["names"] as? [String], !names.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: names는 필수입니다 (문자열 배열).", isError: true)
        }

        registry.enable(names: names)

        let valid = names.filter { registry.tool(named: $0) != nil }
        let invalid = names.filter { registry.tool(named: $0) == nil }

        var msg = "도구 활성화 완료: \(valid.joined(separator: ", "))"
        if !invalid.isEmpty {
            msg += "\n찾을 수 없는 도구: \(invalid.joined(separator: ", "))"
        }
        return ToolResult(toolCallId: "", content: msg)
    }
}

@MainActor
final class ToolsEnableTTLTool: BuiltInToolProtocol {
    let name = "tools.enable_ttl"
    let category: ToolCategory = .safe
    let description = "활성화된 도구의 TTL(유효 기간)을 설정합니다."
    let isBaseline = true

    private let registry: ToolRegistry

    init(registry: ToolRegistry) {
        self.registry = registry
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "minutes": ["type": "integer", "description": "TTL (분)"]
            ],
            "required": ["minutes"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let minutes: Int
        if let m = arguments["minutes"] as? Int {
            minutes = m
        } else if let m = arguments["minutes"] as? Double {
            minutes = Int(m)
        } else {
            return ToolResult(toolCallId: "", content: "오류: minutes는 필수입니다 (정수).", isError: true)
        }

        guard minutes > 0 else {
            return ToolResult(toolCallId: "", content: "오류: minutes는 양수여야 합니다.", isError: true)
        }

        registry.enableTTL(minutes: minutes)
        return ToolResult(toolCallId: "", content: "도구 TTL을 \(minutes)분으로 설정했습니다.")
    }
}

@MainActor
final class ToolsResetTool: BuiltInToolProtocol {
    let name = "tools.reset"
    let category: ToolCategory = .safe
    let description = "도구 레지스트리를 기본 상태로 복원합니다."
    let isBaseline = true

    private let registry: ToolRegistry

    init(registry: ToolRegistry) {
        self.registry = registry
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [String: Any]()
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        registry.reset()
        return ToolResult(toolCallId: "", content: "도구 레지스트리를 기본 상태로 복원했습니다.")
    }
}
