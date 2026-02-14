import Foundation
import os

// MARK: - Create Workflow

@MainActor
final class WorkflowCreateTool: BuiltInToolProtocol {
    let name = "workflow.create"
    let category: ToolCategory = .safe
    let description = "다단계 자동화 워크플로우를 생성합니다. 단계별로 도구를 체이닝하여 복잡한 작업을 자동화할 수 있습니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "워크플로우 이름"],
                "description": ["type": "string", "description": "워크플로우 설명"],
                "steps": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "action": ["type": "string", "description": "도구 이름 (예: kanban.add_card)"],
                            "input": [
                                "type": "object",
                                "description": "도구 입력. {{변수명}}으로 이전 단계 결과 참조",
                                "additionalProperties": ["type": "string"],
                            ] as [String: Any],
                            "output_key": ["type": "string", "description": "이 단계 결과를 저장할 변수명"],
                            "description": ["type": "string", "description": "단계 설명"],
                        ] as [String: Any],
                        "required": ["action"],
                    ] as [String: Any],
                    "description": "워크플로우 단계 목록 (순서대로 실행)",
                ] as [String: Any],
                "trigger": [
                    "type": "string",
                    "enum": ["manual", "keyword"],
                    "description": "트리거 유형 (기본: manual)",
                ],
                "trigger_pattern": ["type": "string", "description": "keyword 트리거 시 감지할 패턴"],
            ] as [String: Any],
            "required": ["name", "steps"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let name = arguments["name"] as? String, !name.isEmpty else {
            return ToolResult(toolCallId: "", content: "name 파라미터가 필요합니다.", isError: true)
        }
        guard let stepsRaw = arguments["steps"] as? [[String: Any]], !stepsRaw.isEmpty else {
            return ToolResult(toolCallId: "", content: "steps 파라미터가 필요합니다 (최소 1단계).", isError: true)
        }

        var steps: [WorkflowStep] = []
        for (idx, stepDict) in stepsRaw.enumerated() {
            guard let action = stepDict["action"] as? String, !action.isEmpty else {
                return ToolResult(toolCallId: "", content: "단계 \(idx + 1)에 action이 필요합니다.", isError: true)
            }
            let inputDict = stepDict["input"] as? [String: String] ?? [:]
            let outputKey = stepDict["output_key"] as? String ?? ""
            let desc = stepDict["description"] as? String ?? ""
            steps.append(WorkflowStep(action: action, inputTemplate: inputDict, outputKey: outputKey, description: desc))
        }

        let triggerType = arguments["trigger"] as? String ?? "manual"
        let trigger: WorkflowTrigger
        if triggerType == "keyword", let pattern = arguments["trigger_pattern"] as? String {
            trigger = .keyword(pattern: pattern)
        } else {
            trigger = .manual
        }

        let desc = arguments["description"] as? String ?? ""
        let workflow = WorkflowManager.shared.createWorkflow(name: name, description: desc, steps: steps, trigger: trigger)

        var output = "워크플로우 생성: \(name) [\(workflow.id.uuidString.prefix(8))]\n"
        output += "단계 \(steps.count)개:\n"
        for (idx, step) in steps.enumerated() {
            output += "  \(idx + 1). \(step.action)"
            if !step.description.isEmpty { output += " — \(step.description)" }
            if !step.outputKey.isEmpty { output += " → {{\(step.outputKey)}}" }
            output += "\n"
        }

        return ToolResult(toolCallId: "", content: output)
    }
}

// MARK: - List Workflows

@MainActor
final class WorkflowListTool: BuiltInToolProtocol {
    let name = "workflow.list"
    let category: ToolCategory = .safe
    let description = "등록된 워크플로우 목록을 조회합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [:] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let workflows = WorkflowManager.shared.listWorkflows()
        guard !workflows.isEmpty else {
            return ToolResult(toolCallId: "", content: "등록된 워크플로우가 없습니다. workflow.create로 생성하세요.")
        }

