import Foundation
import KeyboardShortcuts

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
