import XCTest
@testable import Dochi

final class AvatarModelCatalogTests: XCTestCase {

    func testDefaultModelExistsInCatalog() {
        XCTAssertFalse(AvatarModelCatalog.models.isEmpty)
        XCTAssertTrue(
            AvatarModelCatalog.models.contains { $0.id == AvatarModelCatalog.defaultModelID },
            "defaultModelID must exist in models"
        )
    }

    func testModelIDsAreUnique() {
        let ids = AvatarModelCatalog.models.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testNormalizedModelIDFallsBackForInvalidValues() {
        XCTAssertEqual(AvatarModelCatalog.normalizedModelID(nil), AvatarModelCatalog.defaultModelID)
        XCTAssertEqual(AvatarModelCatalog.normalizedModelID(""), AvatarModelCatalog.defaultModelID)
        XCTAssertEqual(AvatarModelCatalog.normalizedModelID("unknown-model"), AvatarModelCatalog.defaultModelID)
    }
}