        let lines = workflows.map { wf in
            let status = wf.enabled ? "✅" : "⏸️"
            let triggerStr: String
            switch wf.trigger {
            case .manual: triggerStr = "수동"
            case .schedule(let cron): triggerStr = "스케줄(\(cron))"
            case .keyword(let pattern): triggerStr = "키워드(\(pattern))"
            }
            return "\(status) \(wf.name) [\(wf.id.uuidString.prefix(8))] — \(wf.steps.count)단계, \(triggerStr)"
        }

        return ToolResult(toolCallId: "", content: "워크플로우 (\(workflows.count)개):\n\(lines.joined(separator: "\n"))")
    }
}

// MARK: - Run Workflow

@MainActor
final class WorkflowRunTool: BuiltInToolProtocol {
    let name = "workflow.run"
    let category: ToolCategory = .sensitive
    let description = "워크플로우를 실행합니다. 각 단계의 도구를 순서대로 호출하고 결과를 체이닝합니다."
    let isBaseline = true

    private let toolExecutor: WorkflowManager.ToolExecutor

    init(toolExecutor: @escaping WorkflowManager.ToolExecutor) {
        self.toolExecutor = toolExecutor
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "workflow_name": ["type": "string", "description": "워크플로우 이름 (부분 일치)"],
                "workflow_id": ["type": "string", "description": "워크플로우 ID (8자 prefix)"],
                "context": [
                    "type": "object",
                    "description": "초기 컨텍스트 변수 (예: {\"topic\": \"AI 뉴스\"})",
                    "additionalProperties": ["type": "string"],
                ] as [String: Any],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let workflow: Workflow?
        if let idPrefix = arguments["workflow_id"] as? String {
            workflow = WorkflowManager.shared.listWorkflows().first {
                $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased())
            }
        } else if let name = arguments["workflow_name"] as? String {
            workflow = WorkflowManager.shared.workflow(name: name)
        } else {
            return ToolResult(toolCallId: "", content: "workflow_name 또는 workflow_id가 필요합니다.", isError: true)
        }

        guard let workflow else {
            return ToolResult(toolCallId: "", content: "워크플로우를 찾을 수 없습니다.", isError: true)
        }

        let initialContext = (arguments["context"] as? [String: String]) ?? [:]

        guard let run = await WorkflowManager.shared.executeWorkflow(
            id: workflow.id,
            initialContext: initialContext,
            toolExecutor: toolExecutor
        ) else {
            return ToolResult(toolCallId: "", content: "워크플로우 실행 실패 (비활성 또는 존재하지 않음).", isError: true)
        }

        var output = run.success ? "✅ 워크플로우 완료: \(workflow.name)\n" : "❌ 워크플로우 실패: \(workflow.name)\n"
        for (idx, result) in run.stepResults.enumerated() {
            let icon: String
            switch result.status {
            case .completed: icon = "✅"
            case .failed: icon = "❌"
            case .running: icon = "🔄"
            case .pending: icon = "⏳"
            case .skipped: icon = "⏭️"
            }
            let preview = String(result.output.prefix(100))
            output += "  \(idx + 1). \(icon) \(result.action): \(preview)\n"
        }

        return ToolResult(toolCallId: "", content: output)
    }
}

// MARK: - Delete Workflow

@MainActor
final class WorkflowDeleteTool: BuiltInToolProtocol {
    let name = "workflow.delete"
    let category: ToolCategory = .safe
    let description = "워크플로우를 삭제합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "workflow_name": ["type": "string", "description": "워크플로우 이름 (부분 일치)"],
                "workflow_id": ["type": "string", "description": "워크플로우 ID (8자 prefix)"],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let workflow: Workflow?
        if let idPrefix = arguments["workflow_id"] as? String {
            workflow = WorkflowManager.shared.listWorkflows().first {
                $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased())
            }
        } else if let name = arguments["workflow_name"] as? String {
            workflow = WorkflowManager.shared.workflow(name: name)
        } else {
            return ToolResult(toolCallId: "", content: "workflow_name 또는 workflow_id가 필요합니다.", isError: true)
        }

        guard let workflow else {
            return ToolResult(toolCallId: "", content: "워크플로우를 찾을 수 없습니다.", isError: true)
        }

        WorkflowManager.shared.deleteWorkflow(id: workflow.id)
        return ToolResult(toolCallId: "", content: "워크플로우 삭제: \(workflow.name)")
    }
}

