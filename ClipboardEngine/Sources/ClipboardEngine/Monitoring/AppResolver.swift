import AppKit
import Foundation

/// Resolves information about the currently frontmost application.
/// Used to tag each clipboard entry with its source app.
public struct AppResolver: Sendable {

    /// Returns the bundle ID and display name of the frontmost application.
    @MainActor
    public static func frontmostAppInfo() -> (bundleID: String?, name: String?) {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return (nil, nil)
        }
        return (app.bundleIdentifier, app.localizedName)
    }

    /// Returns the icon for an app given its bundle identifier.
    /// Useful for displaying source app icons in the clip list.
    @MainActor
    public static func iconForBundleID(_ bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleID
        ) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
