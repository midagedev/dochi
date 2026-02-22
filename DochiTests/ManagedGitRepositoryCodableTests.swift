import XCTest
@testable import Dochi

final class ManagedGitRepositoryCodableTests: XCTestCase {

    func testDecodingLegacyRepositoryWithoutTrustDomainDefaultsToUnknown() throws {
        let legacyJSON = """
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "name": "repo-a",
          "rootPath": "/tmp/repo-a",
          "source": "attached",
          "originURL": "git@github.com:midagedev/repo-a.git",
          "defaultBranch": "main",
          "isArchived": false,
          "createdAt": "2026-02-22T00:00:00Z",
          "updatedAt": "2026-02-22T00:00:00Z"
        }
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ManagedGitRepository.self, from: data)

        XCTAssertEqual(decoded.name, "repo-a")
        XCTAssertEqual(decoded.trustDomain, .unknown)
    }
}
