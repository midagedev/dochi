import SwiftUI

@main
struct DochiMobileApp: App {
    @StateObject private var viewModel = MobileChatViewModel()

    var body: some Scene {
        WindowGroup {
            MobileContentView()
                .environmentObject(viewModel)
        }
    }
}
