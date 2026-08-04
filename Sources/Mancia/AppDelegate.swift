import AppKit
import SwiftUI

/// Wires together the status item, global hotkey, and edit coordinator, and
/// owns the settings window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private lazy var provider = CopilotCLIProvider(settings: settings)
    private var coordinator: EditCoordinator?
    private var statusBar: StatusBarController?
    private var hotkey: HotkeyManager?
    private var selectionMonitor: SelectionMonitor?
    private var commandWindow: NSWindow?
    private var commandTargetApp: NSRunningApplication?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = EditCoordinator(provider: provider, settings: settings)
        coordinator.onOpenSettings = { [weak self] in self?.showSettings() }
        self.coordinator = coordinator

        let statusBar = StatusBarController(provider: provider)
        statusBar.onEdit = { [weak self] in self?.coordinator?.start() }
        statusBar.onSettings = { [weak self] in self?.showSettings() }
        statusBar.onAbout = { [weak self] in self?.showAbout() }
        self.statusBar = statusBar
        statusBar.setIconVisible(!settings.hideMenuBarIcon)

        self.hotkey = HotkeyManager { [weak self] in self?.coordinator?.start() }

        let selectionMonitor = SelectionMonitor(
            isEnabled: { [weak self] in self?.settings.showRibbonOnTextSelection ?? false },
            onSelection: { [weak self] in
                guard let coordinator = self?.coordinator, !coordinator.isSessionActive else { return }
                coordinator.start()
            }
        )
        selectionMonitor.start()
        self.selectionMonitor = selectionMonitor
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        showCommandWindow()
        return true
    }

    private func showCommandWindow() {
        commandTargetApp = NSWorkspace.shared.frontmostApplication.flatMap { app in
            app.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : app
        }
        NSApp.activate()
        if let commandWindow {
            commandWindow.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: StartupMenuView(
            provider: provider,
            onEdit: { [weak self] in self?.startFromCommandWindow() },
            onSettings: { [weak self] in
                self?.commandWindow?.close()
                self?.showSettings()
            },
            onAbout: { [weak self] in
                self?.commandWindow?.close()
                self?.showAbout()
            }
        ))
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "Mancia"
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.center()
        commandWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func startFromCommandWindow() {
        commandWindow?.close()
        let target = commandTargetApp
        Task { @MainActor [weak self] in
            target?.activate()
            try? await Task.sleep(for: .milliseconds(120))
            self?.coordinator?.start()
        }
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView(
            settings: settings,
            provider: provider,
            onMenuBarVisibilityChange: { [weak self] visible in
                self?.statusBar?.setIconVisible(visible)
            }
        ))
        // Create the window with its final style mask up front: reassigning
        // styleMask after NSWindow(contentViewController:) collapses the
        // content area to zero height (the "empty settings window" bug).
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mancia Settings"
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.center()
        // Opening Settings activates the app and takes key status away from
        // the floating panel; without this, an open edit session stops
        // responding to Esc and typing after Settings closes.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.coordinator?.refocusPanel() }
        }
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func showAbout() {
        AboutPanel.present()
    }
}
