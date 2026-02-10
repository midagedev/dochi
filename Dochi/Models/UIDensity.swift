import Foundation

enum UIDensity: String, CaseIterable, Identifiable, Hashable {
    case standard
    case compact

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .standard: return "기본"
        case .compact: return "컴팩트"
        }
    }
}
