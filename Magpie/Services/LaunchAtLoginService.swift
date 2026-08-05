import Foundation
import ServiceManagement
import SwiftUI
import AppKit
import Combine

/// The subset of `SMAppService` this service needs. Abstracting it lets
/// launch-at-login orchestration (persistence, repair, failure-revert) be
/// unit tested with a fake instead of mutating real system state.
protocol LoginItemControlling {
    var status: SMAppService.Status { get }
    var legacyMainAppWasEnabled: Bool { get }
    func register() throws
    func unregister() throws
}

extension LoginItemControlling {
    var legacyMainAppWasEnabled: Bool { false }
}

enum KeeperServiceConfiguration {
    static var agentPlistName: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.goodfeels.magpie"
        return "\(bundleID).keeper.plist"
    }
}

/// Production implementation backed by a launchd-managed recovery agent.
/// The previous main-app login registration is removed after the keeper is
/// live so updates migrate existing users without leaving duplicate jobs.
struct SystemLoginItemControl: LoginItemControlling {
    private var keeper: SMAppService {
        SMAppService.agent(plistName: KeeperServiceConfiguration.agentPlistName)
    }

    var status: SMAppService.Status { keeper.status }

    var legacyMainAppWasEnabled: Bool {
        let legacyStatus = SMAppService.mainApp.status
        return legacyStatus == .enabled || legacyStatus == .requiresApproval
    }

    func register() throws {
        try keeper.register()
        if legacyMainAppWasEnabled {
            try? SMAppService.mainApp.unregister()
        }
    }

    func unregister() throws {
        var firstError: Error?

        if keeper.status != .notRegistered {
            do {
                try keeper.unregister()
            } catch {
                firstError = error
            }
        }

        if SMAppService.mainApp.status != .notRegistered {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                firstError = firstError ?? error
            }
        }

        if let firstError {
            throw firstError
        }
    }
}

/// Wraps `SMAppService` to manage the "Launch at Login" preference and
/// the launchd-managed keeper that restores Magpie after forced exits.
/// Requires macOS 13+ and a valid app bundle with a CFBundleIdentifier.
///
/// Login item defaults to OFF on first launch (MAS-safe). The onboarding
/// flow prompts the user to enable it. The user's choice is persisted in
/// UserDefaults so a registration dropped by macOS (Background Task
/// Management resets, app updates replacing the bundle) can be repaired
/// at the next launch via `healRegistrationIfNeeded()`.
@MainActor
final class LaunchAtLoginService: ObservableObject {
    static let desiredEnabledKey = "launchAtLoginDesired"
    static let healStampKey = "launchAtLoginHealStamp"

    enum MoveResult: Equatable {
        case moved
        case alreadyInApplications
        case destinationExists
        case failed(String)
    }

    @Published var isEnabled: Bool {
        didSet {
            guard !isSyncingFromSystem, isEnabled != oldValue else { return }
            setLoginItem(enabled: isEnabled)
        }
    }

    /// Live registration status, published so UI like the
    /// requires-approval notice updates when the status changes behind
    /// the app's back (e.g. the user approves the item in System
    /// Settings and switches back to Magpie).
    @Published private(set) var status: SMAppService.Status

    private var isSyncingFromSystem = false
    private let control: LoginItemControlling
    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()

