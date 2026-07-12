import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Task { @MainActor [weak self] in self?.ensurePrimaryWindowVisible() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            Task { @MainActor in self?.ensurePrimaryWindowVisible() }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.ensurePrimaryWindowVisible() }
    }

    @MainActor
    private func ensurePrimaryWindowVisible() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = Self.findPrimaryWindow() {
            window.makeKeyAndOrderFront(nil)
            return
        }
        for action in ["newWindowForTab:", "newWindow:", "newDocument:"] {
            _ = NSApp.sendAction(Selector(action), to: nil, from: nil)
        }
        Self.findPrimaryWindow()?.makeKeyAndOrderFront(nil)
    }

    @MainActor
    private static func findPrimaryWindow() -> NSWindow? {
        NSApp.windows.first(where: { $0.className != "NSStatusBarWindow" && $0.className != "_NSPopoverWindow" })
    }
}

/// Dochi — a voice + 3D-character front-end for a Hermes Agent backend.
///
/// The app keeps only what it does best: Korean speech recognition, local/cloud
/// TTS, and a VRM avatar. Reasoning, memory, and tools come from Hermes through
/// ``HermesAgentBridge`` (see `HermesBridge/` for the Python side).
@main
struct DochiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel: DochiViewModel
    private let settings: AppSettings
    private let keychainService: KeychainService
    private let ttsService: TTSRouter
    private let ttsModelDownloadManager: ModelDownloadManager

    init() {
        let settings = AppSettings()
        let keychainService = KeychainService()
        let speechService = SpeechService()
        let ttsService = TTSRouter(settings: settings, keychainService: keychainService)
        let ttsModelDownloadManager = ModelDownloadManager()
        let soundService = SoundService()
        let conversationService = ConversationService()
        let hermesBridge = HermesAgentBridge(
            host: settings.hermesBridgeHost,
            port: settings.hermesBridgePort
        )

        self.settings = settings
        self.keychainService = keychainService
        self.ttsService = ttsService
        self.ttsModelDownloadManager = ttsModelDownloadManager

        let viewModel = DochiViewModel(
            settings: settings,
            speechService: speechService,
            ttsService: ttsService,
            soundService: soundService,
            conversationService: conversationService,
            hermesBridge: hermesBridge
        )
        _viewModel = State(initialValue: viewModel)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onAppear {
                    viewModel.loadConversations()
                    viewModel.connectBackend()
                    if viewModel.isVoiceMode {
                        viewModel.prepareTTSEngine()
                        viewModel.startBackgroundWakeWordListener()
                    }
                }
        }

        Settings {
            SettingsView(
                settings: settings,
                keychainService: keychainService,
                ttsService: ttsService,
                downloadManager: ttsModelDownloadManager,
                viewModel: viewModel
            )
        }
    }
}
