import AppKit
import SwiftUI
import ClipboardEngine

/// Application delegate responsible for:
///   • Creating the menu bar status item + popover
///   • Hiding the Dock icon (agent app)
///   • Starting/stopping clipboard monitoring
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a menu-bar-only app (no Dock icon).
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupPopover()
        setupEventMonitor()
        appState.startMonitoring()

        // Give AppState callbacks for dismiss and settings
        appState.onDismiss = { [weak self] in
            self?.closePopover()
        }
        appState.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stopMonitoring()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Status Item (Menu Bar Icon)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: "Magpie"
            )
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 520)
        popover.behavior = .transient  // Dismiss when clicking outside
        popover.animates = true

        let contentView = ClipboardHistoryView()
            .environmentObject(appState)
            .environmentObject(appState.exclusionManager)

        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        appState.loadClips()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Ensure the popover window becomes key so the search bar gets focus
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    // MARK: - Click-Outside Monitor

    private func setupEventMonitor() {
        // Close the popover when clicking outside of it
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            if let self = self, self.popover.isShown {
                self.closePopover()
            }
        }
    }

    // MARK: - Settings Window

    func openSettings() {
        closePopover()

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = PreferencesView()
            .environmentObject(appState)
            .environmentObject(appState.exclusionManager)

        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Magpie Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 420, height: 420))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
}
