import Foundation
import KeyboardShortcuts
import ServiceManagement
import Sparkle

enum LoginItemRepairRules {
    /// Repair only when the user opted in and macOS lost the registration.
    /// `.enabled` needs nothing; `.requiresApproval` means re-registering
    /// is pointless — the user must approve it in System Settings.
    ///
    /// `alreadyRepairedInThisEnvironment` limits repair to once per
    /// (app build, macOS version): a dropped registration in a NEW
    /// environment is macOS losing it (update replaced the bundle, BTM
    /// reset), but a drop in an environment we already repaired means the
    /// user removed Magpie in System Settings > Login Items — re-adding it
    /// every launch would fight their explicit choice.
    static func shouldAttemptRepair(
        desiredEnabled: Bool,
        status: SMAppService.Status,
        alreadyRepairedInThisEnvironment: Bool
    ) -> Bool {
        desiredEnabled
            && !alreadyRepairedInThisEnvironment
            && (status == .notRegistered || status == .notFound)
    }

    /// Users who enabled launch-at-login before the choice was persisted
    /// have no stored preference. If the login item is currently live,
    /// backfill the stored value to `true` so a future drop can be
    /// repaired. Returns the value to persist, or `nil` to write nothing.
    static func backfillDesiredValue(
        storedDesired: Bool?,
        statusIsEnabled: Bool
    ) -> Bool? {
        guard storedDesired == nil, statusIsEnabled else { return nil }
        return true
    }
}

enum UpdateFailureRules {
    /// Sparkle routes EVERY aborted update cycle through
    /// `updater(_:didAbortWithError:)` in `SUSparkleErrorDomain` —
    /// including "no update found", user cancellation, and scheduled
    /// background checks failing offline. Only a real failure of a check
    /// the user started warrants the manual-download alert.
    static let routineAbortCodes: Set<Int> = [
        Int(SUError.noUpdateError.rawValue),
        Int(SUError.installationCanceledError.rawValue),
        Int(SUError.installationAuthorizeLaterError.rawValue),
    ]

    static func shouldOfferManualDownload(
        errorDomain: String,
        errorCode: Int,
        userInitiated: Bool
    ) -> Bool {
        userInitiated
            && errorDomain == SUSparkleErrorDomain
            && !routineAbortCodes.contains(errorCode)
    }
}

enum StatusItemVisibilityRules {
    /// macOS pushes status items evicted from a full menu bar outside
    /// every screen's frame. Occlusion state alone can't distinguish
    /// "menu bar full" from a locked screen, a fullscreen app, or an
    /// auto-hidden menu bar — so the "your icon is hidden" warning must
    /// only fire on the off-screen-frame signal.
    static func isConfidentlyEvicted(
        buttonWindowFrame: CGRect,
        screenFrames: [CGRect]
    ) -> Bool {
        !screenFrames.contains { $0.intersects(buttonWindowFrame) }
    }
}

enum SessionHealthRules {
    static func previousSessionEndedUnexpectedly(
        hasPreviousSession: Bool,
        endedCleanly: Bool
    ) -> Bool {
        hasPreviousSession && !endedCleanly
    }
}

enum HiddenStatusItemCopy {
    /// Alert body for the hidden-status-item warning. The shortcut is
    /// user-configurable (and clearable), so the copy must render the
    /// live binding rather than hardcode ⌘⇧V.
    static func alertBody(shortcutText: String?) -> String {
        let hint: String
        if let shortcutText {
            hint = "press \(shortcutText) to open your history anytime"
        } else {
            hint = "set a keyboard shortcut in Magpie Settings to open your history without the icon"
        }

        return """
            Your menu bar is full, so macOS is hiding Magpie's icon. On MacBooks with a notch this happens with fewer icons.

            Magpie is still saving your clipboard — \(hint). To make the icon visible, quit another menu bar app or use a menu bar manager.
            """
    }
}

enum PopoverAnchorRules {
    /// Where to anchor the history popover when the status item is hidden
    /// (menu bar full / under the notch): a 1-point rect at the top center
    /// of the screen, mimicking the status item position.
    static func fallbackAnchorRect(visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.midX,
            y: visibleFrame.maxY - 1,
            width: 1,
            height: 1
        )
    }
}

enum StartupUIRules {
    static func shouldShowMoveAction(isRunningFromApplicationsFolder: Bool) -> Bool {
        !isRunningFromApplicationsFolder
    }

    static func startupStatusText(
        isRunningFromApplicationsFolder: Bool,
        statusDescription: String
    ) -> String {
        if isRunningFromApplicationsFolder &&
            statusDescription.lowercased().contains("not found") {
            return "Running from /Applications. If Launch at Login is unavailable, restart Magpie once."
        }

        return statusDescription
    }
}

enum VersionDisplayFormatter {
    static func versionText(infoDictionary: [String: Any]?) -> String {
        let shortVersion = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Version \(shortVersion) (\(build))"
    }
}

enum ShortcutSettingsCopy {
    static let helperText = "Set the default shortcut or clear it. Changes apply immediately."
}

enum ShortcutSettingsRules {
    static func validationMessage(
        for shortcut: KeyboardShortcuts.Shortcut?
    ) -> String? {
        guard let shortcut else {
            return "Press a key combination."
        }

        guard shortcut.key != nil else {
            return "Unsupported key. Try a different key combination."
        }

        let hasRequiredModifier = !shortcut.modifiers
            .intersection([.command, .option, .control, .shift])
            .isEmpty
        if !hasRequiredModifier {
            return "Include at least one modifier key (\u{2318}, \u{2325}, \u{2303}, or \u{21e7})."
        }

        return nil
    }
}

enum LegacyDatabaseMigrationRules {
    static let databaseBaseName = "clipboard.sqlite"
    static let suffixes = ["", "-wal", "-shm"]

    static func shouldMigrate(
        targetDir: URL,
        legacyDir: URL,
        targetDatabaseExists: Bool,
        legacyDatabaseExists: Bool
    ) -> Bool {
        if targetDir.standardizedFileURL == legacyDir.standardizedFileURL {
            return false
        }

        if targetDatabaseExists {
            return false
        }

        return legacyDatabaseExists
    }
}
