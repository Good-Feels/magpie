import XCTest
@testable import Magpie

final class RegressionGuardsTests: XCTestCase {
    func testMoveActionHiddenWhenRunningFromApplications() {
        XCTAssertFalse(
            StartupUIRules.shouldShowMoveAction(isRunningFromApplicationsFolder: true)
        )
    }

    func testMoveActionShownWhenNotRunningFromApplications() {
        XCTAssertTrue(
            StartupUIRules.shouldShowMoveAction(isRunningFromApplicationsFolder: false)
        )
    }

    func testStartupStatusUsesFriendlyMessageForStaleNotFoundInApplications() {
        let text = StartupUIRules.startupStatusText(
            isRunningFromApplicationsFolder: true,
            statusDescription: "App not found — move to /Applications for login items"
        )

        XCTAssertTrue(text.contains("Running from /Applications"))
    }

    func testStartupStatusPassesThroughNormalStatus() {
        let text = StartupUIRules.startupStatusText(
            isRunningFromApplicationsFolder: true,
            statusDescription: "Enabled"
        )

        XCTAssertEqual(text, "Enabled")
    }

    func testVersionTextUsesBundleValues() {
        let info: [String: Any] = [
            "CFBundleShortVersionString": "1.0.2",
            "CFBundleVersion": "3",
        ]

        XCTAssertEqual(
            VersionDisplayFormatter.versionText(infoDictionary: info),
            "Version 1.0.2 (3)"
        )
    }

    func testVersionTextFallsBackWhenMissing() {
        XCTAssertEqual(
            VersionDisplayFormatter.versionText(infoDictionary: nil),
            "Version ? (?)"
        )
    }

    func testLegacyMigrationSkippedWhenPathsMatch() {
        let url = URL(fileURLWithPath: "/tmp/Magpie", isDirectory: true)

        XCTAssertFalse(
            LegacyDatabaseMigrationRules.shouldMigrate(
                targetDir: url,
                legacyDir: url,
                targetDatabaseExists: false,
                legacyDatabaseExists: true
            )
        )
    }

    func testLegacyMigrationSkippedWhenTargetAlreadyExists() {
        XCTAssertFalse(
            LegacyDatabaseMigrationRules.shouldMigrate(
                targetDir: URL(fileURLWithPath: "/target", isDirectory: true),
                legacyDir: URL(fileURLWithPath: "/legacy", isDirectory: true),
                targetDatabaseExists: true,
                legacyDatabaseExists: true
            )
        )
    }

    func testLegacyMigrationSkippedWhenLegacyMissing() {
        XCTAssertFalse(
            LegacyDatabaseMigrationRules.shouldMigrate(
                targetDir: URL(fileURLWithPath: "/target", isDirectory: true),
                legacyDir: URL(fileURLWithPath: "/legacy", isDirectory: true),
                targetDatabaseExists: false,
                legacyDatabaseExists: false
            )
        )
    }

    func testLegacyMigrationRunsWhenTargetMissingAndLegacyExists() {
        XCTAssertTrue(
            LegacyDatabaseMigrationRules.shouldMigrate(
                targetDir: URL(fileURLWithPath: "/target", isDirectory: true),
                legacyDir: URL(fileURLWithPath: "/legacy", isDirectory: true),
                targetDatabaseExists: false,
                legacyDatabaseExists: true
            )
        )
    }
}
