import XCTest
@testable import Dochi

// MARK: - AgentTemplate Model Tests

final class AgentTemplateTests: XCTestCase {

    func testBuiltInTemplatesCount() {
        XCTAssertEqual(AgentTemplate.builtInTemplates.count, 5, "Should have 5 built-in templates")
    }

    func testBuiltInTemplatesAreBuiltIn() {
        for template in AgentTemplate.builtInTemplates {
            XCTAssertTrue(template.isBuiltIn, "\(template.name) should be built-in")
        }
    }

    func testBlankTemplateIsBuiltIn() {
        XCTAssertTrue(AgentTemplate.blank.isBuiltIn)
        XCTAssertEqual(AgentTemplate.blank.id, "blank")
    }

    func testBuiltInTemplatesHaveUniqueIds() {
        var allTemplates = AgentTemplate.builtInTemplates
        allTemplates.append(.blank)
        let ids = allTemplates.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Template IDs should be unique")
    }

    func testBuiltInTemplatesHaveRequiredFields() {
        var allTemplates = AgentTemplate.builtInTemplates
        allTemplates.append(.blank)
        for template in allTemplates {
            XCTAssertFalse(template.id.isEmpty, "\(template.name) id should not be empty")
            XCTAssertFalse(template.name.isEmpty, "\(template.id) name should not be empty")
            XCTAssertFalse(template.icon.isEmpty, "\(template.id) icon should not be empty")
            XCTAssertFalse(template.description.isEmpty, "\(template.id) description should not be empty")
            XCTAssertFalse(template.accentColor.isEmpty, "\(template.id) accentColor should not be empty")
        }
    }

    func testCodingAssistantTemplate() {
        let template = AgentTemplate.codingAssistant
        XCTAssertEqual(template.id, "coding-assistant")
        XCTAssertTrue(template.suggestedPermissions.contains("restricted"))
        XCTAssertFalse(template.suggestedPersona.isEmpty)
        XCTAssertFalse(template.suggestedTools.isEmpty)
    }

    func testResearcherTemplate() {
        let template = AgentTemplate.researcher
        XCTAssertEqual(template.id, "researcher")
        XCTAssertTrue(template.suggestedPermissions.contains("sensitive"))
        XCTAssertFalse(template.suggestedPermissions.contains("restricted"))
    }

    func testSchedulerTemplate() {
        let template = AgentTemplate.scheduler
        XCTAssertEqual(template.id, "scheduler")
        XCTAssertTrue(template.suggestedTools.contains("calendar.list"))
    }

    func testWriterTemplate() {
        let template = AgentTemplate.writer
        XCTAssertEqual(template.id, "writer")
        XCTAssertEqual(template.suggestedPermissions, ["safe"])
    }

    func testKanbanManagerTemplate() {
        let template = AgentTemplate.kanbanManager
        XCTAssertEqual(template.id, "kanban-manager")
        XCTAssertTrue(template.suggestedTools.contains("kanban.list"))
    }

    func testBlankTemplate() {
        let template = AgentTemplate.blank
        XCTAssertEqual(template.id, "blank")
        XCTAssertTrue(template.suggestedPersona.isEmpty)
        XCTAssertEqual(template.suggestedPermissions, ["safe"])
        XCTAssertTrue(template.suggestedTools.isEmpty)
    }

    func testPersonaChips() {
        let coding = AgentTemplate.codingAssistant
        XCTAssertEqual(coding.personaChips.count, 3)

        let blank = AgentTemplate.blank
        XCTAssertEqual(blank.personaChips.count, 3)
    }

    // MARK: - Codable Roundtrip

    func testCodableRoundtrip() throws {
        let template = AgentTemplate(
            id: "test-custom",
            name: "테스트 템플릿",
            icon: "star",
            description: "테스트",
            detailedDescription: "상세 설명",
            suggestedPersona: "당신은 테스트 에이전트입니다.",
            suggestedModel: "gpt-4o",
            suggestedPermissions: ["safe", "sensitive"],
            suggestedTools: ["web.search"],
            isBuiltIn: false,
            accentColor: "purple"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(template)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AgentTemplate.self, from: data)

        XCTAssertEqual(decoded.id, template.id)
        XCTAssertEqual(decoded.name, template.name)
        XCTAssertEqual(decoded.icon, template.icon)
        XCTAssertEqual(decoded.description, template.description)
        XCTAssertEqual(decoded.detailedDescription, template.detailedDescription)
        XCTAssertEqual(decoded.suggestedPersona, template.suggestedPersona)
        XCTAssertEqual(decoded.suggestedModel, template.suggestedModel)
        XCTAssertEqual(decoded.suggestedPermissions, template.suggestedPermissions)
        XCTAssertEqual(decoded.suggestedTools, template.suggestedTools)
        XCTAssertEqual(decoded.isBuiltIn, template.isBuiltIn)
        XCTAssertEqual(decoded.accentColor, template.accentColor)
    }