// MARK: - Add Step

@MainActor
final class WorkflowAddStepTool: BuiltInToolProtocol {
    let name = "workflow.add_step"
    let category: ToolCategory = .safe
    let description = "기존 워크플로우에 단계를 추가합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "workflow_name": ["type": "string", "description": "워크플로우 이름"],
                "action": ["type": "string", "description": "도구 이름"],
                "input": [
                    "type": "object",
                    "description": "도구 입력 ({{변수명}}으로 이전 단계 결과 참조)",
                    "additionalProperties": ["type": "string"],
                ] as [String: Any],
                "output_key": ["type": "string", "description": "결과를 저장할 변수명"],
                "description": ["type": "string", "description": "단계 설명"],
            ] as [String: Any],
            "required": ["workflow_name", "action"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let wfName = arguments["workflow_name"] as? String else {
            return ToolResult(toolCallId: "", content: "workflow_name 파라미터가 필요합니다.", isError: true)
        }
        guard let action = arguments["action"] as? String, !action.isEmpty else {
            return ToolResult(toolCallId: "", content: "action 파라미터가 필요합니다.", isError: true)
        }
        guard let workflow = WorkflowManager.shared.workflow(name: wfName) else {
            return ToolResult(toolCallId: "", content: "'\(wfName)' 워크플로우를 찾을 수 없습니다.", isError: true)
        }

        let inputTemplate = arguments["input"] as? [String: String] ?? [:]
        let outputKey = arguments["output_key"] as? String ?? ""
        let desc = arguments["description"] as? String ?? ""

        let step = WorkflowStep(action: action, inputTemplate: inputTemplate, outputKey: outputKey, description: desc)
        guard WorkflowManager.shared.addStep(workflowId: workflow.id, step: step) else {
            return ToolResult(toolCallId: "", content: "단계 추가 실패.", isError: true)
        }

        let stepCount = WorkflowManager.shared.workflow(id: workflow.id)?.steps.count ?? 0
        return ToolResult(toolCallId: "", content: "단계 추가: \(action) → \(workflow.name) (총 \(stepCount)단계)")
    }
}

// MARK: - Workflow History

@MainActor
final class WorkflowHistoryTool: BuiltInToolProtocol {
    let name = "workflow.history"
    let category: ToolCategory = .safe
    let description = "워크플로우 실행 기록을 조회합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "workflow_name": ["type": "string", "description": "워크플로우 이름 (생략하면 전체)"],
                "limit": ["type": "integer", "description": "최대 조회 수 (기본: 5)"],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let limit = arguments["limit"] as? Int ?? 5
        var runs = WorkflowManager.shared.runs

        if let name = arguments["workflow_name"] as? String {
            runs = runs.filter { $0.workflowName.localizedCaseInsensitiveContains(name) }
        }

        let recent = runs.suffix(limit)
        guard !recent.isEmpty else {
            return ToolResult(toolCallId: "", content: "실행 기록이 없습니다.")
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"

        let lines = recent.map { run in
            let icon = run.success ? "✅" : "❌"
            let time = formatter.string(from: run.startedAt)
            let steps = "\(run.stepResults.filter { $0.status == .completed }.count)/\(run.stepResults.count)"
            return "\(icon) \(run.workflowName) [\(time)] — \(steps) 단계 완료"
        }

        return ToolResult(toolCallId: "", content: "실행 기록:\n\(lines.joined(separator: "\n"))")
    }
}
