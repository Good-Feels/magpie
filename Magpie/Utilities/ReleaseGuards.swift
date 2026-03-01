import Foundation

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
