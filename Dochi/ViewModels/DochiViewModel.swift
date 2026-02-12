import Foundation
import SwiftUI

@MainActor
@Observable
final class DochiViewModel {
    // MARK: - State
    var interactionState: InteractionState = .idle
    var sessionState: SessionState = .inactive
    var processingSubState: ProcessingSubState?

    // MARK: - Data
    var currentConversation: Conversation?
    var streamingText: String = ""
    var inputText: String = ""
    var errorMessage: String?

    // MARK: - Services (to be injected in Phase 1)

    init() {
        Log.app.info("DochiViewModel initialized")
    }

    // MARK: - Actions

    func sendMessage() {
        // TODO: Phase 1
    }

    func cancelRequest() {
        // TODO: Phase 1
    }
}
