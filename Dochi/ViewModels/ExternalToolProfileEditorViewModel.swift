import Foundation

@MainActor
@Observable
final class ExternalToolProfileEditorViewModel {
    private let manager: ExternalToolSessionManagerProtocol

    var recommendedRoots: [GitRepositoryInsight] = []
    var isLoadingRecommendations = false
    var hasLoadedRecommendations = false

    init(manager: ExternalToolSessionManagerProtocol) {
        self.manager = manager
    }

    func refreshRecommendedRoots(limit: Int = 12) async {
        isLoadingRecommendations = true
        defer {
            isLoadingRecommendations = false
            hasLoadedRecommendations = true
        }

        let normalizedLimit = max(1, min(30, limit))
        recommendedRoots = await manager.discoverGitRepositoryInsights(
            searchPaths: nil,
            limit: normalizedLimit
        )
    }

    func applyRecommendedRoot(_ root: GitRepositoryInsight) -> String {
        root.path
    }
}
