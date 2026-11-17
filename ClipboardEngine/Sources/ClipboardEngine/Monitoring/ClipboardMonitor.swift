import AppKit
import Foundation

/// Polls `NSPasteboard.general` at a regular interval and fires a callback
/// whenever the pasteboard's `changeCount` increments (i.e. a new copy/cut).
///
/// Usage:
/// ```swift
/// let monitor = ClipboardMonitor()
/// monitor.start { pasteboard in
///     // handle new clipboard content
/// }
/// ```
@MainActor
public final class ClipboardMonitor: ObservableObject {
    /// The last observed change count – public so the app can update it
    /// when it writes to the pasteboard itself (to avoid re-capturing).
    @Published public var lastChangeCount: Int

    private var timer: Timer?
    private let pasteboard: NSPasteboard
    private let currentSourceBundleID: () -> String?
    private let activationCenter: NotificationCenter
    private let activatedBundleID: (Notification) -> String?
    private var activationObserver: NSObjectProtocol?
    private var sourceInterval = ClipboardSourceInterval()
    public private(set) var sourceBundleIDsForCurrentChange: Set<String> = []
    private let pollInterval: TimeInterval
    private var onNewClip: ((NSPasteboard) -> Void)?

    // MARK: - Init

    public init(
        pollInterval: TimeInterval = 0.5,
        pasteboard: NSPasteboard = .general,
        currentSourceBundleID: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
        activationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        activatedBundleID: @escaping (Notification) -> String? = {
            ($0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
        }
    ) {
        self.pollInterval = pollInterval
        self.pasteboard = pasteboard
        self.currentSourceBundleID = currentSourceBundleID
        self.activationCenter = activationCenter
        self.activatedBundleID = activatedBundleID
        self.lastChangeCount = pasteboard.changeCount
    }

    // MARK: - Lifecycle

    /// Starts polling. The `onNewClip` callback fires on the main thread
    /// each time new content is detected.
    public func start(onNewClip: @escaping (NSPasteboard) -> Void) {
        // Invalidate any existing timer to prevent duplicates
        timer?.invalidate()

        self.onNewClip = onNewClip
        sourceInterval = ClipboardSourceInterval(
            initialBundleID: currentSourceBundleID()
        )
        if let activationObserver {
            activationCenter.removeObserver(activationObserver)
        }
        activationObserver = activationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            // .main delivery is synchronous: do not defer source evidence past
            // a polling callback scheduled on the same main run loop.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sourceInterval.observe(self.activatedBundleID(notification))
            }
        }
        timer = Timer.scheduledTimer(
            withTimeInterval: pollInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkForChanges()
            }
        }
    }

    /// Stops the polling timer.
    public func stop() {
        timer?.invalidate()
        timer = nil
        onNewClip = nil
        if let activationObserver {
            activationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    // MARK: - Private

    // Internal so deterministic tests exercise the same polling callback without
    // depending on XCTest's hosting of the system run loop.
    func checkForChanges() {
        sourceBundleIDsForCurrentChange = sourceInterval.finish(
            currentBundleID: currentSourceBundleID()
        )
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount
        onNewClip?(pasteboard)
    }
}
