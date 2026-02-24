import Foundation

enum InteractionState: Sendable, Equatable {
    case idle
    case listening
    case processing
    case speaking
}
