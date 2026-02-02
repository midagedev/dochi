import SwiftUI

@main
struct DochiApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var viewModel: DochiViewModel

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _viewModel = StateObject(wrappedValue: DochiViewModel(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 650)
    }
}
