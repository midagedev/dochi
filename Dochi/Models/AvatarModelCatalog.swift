import Foundation

struct AvatarModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let originalName: String
    let creator: String
    let previewAssetName: String
    let license: String
    let sourceURL: String
}

enum AvatarModelCatalog {
    static let models: [AvatarModelOption] = [
        AvatarModelOption(
            id: "chubby_tubby_cat",
            displayName: "통통 고양이",
            originalName: "Chubby Tubby Cat",
            creator: "ToxSam",
            previewAssetName: "Avatar_chubby_tubby_cat",
            license: "CC0",
            sourceURL: "https://gateway.pinata.cloud/ipfs/QmY4NQRArQaEWPgyzyTuCSvyAnBUhtsshFKPjJHbbzVKLL/ChubbyTubbyCat.vrm"
        ),
        AvatarModelOption(
            id: "dogo_burger",
            displayName: "햄버거 강아지",
            originalName: "Dogo Burger",
            creator: "Polygonal Mind",
            previewAssetName: "Avatar_dogo_burger",
            license: "CC0",
            sourceURL: "https://arweave.net/qKrAwFf60cT1348kvQc7S5Nzn3fO0aNvJ8ybMx5Lu04"
        ),
        AvatarModelOption(
            id: "cute_saurus",
            displayName: "포근 공룡",
            originalName: "Cute Saurus",
            creator: "Polygonal Mind",
            previewAssetName: "Avatar_cute_saurus",
            license: "CC0",
            sourceURL: "https://arweave.net/1-EJ5GXIlQ1ohw6GMsMnEzyK7IHhI8YDPYsjMvo_xhQ"
        ),
        AvatarModelOption(
            id: "weird_cat",
            displayName: "엉뚱 고양이",
            originalName: "Weird Cat",
            creator: "Polygonal Mind",
            previewAssetName: "Avatar_weird_cat",
            license: "CC0",
            sourceURL: "https://arweave.net/pPaWwgWt8Gu7hJyHo_wG45lxPVV8ka8zBJJKSQD8Ngs"
        ),
        AvatarModelOption(
            id: "cute_moth",
            displayName: "솜사탕 나방",
            originalName: "Cute Moth",
            creator: "Polygonal Mind",
            previewAssetName: "Avatar_cute_moth",
            license: "CC0",
            sourceURL: "https://arweave.net/LWj4C9ClGs0ChP7oHDEEWPbGTo0HAWNMjhIRlyMkRHg"
        ),
        AvatarModelOption(
            id: "dino_kid",
            displayName: "꼬마 공룡",
            originalName: "DinoKid",
            creator: "Polygonal Mind",
            previewAssetName: "Avatar_dino_kid",
            license: "CC0",
            sourceURL: "https://raw.githubusercontent.com/PolygonalMind/100Avatars/master/100Avatars_045/100Avatars_045_DinoKid.vrm"
        ),
        AvatarModelOption(
            id: "megan_the_fox",
            displayName: "메건 여우",
            originalName: "Megan The Fox",
            creator: "Polygonal Mind",
            previewAssetName: "Avatar_megan_the_fox",
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
