import XCTest
import VRMKit
import VRMRealityKit
@testable import Dochi

final class AvatarModelCatalogTests: XCTestCase {
    func testDefaultModelExistsInCatalog() {
        XCTAssertFalse(AvatarModelCatalog.models.isEmpty)
        XCTAssertTrue(AvatarModelCatalog.models.contains { $0.id == AvatarModelCatalog.defaultModelID })
    }

    func testModelIDsAndPreviewAssetsAreUnique() {
        let ids = AvatarModelCatalog.models.map(\.id)
        let previews = AvatarModelCatalog.models.map(\.previewAssetName)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(previews).count, previews.count)
    }

    func testCatalogContainsOnlyCC0ModelsWithSecureSources() {
        for model in AvatarModelCatalog.models {
            XCTAssertEqual(model.license, "CC0", model.id)
            XCTAssertEqual(URL(string: model.sourceURL)?.scheme, "https", model.id)
        }
    }

    func testNormalizedModelIDFallsBackForInvalidValues() {
        XCTAssertEqual(AvatarModelCatalog.normalizedModelID(nil), AvatarModelCatalog.defaultModelID)
        XCTAssertEqual(AvatarModelCatalog.normalizedModelID(""), AvatarModelCatalog.defaultModelID)
        XCTAssertEqual(AvatarModelCatalog.normalizedModelID("unknown-model"), AvatarModelCatalog.defaultModelID)
    }

    func testBundledModelsAreLegacyVRMWithRedistributableMetadata() throws {
        for model in AvatarModelCatalog.models {
            let url = try XCTUnwrap(
                Bundle.main.url(forResource: model.id, withExtension: "vrm"),
                "Missing bundled VRM for \(model.id)"
            )
            let document = try legacyVRMDocument(at: url)
            let vrm = try XCTUnwrap((document["extensions"] as? [String: Any])?["VRM"] as? [String: Any])
            let meta = try XCTUnwrap(vrm["meta"] as? [String: Any])

            XCTAssertEqual(vrm["specVersion"] as? String, "0.0", model.id)
            XCTAssertEqual(meta["licenseName"] as? String, "CC0", model.id)
            XCTAssertEqual(meta["allowedUserName"] as? String, "Everyone", model.id)
            XCTAssertEqual(meta["commercialUssageName"] as? String, "Allow", model.id)

            let master = try XCTUnwrap(vrm["blendShapeMaster"] as? [String: Any])
            let groups = try XCTUnwrap(master["blendShapeGroups"] as? [[String: Any]])
            let presets = Set(groups.compactMap { $0["presetName"] as? String })
            XCTAssertTrue(presets.contains("a"), "\(model.id) needs the A lip-sync preset")
            XCTAssertTrue(presets.contains("blink"), "\(model.id) needs the blink preset")
        }
    }

    @available(macOS 15.0, *)
    @MainActor
    func testBundledModelsCreateRealityKitEntities() throws {
        for model in AvatarModelCatalog.models {
            let vrm = try VRMLoader().load(named: "\(model.id).vrm")
            let entity = try VRMEntityLoader(vrm: vrm).loadEntity()
            XCTAssertNotNil(entity.humanoid.node(for: .head), "\(model.id) needs a head bone")
        }
    }

    private func legacyVRMDocument(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard data.count >= 20, String(data: data.prefix(4), encoding: .ascii) == "glTF" else {
            throw VRMTestError.invalidGLB
        }

        var offset = 12
        while offset + 8 <= data.count {
            let chunkLength = Int(readUInt32LE(data, at: offset))
            let chunkType = readUInt32LE(data, at: offset + 4)
            let chunkStart = offset + 8
            let chunkEnd = chunkStart + chunkLength
            guard chunkEnd <= data.count else { throw VRMTestError.invalidGLB }

            if chunkType == 0x4E4F534A {
                var jsonData = data.subdata(in: chunkStart..<chunkEnd)
                while jsonData.last == 0 || jsonData.last == 0x20 {
                    jsonData.removeLast()
                }
                return try XCTUnwrap(JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
            }
            offset = chunkEnd
        }
        throw VRMTestError.missingJSONChunk
    }

    private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        (0..<4).reduce(into: UInt32.zero) { value, index in
            value |= UInt32(data[offset + index]) << UInt32(index * 8)
        }
    }
}

private enum VRMTestError: Error {
    case invalidGLB
    case missingJSONChunk
}
