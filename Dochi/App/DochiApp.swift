import SwiftUI

@main
struct DochiApp: App {
    @State private var viewModel = DochiViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }

        Settings {
            SettingsView()
        }
    }
}
