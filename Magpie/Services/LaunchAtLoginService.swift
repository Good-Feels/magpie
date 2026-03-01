import Foundation
import ServiceManagement
import SwiftUI
import AppKit

/// Wraps `SMAppService` to manage the "Launch at Login" preference.
/// Requires macOS 13+ and a valid app bundle with a CFBundleIdentifier.
///
/// Login item defaults to OFF on first launch (MAS-safe). The onboarding
/// flow prompts the user to enable it. Choice is remembered across launches.
@MainActor
final class LaunchAtLoginService: ObservableObject {
    enum MoveResult: Equatable {
        case moved
        case alreadyInApplications
        case destinationExists
        case failed(String)
    }

    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            setLoginItem(enabled: isEnabled)
        }
    }

    init() {
        // Just reflect the current system state — no auto-registration
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Public

    /// Registers or unregisters the login item. Called from didSet and
    /// also from the onboarding flow.
    func setLoginItem(enabled: Bool) {
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

    var isRunningFromApplicationsFolder: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    func openApplicationsFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: "/Applications")
    }

    func revealCurrentAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func moveToApplicationsAndRelaunch(completion: @escaping (MoveResult) -> Void) {
        let currentURL = Bundle.main.bundleURL.standardizedFileURL
        let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let destinationURL = applicationsURL.appendingPathComponent(currentURL.lastPathComponent)

        if currentURL == destinationURL.standardizedFileURL {
            completion(.alreadyInApplications)
            return
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            completion(.destinationExists)
            return
        }

        do {
            try fileManager.copyItem(at: currentURL, to: destinationURL)
        } catch {
            completion(.failed("Couldn't copy app to /Applications: \(error.localizedDescription)"))
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: destinationURL, configuration: config) { _, launchError in
            if let launchError {
                completion(.failed("Copied app but failed to relaunch: \(launchError.localizedDescription)"))
                return
            }

            completion(.moved)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
        }
    }
}
