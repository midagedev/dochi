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

        let normalizedNames = normalizeRequestedNames(names)
        let previouslyEnabled = registry.enabledToolNames
        registry.enable(names: normalizedNames)

        let valid = normalizedNames.filter { registry.tool(named: $0) != nil }
        let invalid = normalizedNames.filter { registry.tool(named: $0) == nil }
        let newlyEnabled = valid.filter { !previouslyEnabled.contains($0) }
        let alreadyEnabled = valid.filter { previouslyEnabled.contains($0) }

        var lines: [String] = []
        if !newlyEnabled.isEmpty {
            lines.append("도구 활성화 완료: \(newlyEnabled.joined(separator: ", "))")
        }
        if !alreadyEnabled.isEmpty {
            lines.append("이미 활성화된 도구: \(alreadyEnabled.joined(separator: ", "))")
            lines.append("같은 tools.enable 호출을 반복하지 말고, 이제 실제 작업 도구를 호출하세요.")
        }
        if !invalid.isEmpty {
            lines.append("찾을 수 없는 도구: \(invalid.joined(separator: ", "))")
        }
        if lines.isEmpty {
            lines.append("활성화 가능한 도구가 없습니다.")
        }
        return ToolResult(toolCallId: "", content: lines.joined(separator: "\n"))
    }

    private func normalizeRequestedNames(_ names: [String]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []

        for rawName in names {
            let normalized = normalizeRequestedName(rawName)
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }

        return result
    }

    private func normalizeRequestedName(_ rawName: String) -> String {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return name }

        // LLM이 반환하는 sanitized 표기(codex-_-desktop_activate)를 복원
        name = name.replacingOccurrences(of: "-_-", with: ".")

        // 일부 모델이 잘못 붙이는 function namespace 접두어 제거
        for prefix in ["functions.", "function."] {
            while name.hasPrefix(prefix) {
                name.removeFirst(prefix.count)
            }
        }

        if registry.tool(named: name) != nil {
            return name
        }

        if let canonical = registry.allToolNames.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            return canonical
        }

        return name
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
