import Foundation
import ServiceManagement
import SwiftUI

/// Wraps `SMAppService` to manage the "Launch at Login" preference.
/// Requires macOS 13+ and a valid app bundle with a CFBundleIdentifier.
@MainActor
final class LaunchAtLoginService: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            setLoginItem(enabled: isEnabled)
        }
    }

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Private

    private func setLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
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
