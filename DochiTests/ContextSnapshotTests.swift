import XCTest
@testable import Dochi

// MARK: - ContextSnapshot Model Tests

/// Tests for ContextSnapshot, ContextLayers, ContextLayer model types.
/// Builder/store/boundary tests are in ContextSnapshotBuilderTests.swift.
final class ContextSnapshotModelTests: XCTestCase {

    func testContextLayerInit() {
        let layer = ContextLayer(name: .system, content: "Hello world")
        XCTAssertEqual(layer.name, .system)
        XCTAssertEqual(layer.content, "Hello world")
        XCTAssertFalse(layer.truncated)
        XCTAssertEqual(layer.originalCharCount, 11)
    }

    func testContextLayerTruncated() {
        let layer = ContextLayer(name: .workspace, content: "Short", truncated: true, originalCharCount: 10000)
        XCTAssertTrue(layer.truncated)
        XCTAssertEqual(layer.originalCharCount, 10000)
    }

    func testContextLayersOrdered() {
        let layers = ContextLayers(
            systemLayer: ContextLayer(name: .system, content: "A"),
            workspaceLayer: ContextLayer(name: .workspace, content: "B"),
            agentLayer: ContextLayer(name: .agent, content: "C"),
            personalLayer: ContextLayer(name: .personal, content: "D")
        )
        let names = layers.ordered.map(\.name)
        XCTAssertEqual(names, [.system, .workspace, .agent, .personal])
    }

    func testContextLayersCombinedText() {
        let layers = ContextLayers(
            systemLayer: ContextLayer(name: .system, content: "System"),
            workspaceLayer: ContextLayer(name: .workspace, content: ""),
            agentLayer: ContextLayer(name: .agent, content: "Agent"),
            personalLayer: ContextLayer(name: .personal, content: "Personal")
        )
        let combined = layers.combinedText
        XCTAssertTrue(combined.contains("System"))
        XCTAssertTrue(combined.contains("Agent"))
        XCTAssertTrue(combined.contains("Personal"))
        XCTAssertFalse(combined.contains("\n\n\n\n"))
    }

    func testContextLayersTotalCharCount() {
        let layers = ContextLayers(
            systemLayer: ContextLayer(name: .system, content: "12345"),
            workspaceLayer: ContextLayer(name: .workspace, content: "67890"),
            agentLayer: ContextLayer(name: .agent, content: "AB"),
            personalLayer: ContextLayer(name: .personal, content: "")
        )
        XCTAssertEqual(layers.totalCharCount, 12)
    }

    func testContextSnapshotRef() {
        let snapshot = ContextSnapshot(
            id: "test-id",
            workspaceId: "ws1",
            agentId: "agent1",
            userId: "user1",
            layers: ContextLayers(
                systemLayer: ContextLayer(name: .system, content: ""),
                workspaceLayer: ContextLayer(name: .workspace, content: ""),
                agentLayer: ContextLayer(name: .agent, content: ""),
                personalLayer: ContextLayer(name: .personal, content: "")
            ),
            tokenEstimate: 100,
            createdAt: Date(),
            sourceRevision: "abc123"
        )
        XCTAssertEqual(snapshot.snapshotRef, "test-id")
    }

    func testContextSnapshotCodable() throws {
        let original = ContextSnapshot(
            id: "snap-1",
            workspaceId: "ws-1",
            agentId: "도치",
            userId: "user-1",
            layers: ContextLayers(
                systemLayer: ContextLayer(name: .system, content: "시스템 프롬프트"),
                workspaceLayer: ContextLayer(name: .workspace, content: "워크스페이스 메모리"),
                agentLayer: ContextLayer(name: .agent, content: "에이전트 메모리"),
                personalLayer: ContextLayer(name: .personal, content: "개인 메모리")
            ),
            tokenEstimate: 500,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            sourceRevision: "rev123"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ContextSnapshot.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.workspaceId, original.workspaceId)
        XCTAssertEqual(decoded.agentId, original.agentId)
        XCTAssertEqual(decoded.userId, original.userId)
        XCTAssertEqual(decoded.tokenEstimate, original.tokenEstimate)
        XCTAssertEqual(decoded.sourceRevision, original.sourceRevision)
        XCTAssertEqual(decoded.layers.systemLayer.content, "시스템 프롬프트")
        XCTAssertEqual(decoded.layers.workspaceLayer.content, "워크스페이스 메모리")
        XCTAssertEqual(decoded.layers.agentLayer.content, "에이전트 메모리")
        XCTAssertEqual(decoded.layers.personalLayer.content, "개인 메모리")
    }

    func testContextSnapshotMetadataCodable() throws {
        let meta = ContextSnapshotMetadata(
            snapshotRef: "ref-1",
            workspaceId: "ws-1",
            agentId: "agent-1",
            userId: "user-1",
            tokenEstimate: 200,
            layerSummary: ["system": 100, "workspace": 50, "agent": 30, "personal": 20],
            createdAt: Date(timeIntervalSinceReferenceDate: 0)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(meta)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ContextSnapshotMetadata.self, from: data)

        XCTAssertEqual(decoded.snapshotRef, "ref-1")
        XCTAssertEqual(decoded.layerSummary["system"], 100)
    }

    func testContextLayerNameCodable() throws {
        let names: [ContextLayerName] = [.system, .workspace, .agent, .personal]
        for name in names {
            let data = try JSONEncoder().encode(name)
            let decoded = try JSONDecoder().decode(ContextLayerName.self, from: data)
            XCTAssertEqual(decoded, name)
        }
    }
}
