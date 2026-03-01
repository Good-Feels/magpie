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
        print("[Magpie] ClipboardAccessChecker init")
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
            print("[Magpie] checkAccess: accessBehavior unavailable (pre-15.4 API), state=allowed")
            return
        }

        if let rawValue = rawAccessBehavior {
            accessState = mapRawAccessBehavior(rawValue)
            print("[Magpie] checkAccess: rawAccessBehavior=\(rawValue) mappedState=\(accessState)")
        } else {
            accessState = .allowed
            print("[Magpie] checkAccess: rawAccessBehavior unavailable via KVC, state=allowed")
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

    /// Triggers a clipboard read to invoke the macOS consent dialog,
    /// then re-checks the access state after a short delay.
    public func requestAccess() {
        let pasteboard = NSPasteboard.general
        let before = rawAccessBehavior
        let didReadContent = forceReadClipboardContents(from: pasteboard)
        print("[Magpie] requestAccess: attempted clipboard read didReadContent=\(didReadContent) beforeRaw=\(before.map(String.init) ?? "n/a")")

        // Re-check after the dialog resolves
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            self?.checkAccess()
            let after = self?.rawAccessBehavior
            print("[Magpie] Clipboard access check: before=\(before.map(String.init) ?? "n/a") after=\(after.map(String.init) ?? "n/a") state=\(self?.accessState ?? .allowed)")
        }
    }

    /// Opens System Settings to the Pasteboard privacy pane.
    public func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Raw accessBehavior value from AppKit (macOS 15.4+):
    /// 0 = default, 1 = ask, 2 = alwaysAllow, 3 = alwaysDeny.
    public var rawAccessBehavior: Int? {
        NSPasteboard.general.value(forKey: "accessBehavior") as? Int
    }

    private func mapRawAccessBehavior(_ rawValue: Int) -> AccessState {
        switch rawValue {
        case 2:
            return .allowed
        case 3:
            return .denied
        default:
            return .needsPermission
        }
    }

    /// Reads actual clipboard payload bytes for the first available type.
    /// This is more reliable than `.string` only when clipboard content isn't text.
    @discardableResult
    private func forceReadClipboardContents(from pasteboard: NSPasteboard) -> Bool {
        if let item = pasteboard.pasteboardItems?.first {
            for type in item.types {
                if item.data(forType: type) != nil {
                    return true
                }
            }
        }

        if let type = pasteboard.types?.first, pasteboard.data(forType: type) != nil {
            return true
        }

        if pasteboard.string(forType: .string) != nil {
            return true
        }

        return false
    }
}
