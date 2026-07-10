import AppKit
import Foundation
import Sparkle

/// Wraps Sparkle's `SPUStandardUpdaterController` to expose update
/// functionality to SwiftUI views and provide a manual fallback path.
///
/// For direct distribution (non-MAS): checks `appcast.xml` for updates,
/// downloads and installs them via Sparkle's XPC services.
/// For MAS builds: Sparkle is linked but unused — updates come from the App Store.
@MainActor
final class SoftwareUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    private static let updateCheckInterval: TimeInterval = 60 * 60 * 8
    private static let latestReleaseURL = URL(string: "https://github.com/Good-Feels/magpie/releases/latest")!

    /// Whether Sparkle should check for updates automatically on launch.
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    /// Whether an update check is currently in progress.
    @Published var canCheckForUpdates: Bool = false

    private lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }()

    private lazy var updater: SPUUpdater = updaterController.updater
    private var observation: NSKeyValueObservation?

    override init() {
        automaticallyChecksForUpdates = false

        super.init()

        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        updater.updateCheckInterval = Self.updateCheckInterval

        // Observe canCheckForUpdates via KVO so the UI can disable
        // the button while a check is in progress.
        observation = updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    /// True while the current update cycle was started by the user.
    /// Sparkle reports background scheduled checks and manual checks
    /// through the same delegate callbacks; only user-initiated failures
    /// warrant an alert.
    private var lastCheckWasUserInitiated = false

    /// Manually trigger an update check (e.g. from a "Check Now" button).
    func checkForUpdates() {
        lastCheckWasUserInitiated = true
        updater.checkForUpdates()
    }

    func downloadLatestVersion() {
        NSWorkspace.shared.open(Self.latestReleaseURL)
    }

    /// The date of the last update check, if any.
    var lastUpdateCheckDate: Date? {
        updater.lastUpdateCheckDate
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        guard UpdateFailureRules.shouldOfferManualDownload(
            errorDomain: nsError.domain,
            errorCode: nsError.code,
            userInitiated: lastCheckWasUserInitiated
        ) else { return }
        presentManualDownloadAlert(for: nsError)
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        // The cycle is over either way; the next one is background-
        // initiated unless checkForUpdates() runs again.
        lastCheckWasUserInitiated = false
    }

    private func presentManualDownloadAlert(for error: NSError) {
        // Accessory apps don't get key status automatically; without
        // activating, the modal can open behind the frontmost app.
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Update failed"
        alert.informativeText = [
            error.localizedDescription,
            "You can download the latest version directly instead."
        ].joined(separator: "\n\n")
        alert.addButton(withTitle: "Download Latest Version")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            downloadLatestVersion()
        }
    }
}
