import SwiftUI

@main
@MainActor
struct DochiMobileApp: App {
    @State private var preferences: MobileAgentPreferences
    @State private var controller: MobileAgentController

    init() {
        let preferences = MobileAgentPreferences()
        _preferences = State(initialValue: preferences)
        _controller = State(initialValue: MobileAgentController(preferences: preferences))
    }

    var body: some Scene {
        WindowGroup {
            MobileChatView(controller: controller, preferences: preferences)
                .task { await controller.start() }
        }
    }
}
