import Foundation

enum ProcessingSubState: Sendable {
    case streaming
    case toolCalling
    case toolError
    case complete
}
