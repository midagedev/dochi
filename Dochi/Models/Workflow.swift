import Foundation

// MARK: - Workflow Step

/// A single step in a workflow, mapping to a tool call.
struct WorkflowStep: Codable, Identifiable, Sendable {
    let id: UUID
    var action: String              // Tool name (e.g., "web.search", "kanban.add_card")
    var inputTemplate: [String: String]  // Input arguments, may contain {{variable}} placeholders
    var outputKey: String           // Key to store this step's result in the workflow context
    var description: String

    init(
        id: UUID = UUID(),
        action: String,
        inputTemplate: [String: String] = [:],
        outputKey: String = "",
        description: String = ""
    ) {
        self.id = id
        self.action = action
        self.inputTemplate = inputTemplate
        self.outputKey = outputKey
        self.description = description
    }
}

// MARK: - Workflow Trigger

enum WorkflowTrigger: Codable, Sendable {
    case manual
    case schedule(cron: String)       // Cron expression for periodic execution
    case keyword(pattern: String)     // Keyword trigger from conversation

    enum CodingKeys: String, CodingKey {
        case type, cron, pattern
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "schedule":
            let cron = try container.decode(String.self, forKey: .cron)
            self = .schedule(cron: cron)
        case "keyword":
            let pattern = try container.decode(String.self, forKey: .pattern)
            self = .keyword(pattern: pattern)
        default:
            self = .manual
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .manual:
            try container.encode("manual", forKey: .type)
        case .schedule(let cron):
            try container.encode("schedule", forKey: .type)
            try container.encode(cron, forKey: .cron)
        case .keyword(let pattern):
            try container.encode("keyword", forKey: .type)
            try container.encode(pattern, forKey: .pattern)
        }
    }
}

// MARK: - Workflow

struct Workflow: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var description: String
    var steps: [WorkflowStep]
    var trigger: WorkflowTrigger
    var enabled: Bool
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        steps: [WorkflowStep] = [],
        trigger: WorkflowTrigger = .manual,
        enabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.steps = steps
        self.trigger = trigger
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Workflow Run

enum WorkflowStepStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
    case skipped
}

struct WorkflowStepResult: Codable, Sendable {
    let stepId: UUID
    let action: String
    var status: WorkflowStepStatus
    var output: String
    let startedAt: Date
    var completedAt: Date?
}

struct WorkflowRun: Codable, Identifiable, Sendable {
    let id: UUID
    let workflowId: UUID
    let workflowName: String
    var stepResults: [WorkflowStepResult]
    var context: [String: String]    // Accumulated step outputs
    let startedAt: Date
    var completedAt: Date?
    var success: Bool

    init(
        id: UUID = UUID(),
        workflowId: UUID,
        workflowName: String,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.workflowId = workflowId
        self.workflowName = workflowName
        self.stepResults = []
        self.context = [:]
        self.startedAt = startedAt
        self.completedAt = nil
        self.success = false
    }
}

// MARK: - Workflow Manager

@MainActor
final class WorkflowManager {
    static let shared = WorkflowManager()

    private(set) var workflows: [UUID: Workflow] = [:]
    private(set) var runs: [WorkflowRun] = []
    private let storageDir: URL

    private init() {
        storageDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dochi/workflows", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        loadAll()
    }

    /// Testable initializer with custom storage directory.
    init(storageDir: URL) {
        self.storageDir = storageDir
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        loadAll()
    }

    // MARK: - CRUD

    @discardableResult
    func createWorkflow(name: String, description: String = "", steps: [WorkflowStep] = [], trigger: WorkflowTrigger = .manual) -> Workflow {
        let workflow = Workflow(name: name, description: description, steps: steps, trigger: trigger)
        workflows[workflow.id] = workflow
        save(workflow)
        Log.tool.info("Created workflow: \(name) with \(steps.count) steps")
        return workflow
    }

    func listWorkflows() -> [Workflow] {
        Array(workflows.values).sorted { $0.createdAt < $1.createdAt }
    }

    func workflow(id: UUID) -> Workflow? {
        workflows[id]
    }

    func workflow(name: String) -> Workflow? {
        workflows.values.first { $0.name.localizedCaseInsensitiveContains(name) }
    }

