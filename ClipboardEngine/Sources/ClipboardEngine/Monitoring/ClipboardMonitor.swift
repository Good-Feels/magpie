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
    private let pasteboard = NSPasteboard.general
    private let pollInterval: TimeInterval
    private var onNewClip: ((NSPasteboard) -> Void)?

    // MARK: - Init

    public init(pollInterval: TimeInterval = 0.5) {
        self.pollInterval = pollInterval
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    // MARK: - Lifecycle

    /// Starts polling. The `onNewClip` callback fires on the main thread
    /// each time new content is detected.
    public func start(onNewClip: @escaping (NSPasteboard) -> Void) {
        // Invalidate any existing timer to prevent duplicates
        timer?.invalidate()

        self.onNewClip = onNewClip
        timer = Timer.scheduledTimer(
            withTimeInterval: pollInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkForChanges()
            }
        }
    }

    /// Stops the polling timer.
    public func stop() {
        timer?.invalidate()
        timer = nil
        onNewClip = nil
    }

    // MARK: - Private

    private func checkForChanges() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount
        onNewClip?(pasteboard)
    }
}
