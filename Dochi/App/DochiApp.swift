import AgentRuntimeCore
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

/// Dochi — a voice + character front-end with a native Swift agent runtime and
/// an optional remote Hermes backend.
///
/// The app keeps only what it does best: Korean speech recognition, local/cloud
/// TTS, and a VRM avatar. Reasoning, governed memory, and tools run in-process by
/// default through AgentRuntimeKit.
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
        let approvalBroker = AgentToolApprovalBroker()
        let nativeBackend: AgentBackendProtocol
        do {
            nativeBackend = try DochiNativeAgentAssembly.make(
                settings: settings,
                approvalBroker: approvalBroker
            )
        } catch {
            Log.app.error("Native agent assembly failed: \(error.localizedDescription)")
            nativeBackend = UnavailableAgentBackend(error: error)
        }
        let hermesBridge = HermesAgentBridge(
            host: settings.hermesBridgeHost,
            port: settings.hermesBridgePort
        )
        let agentBackend = AgentBackendRouter(
            selectedKind: settings.currentAgentBackendKind,
            native: nativeBackend,
            hermes: hermesBridge
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
            agentBackend: agentBackend,
            approvalBroker: approvalBroker
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
