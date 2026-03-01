import Foundation
import Sparkle

/// Wraps Sparkle's `SPUStandardUpdaterController` to expose update
/// functionality to SwiftUI views.
///
/// For direct distribution (non-MAS): checks `appcast.xml` for updates,
/// downloads and installs them via Sparkle's XPC services.
/// For MAS builds: Sparkle is linked but unused — updates come from the App Store.
@MainActor
final class SoftwareUpdater: ObservableObject {
    /// Whether Sparkle should check for updates automatically on launch.
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    /// Whether an update check is currently in progress.
    @Published var canCheckForUpdates: Bool = false

    private let updaterController: SPUStandardUpdaterController
    private let updater: SPUUpdater
    private var observation: NSKeyValueObservation?

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updater = updaterController.updater
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates

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

    /// The date of the last update check, if any.
    var lastUpdateCheckDate: Date? {
        updater.lastUpdateCheckDate
    }
}
