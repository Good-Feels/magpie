import AppKit
import Foundation

/// Checks and reports the app's clipboard access permission status.
///
/// On macOS 15.4+, the system prompts users when an app reads the clipboard
/// without direct user action (e.g., polling). Users can grant "Always Allow"
/// in System Settings > Privacy & Security > Paste from Other Apps.
///
/// On earlier macOS versions, clipboard access is unrestricted.
///
/// Uses runtime selector checks to avoid compile-time dependency on the
/// macOS 15.4 SDK, so this compiles on older Xcode versions too.
@MainActor
public final class ClipboardAccessChecker: ObservableObject {
    /// The current clipboard access state.
    public enum AccessState: Equatable {
        /// Clipboard access is allowed (either macOS < 15.4, or user granted it).
        case allowed
        /// User has not yet decided — each read triggers a consent alert.
        case needsPermission
        /// User explicitly denied clipboard access.
        case denied
    }

    @Published public private(set) var accessState: AccessState = .allowed

    public init() {
        checkAccess()
    }

    /// Re-checks the current permission state. Call this after the user
    /// returns from System Settings to refresh the UI.
    public func checkAccess() {
        let pasteboard = NSPasteboard.general
        let selector = NSSelectorFromString("accessBehavior")

        guard pasteboard.responds(to: selector) else {
            // Pre-15.4: clipboard access is always allowed
            accessState = .allowed
            return
        }

        // accessBehavior is an Int-backed ObjC enum (NSPasteboard.AccessBehavior):
        //   0 = allowedWithoutPrompt
        //   1 = transientUserPrompt
        //   2 = denied
        if let rawValue = pasteboard.value(forKey: "accessBehavior") as? Int {
            switch rawValue {
            case 0:
                accessState = .allowed
            case 2:
                accessState = .denied
            default:
                accessState = .needsPermission
            }
        } else {
            accessState = .allowed
        }
    }

    /// Whether the app has full clipboard access (either granted or pre-15.4).
    public var hasAccess: Bool {
        accessState == .allowed
    }

    /// Whether this macOS version has clipboard privacy controls.
    public var isPrivacyControlAvailable: Bool {
        NSPasteboard.general.responds(to: NSSelectorFromString("accessBehavior"))
    }

    /// Opens System Settings to the Pasteboard privacy pane.
    public func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard") {
            NSWorkspace.shared.open(url)
        }
    }
}
