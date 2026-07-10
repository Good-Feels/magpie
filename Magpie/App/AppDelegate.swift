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
class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let appState = AppState()
    private let analytics = AnalyticsService.shared

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var fallbackAnchorWindow: NSWindow?
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
        migrateShortcutForKeyboardLayoutIfNeeded()
        KeyboardShortcuts.onKeyUp(for: .toggleClipboardHistory) { [weak self] in
            self?.togglePopover()
        }

        // Show onboarding on first launch.
        if !hasCompletedOnboarding {
            print("[Magpie] Launch: showing onboarding")
            showOnboarding()
        } else {
            print("[Magpie] Launch: onboarding skipped (already completed)")
            warnIfStatusItemHidden()
        }

        // Re-register launch-at-login if macOS dropped it (BTM resets,
        // updates replacing the bundle). Deferred so the synchronous
        // SMAppService XPC calls don't delay menu bar setup at login.
        Task { @MainActor in
            LaunchAtLoginService().healRegistrationIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stopMonitoring()
        analytics.flush()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Shortcut Migration

    /// Pre-1.0.10 builds stored the physical QWERTY-V shortcut for every
    /// user. On non-QWERTY layouts (Dvorak, AZERTY, …) that key doesn't
    /// type "v", so the hotkey the UI advertised never worked. One-time:
    /// move a stored legacy default to the layout-aware one. Customized
    /// shortcuts don't match the legacy default and are untouched.
    private func migrateShortcutForKeyboardLayoutIfNeeded() {
        let migratedKey = "didMigrateShortcutToKeyboardLayout"
        guard !UserDefaults.standard.bool(forKey: migratedKey) else { return }
        UserDefaults.standard.set(true, forKey: migratedKey)

        guard ShortcutLayoutRules.shouldMigrateStoredShortcut(
            stored: KeyboardShortcuts.getShortcut(for: .toggleClipboardHistory),
            legacyDefault: .legacyPhysicalDefault,
            layoutAwareDefault: .layoutAwareDefault
        ) else { return }

        KeyboardShortcuts.setShortcut(.layoutAwareDefault, for: .toggleClipboardHistory)
        print("[Magpie] Migrated hotkey to layout-aware default: \(KeyboardShortcuts.Shortcut.layoutAwareDefault)")
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

    // MARK: - Menu Bar Visibility

    /// When the menu bar is full (which happens much sooner on MacBooks
    /// with a notch), macOS silently hides status items. The app is then
    /// running with no visible UI, which reads as "the app didn't open".
    /// Detect that and explain it to the user once.
    ///
    /// Warns only on the confident signal (item pushed off-screen) —
    /// occlusion alone false-positives at login with the screen locked,
    /// in fullscreen apps, and with menu bar auto-hide, which would burn
    /// the one-shot alert on a wrong warning.
    private func warnIfStatusItemHidden() {
        // Give the status item a moment to be laid out after launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, self.isStatusItemEvicted() else { return }
            print("[Magpie] Status item is hidden — menu bar is full (or item is under the notch)")
            analytics.trackStatusItemHidden()

            let warnedKey = "hasWarnedHiddenStatusItem"
            guard !UserDefaults.standard.bool(forKey: warnedKey) else { return }
            UserDefaults.standard.set(true, forKey: warnedKey)
            self.showHiddenStatusItemAlert()
        }
    }

    /// True when macOS has pushed the status item outside every screen —
    /// the definitive "menu bar is full" signal.
    private func isStatusItemEvicted() -> Bool {
        guard let window = statusItem.button?.window else { return false }
        return StatusItemVisibilityRules.isConfidentlyEvicted(
            buttonWindowFrame: window.frame,
            screenFrames: NSScreen.screens.map(\.frame)
        )
    }

    private func isStatusItemVisible() -> Bool {
        guard let window = statusItem.button?.window else { return false }
        guard window.occlusionState.contains(.visible) else { return false }
        return !isStatusItemEvicted()
    }

    private func showHiddenStatusItemAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Magpie is running, but its menu bar icon is hidden"
        let shortcut = KeyboardShortcuts.getShortcut(for: .toggleClipboardHistory)
        alert.informativeText = HiddenStatusItemCopy.alertBody(
            shortcutText: shortcut.map(String.init(describing:))
        )
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
        popover.delegate = self
    }

    /// Covers every close path — performClose and transient outside-click
    /// dismissal — so the fallback anchor window never outlives the popover.
    func popoverDidClose(_ notification: Notification) {
        fallbackAnchorWindow?.orderOut(nil)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        // Refresh clipboard access state each time the popover opens
        appState.accessChecker.checkAccess()
        appState.loadClips()
        analytics.trackPopoverOpened(itemCount: appState.displayedClips.count)

        // When the menu bar is full, macOS pushes the status item's window
        // off-screen. Anchoring the popover to it would open the popover
        // off-screen too — invisible, but isShown == true, so the hotkey
        // appears dead. Fall back to an on-screen anchor instead.
        if let button = statusItem.button, isStatusItemVisible() {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        } else {
            print("[Magpie] Status item hidden — showing popover from fallback anchor")
            showPopoverFromFallbackAnchor()
        }

        // Ensure the popover window becomes key so the search bar gets focus
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Anchors the popover to an invisible 1-point window at the top center
    /// of the active screen, mimicking the status item position.
    private func showPopoverFromFallbackAnchor() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let screen else { return }

        let anchorRect = PopoverAnchorRules.fallbackAnchorRect(
            visibleFrame: screen.visibleFrame
        )

        let window: NSWindow
        if let existing = fallbackAnchorWindow {
            window = existing
        } else {
            window = NSWindow(
                contentRect: anchorRect,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .statusBar
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .transient]
            window.isReleasedWhenClosed = false
            fallbackAnchorWindow = window
        }

        window.setFrame(anchorRect, display: false)
        window.orderFrontRegardless()

        guard let anchorView = window.contentView else { return }
        // A borderless anchor window can't become key without the app
        // being active — scoped here so the normal status-item path never
        // steals activation from the user's frontmost app.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
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
