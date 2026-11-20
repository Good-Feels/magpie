import AppKit
import Foundation

/// Resolves information about the currently frontmost application.
/// Used to tag each clipboard entry with its source app.
public struct AppResolver: Sendable {
    @MainActor private static let icons: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        return cache
    }()

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
        let key = bundleID as NSString
        if let icon = icons.object(forKey: key) { return icon }
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleID
        ) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons.setObject(icon, forKey: key)
        return icon
    }
}