    init(
        control: LoginItemControlling = SystemLoginItemControl(),
        defaults: UserDefaults = .standard
    ) {
        self.control = control
        self.defaults = defaults
        // Reflect the current system state — no auto-registration here;
        // repair of dropped registrations happens once per launch in
        // healRegistrationIfNeeded().
        let initialStatus = control.status
        status = initialStatus
        isEnabled = initialStatus == .enabled

        // Status can change outside the app (approval granted in System
        // Settings); re-read it whenever the app becomes active.
        NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatus()
            }
        }
        .store(in: &cancellables)
    }

    /// Re-reads the registration status from the system.
    func refreshStatus() {
        let liveStatus = control.status
        status = liveStatus

        let liveEnabled = liveStatus == .enabled
        if isEnabled != liveEnabled {
            isSyncingFromSystem = true
            isEnabled = liveEnabled
            isSyncingFromSystem = false
        }
    }

    // MARK: - Public

    /// Re-registers the login item when the user chose to enable it but
    /// macOS dropped the registration. Called once at app launch.
    /// Returns `true` if a repair registration was attempted successfully.
    @discardableResult
    func healRegistrationIfNeeded() -> Bool {
        refreshStatus()

        // Users who enabled launch-at-login before the choice was
        // persisted have no stored preference — capture it from the
        // live registration so future drops can be repaired.
        if let backfill = LoginItemRepairRules.backfillDesiredValue(
            storedDesired: defaults.object(forKey: Self.desiredEnabledKey) as? Bool,
            statusIsEnabled: status == .enabled || control.legacyMainAppWasEnabled
        ) {
            defaults.set(backfill, forKey: Self.desiredEnabledKey)
        }

        let desired = defaults.bool(forKey: Self.desiredEnabledKey)
        guard LoginItemRepairRules.shouldAttemptRepair(
            desiredEnabled: desired,
            status: status,
            alreadyRepairedInThisEnvironment:
                defaults.string(forKey: Self.healStampKey) == Self.currentHealStamp
        ) else {
            return false
        }

        do {
            try control.register()
            refreshStatus()
            // Only a successful registration consumes the repair budget.
            // Transient ServiceManagement failures must remain retryable on
            // the next launch, or Magpie can stay unavailable indefinitely.
            defaults.set(Self.currentHealStamp, forKey: Self.healStampKey)
            print("[Magpie] Launch at login: repaired dropped registration")
            return true
        } catch {
            print("[Magpie] Launch at login: repair failed: \(error)")
            return false
        }
    }

    /// Identifies the (app build, macOS version) environment a repair ran
    /// in. Registration drops caused by macOS happen when this changes —
    /// an update replaced the bundle, or the OS was upgraded.
    static var currentHealStamp: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "keeper-v1-\(build)-\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    /// Registers or unregisters the login item. Called from didSet and
    /// also from the onboarding flow.
    func setLoginItem(enabled: Bool) {
        if enabled {
            do {
                try control.register()
            } catch {
                print("[Magpie] Launch at login error: \(error)")
                // Revert without re-triggering setLoginItem from didSet.
                if isEnabled != false {
                    isSyncingFromSystem = true
                    isEnabled = false
                    isSyncingFromSystem = false
                }
                refreshStatus()
                return
            }
            // A fresh explicit opt-in resets the once-per-environment
            // repair budget: a later drop should be repairable again.
            defaults.removeObject(forKey: Self.healStampKey)
        } else if control.status != .notRegistered || control.legacyMainAppWasEnabled {
            // A throw here (e.g. a stale .notFound registration) must not
            // trap the user with a toggle that snaps back on — honor the
            // disable regardless.
            do {
                try control.unregister()
            } catch {
                print("[Magpie] Launch at login: unregister failed, disabling anyway: \(error)")
            }
        }

        defaults.set(enabled, forKey: Self.desiredEnabledKey)
        refreshStatus()
    }

    /// True when registration succeeded but the user still has to approve
    /// the login item in System Settings before it takes effect.
    var requiresApproval: Bool {
        status == .requiresApproval
    }

    var isDesiredEnabled: Bool {
        defaults.bool(forKey: Self.desiredEnabledKey)
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// The current registration status, useful for displaying in the UI.
    var statusDescription: String {
        switch status {
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

        // The login item registration points at this (old) location.
        // Unregister it so the copy in /Applications can register cleanly:
        // healRegistrationIfNeeded() reads the persisted choice on next launch.
        let registrationStatus = control.status
        if registrationStatus == .enabled || registrationStatus == .requiresApproval {
            try? control.unregister()
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        // Without this, LaunchServices resolves the same bundle ID to this
        // running instance and never starts the /Applications copy.
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destinationURL, configuration: config) { _, launchError in
            DispatchQueue.main.async {
                if let launchError {
                    completion(.failed("Copied app but failed to relaunch: \(launchError.localizedDescription)"))
                    return
                }

                completion(.moved)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Trash the old copy so two bundles with the same bundle
                    // ID don't fight over the login item registration.
                    NSWorkspace.shared.recycle([currentURL]) { _, _ in
                        DispatchQueue.main.async {
                            NSApp.terminate(nil)
                        }
                    }
                }
            }
        }
    }
}
