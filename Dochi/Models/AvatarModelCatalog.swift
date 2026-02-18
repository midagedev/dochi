import Foundation

struct AvatarModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let license: String
    let sourceURL: String
}

enum AvatarModelCatalog {
    static let models: [AvatarModelOption] = [
        AvatarModelOption(
            id: "chubby_tubby_cat",
            displayName: "Chubby Tubby Cat (고양이)",
            license: "CC0",
            sourceURL: "https://gateway.pinata.cloud/ipfs/QmY4NQRArQaEWPgyzyTuCSvyAnBUhtsshFKPjJHbbzVKLL/ChubbyTubbyCat.vrm"
        ),
        AvatarModelOption(
            id: "paws_chestnut",
            displayName: "Paws Chestnut (곰)",
            license: "CC0",
            sourceURL: "https://gateway.pinata.cloud/ipfs/QmSpb8jZRtwDhpp7zjpfvU47GZyapmh8GvQApmzTxFcaLz/Avatar02_Neutral.vrm"
        ),
        AvatarModelOption(
            id: "merry_yulelog",
            displayName: "Merry Yulelog (여우)",
            license: "CC0",
            sourceURL: "https://gateway.pinata.cloud/ipfs/QmSpb8jZRtwDhpp7zjpfvU47GZyapmh8GvQApmzTxFcaLz/Avatar06_Neutral.vrm"
        ),
        AvatarModelOption(
            id: "thumper_cranberry",
            displayName: "Thumper Cranberry (토끼)",
            license: "CC0",
            sourceURL: "https://gateway.pinata.cloud/ipfs/QmSpb8jZRtwDhpp7zjpfvU47GZyapmh8GvQApmzTxFcaLz/Avatar09_Neutral.vrm"
        ),
        AvatarModelOption(
            id: "megan_the_fox",
            displayName: "MeganTheFox (애니풍)",
            license: "CC0",
            sourceURL: "https://arweave.net/up4WzT0YJfXv9woGseCIQnBSq3eH8KWASJJbNtuvEWY"
        ),
    ]

    static let defaultModelID = models.first?.id ?? "chubby_tubby_cat"

    static func model(for id: String) -> AvatarModelOption? {
        models.first { $0.id == id }
    }

    static func normalizedModelID(_ id: String?) -> String {
        guard let id, !id.isEmpty, model(for: id) != nil else {
            return defaultModelID
        }
        return id
    }
}
