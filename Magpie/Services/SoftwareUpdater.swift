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

    /// Manually trigger an update check (e.g. from a "Check Now" button).
    func checkForUpdates() {
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
        guard shouldOfferManualDownload(for: error as NSError) else { return }
        presentManualDownloadAlert(for: error as NSError)
    }

    private func shouldOfferManualDownload(for error: NSError) -> Bool {
        error.domain == SUSparkleErrorDomain
    }

    private func presentManualDownloadAlert(for error: NSError) {
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
