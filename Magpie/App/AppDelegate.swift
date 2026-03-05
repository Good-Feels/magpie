import AppKit
import SwiftUI
import Combine
import ClipboardEngine
import KeyboardShortcuts

/// Application delegate responsible for:
///   • Creating the menu bar status item + popover
///   • Hiding the Dock icon (agent app)
///   • Starting/stopping clipboard monitoring
///   • Showing first-launch onboarding
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private let analytics = AnalyticsService.shared

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a menu-bar-only app (no Dock icon).
        NSApp.setActivationPolicy(.accessory)
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        print("[Magpie] Launch: bundleID=\(bundleID) hasCompletedOnboarding=\(hasCompletedOnboarding)")
        analytics.configure()
        analytics.trackAppOpened(hasCompletedOnboarding: hasCompletedOnboarding)

        setupStatusItem()
        setupPopover()
        setupEventMonitor()
        setupAccessStateMonitoring()

        // Give AppState callbacks for dismiss and settings
        appState.onDismiss = { [weak self] in
            self?.closePopover()
        }
        appState.onOpenSettings = { [weak self] in
            self?.openSettings()
        }

        // Global hotkey: toggle popover from anywhere
        KeyboardShortcuts.onKeyUp(for: .toggleClipboardHistory) { [weak self] in
            self?.togglePopover()
        }

        // Show onboarding on first launch.
        if !hasCompletedOnboarding {
            print("[Magpie] Launch: showing onboarding")
            showOnboarding()
        } else {
            print("[Magpie] Launch: onboarding skipped (already completed)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stopMonitoring()
        analytics.flush()
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
        // Refresh clipboard access state each time the popover opens
        appState.accessChecker.checkAccess()
        appState.loadClips()
        analytics.trackPopoverOpened(itemCount: appState.displayedClips.count)
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

    private func setupAccessStateMonitoring() {
        appState.accessChecker.$accessState
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                print("[Magpie] accessState changed -> \(state)")
                switch state {
                case .allowed:
                    print("[Magpie] accessState=allowed, starting monitor")
                    self.appState.startMonitoring()
                case .needsPermission, .denied:
                    print("[Magpie] accessState=\(state), stopping monitor")
                    self.appState.stopMonitoring()
                }
            }
            .store(in: &cancellables)

        // Ensure the current state is reflected immediately.
        appState.accessChecker.checkAccess()
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        let onboardingView = OnboardingView(
            accessChecker: appState.accessChecker
        ) { [weak self] in
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        }

        let hostingController = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to Magpie"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 400, height: 480))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
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
        window.setContentSize(NSSize(width: 560, height: 650))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
}