    func testCodableRoundtripNilModel() throws {
        let template = AgentTemplate.blank

        let encoder = JSONEncoder()
        let data = try encoder.encode(template)
        let decoded = try JSONDecoder().decode(AgentTemplate.self, from: data)

        XCTAssertNil(decoded.suggestedModel)
        XCTAssertEqual(decoded.id, "blank")
    }

    func testCodableArrayRoundtrip() throws {
        let templates = AgentTemplate.builtInTemplates

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(templates)

        let decoded = try JSONDecoder().decode([AgentTemplate].self, from: data)
        XCTAssertEqual(decoded.count, 5)
        XCTAssertEqual(decoded.map(\.id), templates.map(\.id))
    }

    // MARK: - Equatable

    func testEquatable() {
        let a = AgentTemplate.codingAssistant
        let b = AgentTemplate.codingAssistant
        XCTAssertEqual(a, b)

        XCTAssertNotEqual(AgentTemplate.codingAssistant, AgentTemplate.researcher)
    }
}

// MARK: - ContextService Custom Templates Tests

@MainActor
final class ContextServiceTemplateTests: XCTestCase {
    private var service: ContextService!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DochiTests-Templates-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        service = ContextService(baseURL: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testLoadCustomTemplatesEmpty() {
        let templates = service.loadCustomTemplates()
        XCTAssertTrue(templates.isEmpty, "Should return empty when no file exists")
    }

    func testSaveAndLoadCustomTemplates() {
        let template = AgentTemplate(
            id: "custom-1",
            name: "내 템플릿",
            icon: "star",
            description: "커스텀 템플릿",
            detailedDescription: "상세",
            suggestedPersona: "페르소나",
            suggestedModel: "gpt-4o",
            suggestedPermissions: ["safe"],
            suggestedTools: [],
            isBuiltIn: false,
            accentColor: "blue"
        )

        service.saveCustomTemplates([template])

        let loaded = service.loadCustomTemplates()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, "custom-1")
        XCTAssertEqual(loaded.first?.name, "내 템플릿")
    }

    func testSaveMultipleTemplates() {
        let t1 = AgentTemplate(
            id: "custom-1", name: "첫 번째", icon: "1.circle", description: "1",
            detailedDescription: "", suggestedPersona: "", suggestedModel: nil,
            suggestedPermissions: ["safe"], suggestedTools: [], isBuiltIn: false, accentColor: "blue"
        )
        let t2 = AgentTemplate(
            id: "custom-2", name: "두 번째", icon: "2.circle", description: "2",
            detailedDescription: "", suggestedPersona: "", suggestedModel: nil,
            suggestedPermissions: ["safe", "sensitive"], suggestedTools: [], isBuiltIn: false, accentColor: "green"
        )

        service.saveCustomTemplates([t1, t2])

        let loaded = service.loadCustomTemplates()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.map(\.id).sorted(), ["custom-1", "custom-2"])
    }

    func testOverwriteTemplates() {
        let t1 = AgentTemplate(
            id: "custom-1", name: "첫 번째", icon: "1.circle", description: "1",
            detailedDescription: "", suggestedPersona: "", suggestedModel: nil,
            suggestedPermissions: ["safe"], suggestedTools: [], isBuiltIn: false, accentColor: "blue"
        )

        service.saveCustomTemplates([t1])
        XCTAssertEqual(service.loadCustomTemplates().count, 1)

        // Overwrite with empty
        service.saveCustomTemplates([])
        XCTAssertEqual(service.loadCustomTemplates().count, 0)
    }
}

// MARK: - MockContextService Custom Templates Tests

@MainActor
final class MockContextServiceTemplateTests: XCTestCase {

    func testMockLoadAndSaveTemplates() {
        let mock = MockContextService()

        // Initially empty
        XCTAssertTrue(mock.loadCustomTemplates().isEmpty)

        // Save templates
        let template = AgentTemplate(
            id: "mock-1", name: "Mock 템플릿", icon: "star", description: "test",
            detailedDescription: "", suggestedPersona: "", suggestedModel: nil,
            suggestedPermissions: ["safe"], suggestedTools: [], isBuiltIn: false, accentColor: "gray"
        )
        mock.saveCustomTemplates([template])

        // Load back
        let loaded = mock.loadCustomTemplates()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, "mock-1")
    }
}
