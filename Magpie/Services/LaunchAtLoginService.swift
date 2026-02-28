import Foundation
import ServiceManagement
import SwiftUI

/// Wraps `SMAppService` to manage the "Launch at Login" preference.
/// Requires macOS 13+ and a valid app bundle with a CFBundleIdentifier.
///
/// On first launch, login item is enabled by default. Users can disable
/// it in Settings. The choice is remembered across launches.
@MainActor
final class LaunchAtLoginService: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            setLoginItem(enabled: isEnabled)
        }
    }

    init() {
        let status = SMAppService.mainApp.status
        let hasBeenConfigured = UserDefaults.standard.bool(forKey: "hasConfiguredLoginItem")

        if status == .enabled {
            // Already registered — keep it on
            isEnabled = true
        } else if !hasBeenConfigured {
            // First launch — enable by default
            isEnabled = true
            UserDefaults.standard.set(true, forKey: "hasConfiguredLoginItem")
            // didSet isn't called during init, so register manually
            try? SMAppService.mainApp.register()
        } else {
            // User previously disabled it — respect their choice
            isEnabled = false
        }
    }

    // MARK: - Private

    private func setLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            UserDefaults.standard.set(true, forKey: "hasConfiguredLoginItem")
        } catch {
            print("[Magpie] Launch at login error: \(error)")
            // Revert on failure without re-triggering didSet
            let reverted = !enabled
            if isEnabled != reverted {
                isEnabled = reverted
            }
        }
    }

    /// The current registration status, useful for displaying in the UI.
    var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "Enabled"
        case .notRegistered:
            return "Not registered"
        case .notFound:
            return "App not found — move to /Applications for login items"
        case .requiresApproval:
            return "Requires approval in System Settings"
        @unknown default:
            return "Unknown"
        }
    }
}
