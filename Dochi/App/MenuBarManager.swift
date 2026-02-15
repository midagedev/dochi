import AppKit
import SwiftUI

/// NSStatusItem + NSPopover 관리, 글로벌 핫키 등록 (H-1)
@MainActor
final class MenuBarManager {

    // MARK: - State

    enum StatusIconState {
        case normal
        case processing
        case error
    }

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var eventMonitor: Any?

    private let settings: AppSettings
    private weak var viewModel: DochiViewModel?

    private(set) var iconState: StatusIconState = .normal

    // MARK: - Init

    init(settings: AppSettings, viewModel: DochiViewModel) {
        self.settings = settings
        self.viewModel = viewModel
    }

    // MARK: - Setup / Teardown

    func setup() {
        guard settings.menuBarEnabled else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "bubble.left.fill", accessibilityDescription: "도치 퀵 액세스")
            image?.isTemplate = true
            let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            button.image = image?.withSymbolConfiguration(config)
            button.action = #selector(AppDelegate.toggleMenuBarPopover)
            button.target = nil // Sends up responder chain to AppDelegate
        }
        self.statusItem = item

        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentSize = NSSize(width: 380, height: 480)
        pop.animates = true

        if let viewModel {
            let popoverView = MenuBarPopoverView(viewModel: viewModel, onClose: { [weak self] in
                self?.closePopover()
            }, onOpenMainApp: { [weak self] in
                self?.openMainApp()
            })
            pop.contentViewController = NSHostingController(rootView: popoverView)
        }
        self.popover = pop

        registerGlobalShortcut()

        Log.app.info("MenuBarManager: setup completed")
    }

    func teardown() {
        unregisterGlobalShortcut()

        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        popover?.close()
        popover = nil

        Log.app.info("MenuBarManager: teardown completed")
    }

    // MARK: - Popover Control

    func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Bring popover window to front
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func closePopover() {
        popover?.performClose(nil)
    }

    var isPopoverShown: Bool {
        popover?.isShown ?? false
    }

    // MARK: - Icon State

    func updateIconState(_ state: StatusIconState) {
        iconState = state
        guard let button = statusItem?.button else { return }

        let baseImage = NSImage(systemSymbolName: "bubble.left.fill", accessibilityDescription: "도치 퀵 액세스")
        baseImage?.isTemplate = true
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let configuredImage = baseImage?.withSymbolConfiguration(config)

        switch state {
        case .normal:
            button.image = configuredImage
        case .processing:
            // Use the template image with a blue tint via compositing
            let tintConfig = NSImage.SymbolConfiguration(paletteColors: [.systemBlue])
            button.image = configuredImage?.withSymbolConfiguration(tintConfig)
        case .error:
            let tintConfig = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            button.image = configuredImage?.withSymbolConfiguration(tintConfig)
        }
    }

    // MARK: - Open Main App

    func openMainApp() {
        closePopover()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.className.contains("AppKit") == false && $0.isVisible == false }?.makeKeyAndOrderFront(nil)
        // Fallback: bring any main window forward
        if let mainWindow = NSApp.windows.first(where: { $0.className != "NSStatusBarWindow" && $0.className != "_NSPopoverWindow" }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Global Shortcut (Cmd+Shift+D)

    private func registerGlobalShortcut() {
        guard settings.menuBarGlobalShortcutEnabled else { return }

        // Global monitor (when app is not in focus)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleShortcutEvent(event)
        }

        // Local monitor (when app is in focus)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleShortcutEvent(event) == true {
                return nil // consume the event
            }
            return event
        }

        Log.app.info("MenuBarManager: global shortcut registered (Cmd+Shift+D)")
    }

    private func unregisterGlobalShortcut() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        Log.app.info("MenuBarManager: global shortcut unregistered")
    }

    @discardableResult
    private func handleShortcutEvent(_ event: NSEvent) -> Bool {
        // Cmd+Shift+D
        guard event.modifierFlags.contains([.command, .shift]),
              event.keyCode == 2 else { // 2 = 'D' key
            return false
        }

        Task { @MainActor in
            self.togglePopover()
        }
        return true
    }

    // MARK: - Settings Observation

    func handleSettingsChange() {
        if settings.menuBarEnabled {
            if statusItem == nil {
                setup()
            }
        } else {
            teardown()
        }

        // Re-register or unregister global shortcut
        unregisterGlobalShortcut()
        if settings.menuBarEnabled {
            registerGlobalShortcut()
        }
    }
}
