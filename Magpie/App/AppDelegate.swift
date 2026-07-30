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
    private let diagnostics = AppSessionDiagnostics.shared
    private let launchAtLoginService = LaunchAtLoginService()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var fallbackAnchorWindow: NSWindow?
    private var eventMonitor: Any?
    private var persistenceActivity: NSObjectProtocol?
    private var diagnosticHeartbeatTimer: Timer?
    private var statusItemHealthTimer: Timer?
    private var workspaceWakeObserver: NSObjectProtocol?
    private var screenChangeObserver: NSObjectProtocol?
    private var consecutiveDetachedStatusItemChecks = 0
    private var hasShownLoginItemProblem = false
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        diagnostics.beginSession()
        beginPersistenceActivity()

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
        setupRecoveryMonitoring()

        // Give AppState callbacks for dismiss and settings
        appState.onDismiss = { [weak self] in
            self?.closePopover()
        }
        appState.onOpenSettings = { [weak self] in
            self?.openSettings()
        }

        // Global hotkey: toggle popover from anywhere
        migrateShortcutForKeyboardLayoutIfNeeded()
        registerGlobalShortcut()

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
            let repaired = launchAtLoginService.healRegistrationIfNeeded()
            diagnostics.record(
                "login_item_checked desired=\(launchAtLoginService.isDesiredEnabled) "
                    + "status=\(launchAtLoginService.statusDescription) repaired=\(repaired)"
            )

            if hasCompletedOnboarding {
                showLoginItemProblemIfNeeded()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stopMonitoring()
        analytics.flush()
        diagnosticHeartbeatTimer?.invalidate()
        statusItemHealthTimer?.invalidate()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = workspaceWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        diagnostics.endSession()
        endPersistenceActivity()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        diagnostics.record("last_window_closed termination_refused")
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        diagnostics.record("termination_requested")
        return .terminateNow
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        diagnostics.record("application_reopened visible_windows=\(flag)")

        if let onboardingWindow, onboardingWindow.isVisible {
            onboardingWindow.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
        } else if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
        } else if !popover.isShown {
            showPopover(trigger: "reopen")
        }
        return true
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
            button.action = #selector(handleStatusItemClick)
            button.target = self
        }
    }

    /// If Control Center has detached the underlying status-item scene,
    /// replace it in place. This is distinct from a merely full menu bar:
    /// evicted items still have a window and use the fallback popover anchor.
    private func repairStatusItemIfDetached(reason: String) {
        guard statusItem?.button?.window == nil else {
            consecutiveDetachedStatusItemChecks = 0
            return
        }

        diagnostics.record("status_item_recreated reason=\(reason)")
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        setupStatusItem()
        consecutiveDetachedStatusItemChecks = 0
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

    @objc private func handleStatusItemClick() {
        togglePopover(trigger: "status_item")
    }

    private func togglePopover(trigger: String) {
        diagnostics.record("popover_toggle_received trigger=\(trigger)")
        if popover.isShown {
            closePopover()
        } else {
            showPopover(trigger: trigger)
        }
    }

    private func showPopover(trigger: String) {
        repairStatusItemIfDetached(reason: trigger)

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
            diagnostics.record("popover_opened trigger=\(trigger) anchor=status_item")
        } else {
            print("[Magpie] Status item hidden — showing popover from fallback anchor")
            showPopoverFromFallbackAnchor()
            diagnostics.record("popover_opened trigger=\(trigger) anchor=fallback")
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

    // MARK: - Recovery Monitoring

    private func registerGlobalShortcut() {
        KeyboardShortcuts.onKeyUp(for: .toggleClipboardHistory) { [weak self] in
            self?.togglePopover(trigger: "global_shortcut")
        }
    }

    /// Clipboard monitoring is the app's primary work, so an empty window
    /// list is an idle UI state rather than a reason for macOS to terminate
    /// the process. Retaining an activity token protects both automatic and
    /// sudden termination paths for the lifetime of the app.
    private func beginPersistenceActivity() {
        guard persistenceActivity == nil else { return }

        let processInfo = ProcessInfo.processInfo
        processInfo.disableAutomaticTermination("Magpie clipboard monitoring")
        processInfo.disableSuddenTermination()
        persistenceActivity = processInfo.beginActivity(
            options: [
                .automaticTerminationDisabled,
                .suddenTerminationDisabled,
                .background,
            ],
            reason: "Magpie clipboard monitoring"
        )
        diagnostics.record(
            "termination_protection_enabled "
                + "automatic_support=\(processInfo.automaticTerminationSupportEnabled)"
        )
    }

    private func endPersistenceActivity() {
        let processInfo = ProcessInfo.processInfo
        if let persistenceActivity {
            processInfo.endActivity(persistenceActivity)
            self.persistenceActivity = nil
        }
        processInfo.enableAutomaticTermination("Magpie clipboard monitoring")
        processInfo.enableSuddenTermination()
    }

    private func setupRecoveryMonitoring() {
        diagnosticHeartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: 300,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.diagnostics.heartbeat()
            }
        }
        diagnosticHeartbeatTimer?.tolerance = 30

        // Require two failed checks so a transient screen-layout change does
        // not churn a healthy item. Direct hotkey/reopen attempts repair it
        // immediately because the user is actively asking for UI.
        statusItemHealthTimer = Timer.scheduledTimer(
            withTimeInterval: 30,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.statusItem?.button?.window == nil {
                    self.consecutiveDetachedStatusItemChecks += 1
                    if self.consecutiveDetachedStatusItemChecks >= 2 {
                        self.repairStatusItemIfDetached(reason: "health_check")
                    }
                } else {
                    self.consecutiveDetachedStatusItemChecks = 0
                }
            }
        }
        statusItemHealthTimer?.tolerance = 5

        workspaceWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recoverAfterSystemTransition(reason: "wake")
            }
        }

        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recoverAfterSystemTransition(reason: "screen_change")
            }
        }
    }

    private func recoverAfterSystemTransition(reason: String) {
        diagnostics.record("system_transition reason=\(reason)")
        beginPersistenceActivity()
        registerGlobalShortcut()
        repairStatusItemIfDetached(reason: reason)
    }

    private func showLoginItemProblemIfNeeded() {
        guard launchAtLoginService.isDesiredEnabled,
              launchAtLoginService.status != .enabled,
              !hasShownLoginItemProblem
        else { return }

        hasShownLoginItemProblem = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self,
                  self.launchAtLoginService.isDesiredEnabled,
                  self.launchAtLoginService.status != .enabled
            else { return }

            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Magpie isn't allowed to launch at login"
            alert.informativeText = """
                Magpie needs to stay open to save your clipboard history. \
                macOS currently reports “\(self.launchAtLoginService.statusDescription)”.

                Allow Magpie in System Settings → General → Login Items so \
                it is available after every login.
                """
            alert.addButton(withTitle: "Open Login Items Settings")
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() == .alertFirstButtonReturn {
                self.launchAtLoginService.openLoginItemsSettings()
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
