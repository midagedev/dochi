import XCTest
@testable import Dochi

@MainActor
final class WorkflowTests: XCTestCase {
    private var tempDir: URL!
    private var manager: WorkflowManager!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkflowTests_\(UUID().uuidString)")
        manager = WorkflowManager(storageDir: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - WorkflowStep Model

    func testWorkflowStepInit() {
        let step = WorkflowStep(action: "kanban.add_card", inputTemplate: ["title": "{{task}}"], outputKey: "result")
        XCTAssertEqual(step.action, "kanban.add_card")
        XCTAssertEqual(step.inputTemplate["title"], "{{task}}")
        XCTAssertEqual(step.outputKey, "result")
    }

    func testWorkflowStepDefaults() {
        let step = WorkflowStep(action: "test.tool")
        XCTAssertTrue(step.inputTemplate.isEmpty)
        XCTAssertEqual(step.outputKey, "")
        XCTAssertEqual(step.description, "")
    }

    // MARK: - WorkflowTrigger Codable

    func testManualTriggerCodable() throws {
        let trigger = WorkflowTrigger.manual
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(WorkflowTrigger.self, from: data)
        if case .manual = decoded {} else { XCTFail("Expected manual trigger") }
    }

    func testScheduleTriggerCodable() throws {
        let trigger = WorkflowTrigger.schedule(cron: "0 9 * * *")
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(WorkflowTrigger.self, from: data)
        if case .schedule(let cron) = decoded {
            XCTAssertEqual(cron, "0 9 * * *")
        } else {
            XCTFail("Expected schedule trigger")
        }
    }

    func testKeywordTriggerCodable() throws {
        let trigger = WorkflowTrigger.keyword(pattern: "뉴스 요약")
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(WorkflowTrigger.self, from: data)
        if case .keyword(let pattern) = decoded {
            XCTAssertEqual(pattern, "뉴스 요약")
        } else {
            XCTFail("Expected keyword trigger")
        }
    }

    // MARK: - Workflow Model

    func testWorkflowInitDefaults() {
        let workflow = Workflow(name: "테스트")
        XCTAssertEqual(workflow.name, "테스트")
        XCTAssertTrue(workflow.steps.isEmpty)
        XCTAssertTrue(workflow.enabled)
        if case .manual = workflow.trigger {} else { XCTFail("Expected manual trigger") }
    }

    func testWorkflowCodableRoundtrip() throws {
        let step = WorkflowStep(action: "test.tool", inputTemplate: ["key": "value"], outputKey: "out")
        let workflow = Workflow(
            name: "인코딩 테스트",
            description: "설명",
            steps: [step],
            trigger: .keyword(pattern: "시작")
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(workflow)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Workflow.self, from: data)

        XCTAssertEqual(decoded.name, "인코딩 테스트")
        XCTAssertEqual(decoded.description, "설명")
        XCTAssertEqual(decoded.steps.count, 1)
        XCTAssertEqual(decoded.steps[0].action, "test.tool")
        XCTAssertEqual(decoded.steps[0].outputKey, "out")
        if case .keyword(let pattern) = decoded.trigger {
            XCTAssertEqual(pattern, "시작")
        } else {
            XCTFail("Expected keyword trigger")
        }
    }

    // MARK: - WorkflowRun Model

    func testWorkflowRunInit() {
        let run = WorkflowRun(workflowId: UUID(), workflowName: "테스트")
        XCTAssertTrue(run.stepResults.isEmpty)
        XCTAssertTrue(run.context.isEmpty)
        XCTAssertFalse(run.success)
        XCTAssertNil(run.completedAt)
    }

    // MARK: - Manager CRUD

    func testCreateWorkflow() {
        let wf = manager.createWorkflow(name: "프로젝트 워크플로우")
        XCTAssertEqual(wf.name, "프로젝트 워크플로우")
        XCTAssertEqual(manager.listWorkflows().count, 1)
    }

    func testCreateWorkflowWithSteps() {
        let steps = [
            WorkflowStep(action: "step1"),
            WorkflowStep(action: "step2"),
        ]
        let wf = manager.createWorkflow(name: "다단계", steps: steps)
        XCTAssertEqual(wf.steps.count, 2)
    }

    func testListWorkflowsSorted() {
        let w1 = manager.createWorkflow(name: "First")
        let w2 = manager.createWorkflow(name: "Second")
        let list = manager.listWorkflows()
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].id, w1.id)
        XCTAssertEqual(list[1].id, w2.id)
    }

    func testWorkflowById() {
        let wf = manager.createWorkflow(name: "Find")
        XCTAssertNotNil(manager.workflow(id: wf.id))
        XCTAssertNil(manager.workflow(id: UUID()))
    }

    func testWorkflowByName() {
        _ = manager.createWorkflow(name: "모닝 브리핑")
        XCTAssertNotNil(manager.workflow(name: "모닝"))
        XCTAssertNotNil(manager.workflow(name: "모닝 브리핑"))
        XCTAssertNil(manager.workflow(name: "없는"))
    }

    func testUpdateWorkflow() {
        let wf = manager.createWorkflow(name: "원본")
        let result = manager.updateWorkflow(id: wf.id, name: "수정됨", enabled: false)
        XCTAssertTrue(result)

        let updated = manager.workflow(id: wf.id)!
        XCTAssertEqual(updated.name, "수정됨")
        XCTAssertFalse(updated.enabled)
    }

    func testUpdateWorkflowNonExistent() {
        let result = manager.updateWorkflow(id: UUID(), name: "실패")
        XCTAssertFalse(result)
    }

    func testAddStep() {
        let wf = manager.createWorkflow(name: "빈 워크플로우")
        XCTAssertEqual(wf.steps.count, 0)

        let step = WorkflowStep(action: "test.action")
        let result = manager.addStep(workflowId: wf.id, step: step)
        XCTAssertTrue(result)
        XCTAssertEqual(manager.workflow(id: wf.id)!.steps.count, 1)
    }

    func testAddStepNonExistent() {
        let step = WorkflowStep(action: "test")
        let result = manager.addStep(workflowId: UUID(), step: step)
        XCTAssertFalse(result)
    }

    func testDeleteWorkflow() {
        let wf = manager.createWorkflow(name: "삭제할 워크플로우")
        XCTAssertEqual(manager.listWorkflows().count, 1)
        manager.deleteWorkflow(id: wf.id)
        XCTAssertEqual(manager.listWorkflows().count, 0)
    }

    // MARK: - Template Resolution

    func testResolveTemplateSimple() {
        let result = WorkflowManager.resolveTemplate("Hello {{name}}!", context: ["name": "World"])
        XCTAssertEqual(result, "Hello World!")
    }

    func testResolveTemplateMultiple() {
        let result = WorkflowManager.resolveTemplate(
            "{{greeting}} {{name}}, today is {{day}}",
            context: ["greeting": "Hi", "name": "도치", "day": "금요일"]
        )
        XCTAssertEqual(result, "Hi 도치, today is 금요일")
    }

    func testResolveTemplateNoPlaceholders() {
        let result = WorkflowManager.resolveTemplate("plain text", context: ["key": "value"])
        XCTAssertEqual(result, "plain text")
    }

    func testResolveTemplateMissingKey() {
        let result = WorkflowManager.resolveTemplate("Hello {{missing}}", context: [:])
        XCTAssertEqual(result, "Hello {{missing}}") // unreplaced
    }

    func testResolveInputs() {
        let inputs = WorkflowManager.resolveInputs(
            ["query": "{{topic}} 뉴스", "limit": "10"],
            context: ["topic": "AI"]
        )
        XCTAssertEqual(inputs["query"], "AI 뉴스")
        XCTAssertEqual(inputs["limit"], "10")
    }

    // MARK: - Execution

    func testExecuteWorkflowSuccess() async {
        let steps = [
            WorkflowStep(action: "tool.a", outputKey: "resultA"),
            WorkflowStep(action: "tool.b", inputTemplate: ["input": "{{resultA}}"], outputKey: "resultB"),
        ]
        let wf = manager.createWorkflow(name: "성공 워크플로우", steps: steps)

        let run = await manager.executeWorkflow(id: wf.id) { action, args in
            if action == "tool.a" {
                return ToolResult(toolCallId: "", content: "출력A")
            } else if action == "tool.b" {
                let input = args["input"] ?? ""
                return ToolResult(toolCallId: "", content: "출력B(\(input))")
            }
            return ToolResult(toolCallId: "", content: "unknown", isError: true)
        }

        XCTAssertNotNil(run)
        XCTAssertTrue(run!.success)
        XCTAssertEqual(run!.stepResults.count, 2)
        XCTAssertEqual(run!.stepResults[0].status, .completed)
        XCTAssertEqual(run!.stepResults[1].status, .completed)
        XCTAssertEqual(run!.context["resultA"], "출력A")
        XCTAssertEqual(run!.context["resultB"], "출력B(출력A)")
    }

    func testExecuteWorkflowFailsOnError() async {
        let steps = [
            WorkflowStep(action: "tool.ok", outputKey: "ok"),
            WorkflowStep(action: "tool.fail"),
            WorkflowStep(action: "tool.unreached"),
        ]
        let wf = manager.createWorkflow(name: "실패 워크플로우", steps: steps)

        let run = await manager.executeWorkflow(id: wf.id) { action, _ in
            if action == "tool.fail" {
                return ToolResult(toolCallId: "", content: "에러 발생", isError: true)
            }
            return ToolResult(toolCallId: "", content: "ok")
        }

        XCTAssertNotNil(run)
        XCTAssertFalse(run!.success)
        XCTAssertEqual(run!.stepResults.count, 2) // stops after failure
        XCTAssertEqual(run!.stepResults[0].status, .completed)
        XCTAssertEqual(run!.stepResults[1].status, .failed)
    }

    func testExecuteDisabledWorkflow() async {
        let wf = manager.createWorkflow(name: "비활성")
        _ = manager.updateWorkflow(id: wf.id, enabled: false)

        let run = await manager.executeWorkflow(id: wf.id) { _, _ in
            ToolResult(toolCallId: "", content: "should not run")
        }
        XCTAssertNil(run)
    }

    func testExecuteNonExistentWorkflow() async {
        let run = await manager.executeWorkflow(id: UUID()) { _, _ in
            ToolResult(toolCallId: "", content: "nope")
        }
        XCTAssertNil(run)
    }

    func testExecuteWithInitialContext() async {
        let steps = [
            WorkflowStep(action: "tool.echo", inputTemplate: ["text": "{{greeting}} {{name}}"], outputKey: "msg"),
        ]
        let wf = manager.createWorkflow(name: "컨텍스트 테스트", steps: steps)

        let run = await manager.executeWorkflow(
            id: wf.id,
            initialContext: ["greeting": "안녕", "name": "도치"]
        ) { _, args in
            let text = args["text"] ?? ""
            return ToolResult(toolCallId: "", content: text)
        }

        XCTAssertNotNil(run)
        XCTAssertTrue(run!.success)
        XCTAssertEqual(run!.context["msg"], "안녕 도치")
    }

    func testRunHistoryTracked() async {
        let wf = manager.createWorkflow(
            name: "히스토리 테스트",
            steps: [WorkflowStep(action: "tool.noop")]
        )

        _ = await manager.executeWorkflow(id: wf.id) { _, _ in
            ToolResult(toolCallId: "", content: "ok")
        }
        _ = await manager.executeWorkflow(id: wf.id) { _, _ in
            ToolResult(toolCallId: "", content: "ok")
        }

        XCTAssertEqual(manager.runs.count, 2)
    }

    // MARK: - Persistence

    func testPersistenceRoundtrip() {
        let steps = [WorkflowStep(action: "test.tool", inputTemplate: ["key": "val"], outputKey: "out")]
        _ = manager.createWorkflow(name: "영속성", description: "설명", steps: steps, trigger: .keyword(pattern: "시작"))

        let manager2 = WorkflowManager(storageDir: tempDir)
        let loaded = manager2.listWorkflows()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].name, "영속성")
        XCTAssertEqual(loaded[0].steps.count, 1)
        XCTAssertEqual(loaded[0].steps[0].action, "test.tool")
        if case .keyword(let pattern) = loaded[0].trigger {
            XCTAssertEqual(pattern, "시작")
        } else {
            XCTFail("Expected keyword trigger")
        }
    }

    func testDeleteRemovesFile() {
        let wf = manager.createWorkflow(name: "삭제 파일 테스트")
        let file = tempDir.appendingPathComponent("\(wf.id.uuidString).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        manager.deleteWorkflow(id: wf.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: - Tool Tests

    func testWorkflowCreateToolMissingName() async {
        let tool = WorkflowCreateTool()
        let result = await tool.execute(arguments: ["steps": [["action": "test"]]])
        XCTAssertTrue(result.isError)
    }

    func testWorkflowCreateToolMissingSteps() async {
        let tool = WorkflowCreateTool()
        let result = await tool.execute(arguments: ["name": "test"])
        XCTAssertTrue(result.isError)
    }

    func testWorkflowListToolEmpty() async {
        let tool = WorkflowListTool()
        let result = await tool.execute(arguments: [:])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("없습니다"))
    }

    func testWorkflowDeleteToolMissingParams() async {
        let tool = WorkflowDeleteTool()
        let result = await tool.execute(arguments: [:])
        XCTAssertTrue(result.isError)
    }

    func testWorkflowAddStepToolMissingWorkflow() async {
        let tool = WorkflowAddStepTool()
        let result = await tool.execute(arguments: ["workflow_name": "없는워크플로우_\(UUID())", "action": "test"])
        XCTAssertTrue(result.isError)
    }

    func testWorkflowHistoryToolEmpty() async {
        let tool = WorkflowHistoryTool()
        let result = await tool.execute(arguments: [:])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("없습니다"))
    }
}
