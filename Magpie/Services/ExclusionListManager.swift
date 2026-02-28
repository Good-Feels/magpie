import Foundation
import AppKit
import SwiftUI

/// Manages the set of app bundle identifiers whose clipboard events
/// should be ignored. Persisted in UserDefaults.
@MainActor
final class ExclusionListManager: ObservableObject {
    @Published var excludedBundleIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(
                Array(excludedBundleIDs),
                forKey: Self.storageKey
            )
        }
    }

    private static let storageKey = "excludedAppBundleIDs"

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? []
        self.excludedBundleIDs = Set(stored)
    }

    // MARK: - API

    /// Returns `true` if clips from the given bundle ID should be ignored.
    func isExcluded(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return excludedBundleIDs.contains(id)
    }

    func exclude(_ bundleID: String) {
        excludedBundleIDs.insert(bundleID)
    }

    func include(_ bundleID: String) {
        excludedBundleIDs.remove(bundleID)
    }

    // MARK: - Running Apps

    /// Returns all currently running regular applications (excluding
    /// background-only processes) for the exclusion picker.
    func runningApps() -> [(bundleID: String, name: String, icon: NSImage?)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier else { return nil }
                return (
                    bundleID: bundleID,
                    name: app.localizedName ?? bundleID,
                    icon: app.icon
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