    func updateWorkflow(id: UUID, name: String? = nil, description: String? = nil, steps: [WorkflowStep]? = nil, trigger: WorkflowTrigger? = nil, enabled: Bool? = nil) -> Bool {
        guard var workflow = workflows[id] else { return false }
        if let name { workflow.name = name }
        if let description { workflow.description = description }
        if let steps { workflow.steps = steps }
        if let trigger { workflow.trigger = trigger }
        if let enabled { workflow.enabled = enabled }
        workflow.updatedAt = Date()
        workflows[id] = workflow
        save(workflow)
        return true
    }

    func addStep(workflowId: UUID, step: WorkflowStep) -> Bool {
        guard var workflow = workflows[workflowId] else { return false }
        workflow.steps.append(step)
        workflow.updatedAt = Date()
        workflows[workflowId] = workflow
        save(workflow)
        return true
    }

    func deleteWorkflow(id: UUID) {
        let name = workflows[id]?.name ?? "unknown"
        workflows.removeValue(forKey: id)
        let file = storageDir.appendingPathComponent("\(id.uuidString).json")
        do {
            try FileManager.default.removeItem(at: file)
            Log.tool.info("Deleted workflow: \(name)")
        } catch {
            Log.tool.error("Failed to delete workflow file: \(error.localizedDescription)")
        }
    }

    // MARK: - Execution

    /// Resolves template variables in a string. {{key}} is replaced with context[key].
    static func resolveTemplate(_ template: String, context: [String: String]) -> String {
        var result = template
        for (key, value) in context {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }

    /// Resolves all template variables in a step's input template.
    static func resolveInputs(_ inputTemplate: [String: String], context: [String: String]) -> [String: String] {
        var resolved: [String: String] = [:]
        for (key, value) in inputTemplate {
            resolved[key] = resolveTemplate(value, context: context)
        }
        return resolved
    }

    /// Executes a workflow sequentially, calling the provided tool executor for each step.
    /// Executor type: receives tool name and resolved string arguments, returns result.
    typealias ToolExecutor = @MainActor (String, [String: String]) async -> ToolResult

    func executeWorkflow(
        id: UUID,
        initialContext: [String: String] = [:],
        toolExecutor: ToolExecutor
    ) async -> WorkflowRun? {
        guard let workflow = workflows[id], workflow.enabled else { return nil }

        var run = WorkflowRun(workflowId: workflow.id, workflowName: workflow.name)
        run.context = initialContext

        Log.tool.info("Starting workflow: \(workflow.name) (\(workflow.steps.count) steps)")

        for step in workflow.steps {
            let resolvedInputs: [String: String] = Self.resolveInputs(step.inputTemplate, context: run.context)
            var stepResult = WorkflowStepResult(
                stepId: step.id,
                action: step.action,
                status: .running,
                output: "",
                startedAt: Date()
            )

            let toolResult = await toolExecutor(step.action, resolvedInputs)

            stepResult.completedAt = Date()
            if toolResult.isError {
                stepResult.status = .failed
                stepResult.output = toolResult.content
                run.stepResults.append(stepResult)
                Log.tool.warning("Workflow step failed: \(step.action) — \(toolResult.content)")
                break
            } else {
                stepResult.status = .completed
                stepResult.output = toolResult.content
                if !step.outputKey.isEmpty {
                    run.context[step.outputKey] = toolResult.content
                }
                run.stepResults.append(stepResult)
                Log.tool.debug("Workflow step completed: \(step.action)")
            }
        }

        let allCompleted = run.stepResults.allSatisfy { $0.status == .completed }
        run.success = allCompleted && run.stepResults.count == workflow.steps.count
        run.completedAt = Date()

        runs.append(run)
        // Keep only last 50 runs
        if runs.count > 50 { runs.removeFirst(runs.count - 50) }

        Log.tool.info("Workflow \(workflow.name) \(run.success ? "succeeded" : "failed") (\(run.stepResults.count)/\(workflow.steps.count) steps)")
        return run
    }

    // MARK: - Persistence

    private func save(_ workflow: Workflow) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(workflow)
            let file = storageDir.appendingPathComponent("\(workflow.id.uuidString).json")
            try data.write(to: file)
        } catch {
            Log.tool.error("Failed to save workflow: \(error.localizedDescription)")
        }
    }

    private func loadAll() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let files = try? FileManager.default.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: file)
                let workflow = try decoder.decode(Workflow.self, from: data)
                workflows[workflow.id] = workflow
            } catch {
                Log.tool.warning("Failed to load workflow from \(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}
