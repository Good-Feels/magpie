import XCTest
import KeyboardShortcuts
import ServiceManagement
@testable import Magpie

final class RegressionGuardsTests: XCTestCase {
    func testLoginItemRepairRunsWhenDesiredAndRegistrationDropped() {
        XCTAssertTrue(
            LoginItemRepairRules.shouldAttemptRepair(desiredEnabled: true, status: .notRegistered)
        )
        XCTAssertTrue(
            LoginItemRepairRules.shouldAttemptRepair(desiredEnabled: true, status: .notFound)
        )
    }

    func testLoginItemRepairSkippedWhenAlreadyEnabledOrAwaitingApproval() {
        XCTAssertFalse(
            LoginItemRepairRules.shouldAttemptRepair(desiredEnabled: true, status: .enabled)
        )
        XCTAssertFalse(
            LoginItemRepairRules.shouldAttemptRepair(desiredEnabled: true, status: .requiresApproval)
        )
    }

    func testLoginItemRepairSkippedWhenUserNeverOptedIn() {
        XCTAssertFalse(
            LoginItemRepairRules.shouldAttemptRepair(desiredEnabled: false, status: .notRegistered)
        )
    }

    func testBackfillCapturesEnabledItemWithNoStoredPreference() {
        XCTAssertEqual(
            LoginItemRepairRules.backfillDesiredValue(storedDesired: nil, statusIsEnabled: true),
            true
        )
    }

    func testBackfillSkippedWhenPreferenceAlreadyStored() {
        XCTAssertNil(
            LoginItemRepairRules.backfillDesiredValue(storedDesired: false, statusIsEnabled: true)
        )
        XCTAssertNil(
            LoginItemRepairRules.backfillDesiredValue(storedDesired: true, statusIsEnabled: true)
        )
    }

    func testBackfillSkippedWhenItemNotEnabled() {
        XCTAssertNil(
            LoginItemRepairRules.backfillDesiredValue(storedDesired: nil, statusIsEnabled: false)
        )
    }

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

    func testShortcutHelperCopyIsNoLongerTemporary() {
        XCTAssertFalse(
            ShortcutSettingsCopy.helperText.localizedCaseInsensitiveContains("temporary fallback ui")
        )
    }

    func testShortcutValidationRequiresCapture() {
        XCTAssertEqual(
            ShortcutSettingsRules.validationMessage(for: nil),
            "Press a key combination."
        )
    }

    func testShortcutValidationRequiresModifierKey() {
        let shortcut = KeyboardShortcuts.Shortcut(.v, modifiers: [])

        XCTAssertEqual(
            ShortcutSettingsRules.validationMessage(for: shortcut),
            "Include at least one modifier key (\u{2318}, \u{2325}, \u{2303}, or \u{21e7})."
        )
    }

    func testShortcutValidationAcceptsCommandShortcut() {
        let shortcut = KeyboardShortcuts.Shortcut(.v, modifiers: [.command, .shift])

        XCTAssertNil(
            ShortcutSettingsRules.validationMessage(for: shortcut)
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

    func testAnalyticsQueryLengthBuckets() {
        XCTAssertEqual(AnalyticsBuckets.queryLengthBucket(for: 0), "0")
        XCTAssertEqual(AnalyticsBuckets.queryLengthBucket(for: 3), "1-3")
        XCTAssertEqual(AnalyticsBuckets.queryLengthBucket(for: 8), "4-8")
        XCTAssertEqual(AnalyticsBuckets.queryLengthBucket(for: 9), "9+")
    }

    func testAnalyticsResultCountBuckets() {
        XCTAssertEqual(AnalyticsBuckets.resultCountBucket(for: 0), "0")
        XCTAssertEqual(AnalyticsBuckets.resultCountBucket(for: 5), "1-5")
        XCTAssertEqual(AnalyticsBuckets.resultCountBucket(for: 20), "6-20")
        XCTAssertEqual(AnalyticsBuckets.resultCountBucket(for: 21), "21+")
    }

    // MARK: - Launch-at-login orchestration

    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "MagpieTests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @MainActor
    func testHealRepairsDroppedRegistrationWhenUserOptedIn() {
        let control = FakeLoginItemControl(status: .notRegistered)
        let defaults = makeDefaults()
        defaults.set(true, forKey: LaunchAtLoginService.desiredEnabledKey)

        let service = LaunchAtLoginService(control: control, defaults: defaults)
        let repaired = service.healRegistrationIfNeeded()

        XCTAssertTrue(repaired)
        XCTAssertEqual(control.registerCallCount, 1)
    }

    @MainActor
    func testHealDoesNothingWhenUserNeverOptedIn() {
        let control = FakeLoginItemControl(status: .notRegistered)
        let defaults = makeDefaults()

        let service = LaunchAtLoginService(control: control, defaults: defaults)
        let repaired = service.healRegistrationIfNeeded()

        XCTAssertFalse(repaired)
        XCTAssertEqual(control.registerCallCount, 0)
    }

    @MainActor
    func testHealBackfillsPreferenceForLegacyEnabledUser() {
        // Enabled item, but the user is on a build that never persisted the
        // choice. Heal should capture intent without re-registering.
        let control = FakeLoginItemControl(status: .enabled)
        let defaults = makeDefaults()

        let service = LaunchAtLoginService(control: control, defaults: defaults)
        let repaired = service.healRegistrationIfNeeded()

        XCTAssertFalse(repaired)
        XCTAssertEqual(control.registerCallCount, 0)
        XCTAssertTrue(defaults.bool(forKey: LaunchAtLoginService.desiredEnabledKey))
    }

    @MainActor
    func testSetLoginItemPersistsChoiceOnSuccess() {
        let control = FakeLoginItemControl(status: .notRegistered)
        let defaults = makeDefaults()
        let service = LaunchAtLoginService(control: control, defaults: defaults)

        service.setLoginItem(enabled: true)

        XCTAssertEqual(control.registerCallCount, 1)
        XCTAssertTrue(defaults.bool(forKey: LaunchAtLoginService.desiredEnabledKey))
    }

    @MainActor
    func testSetLoginItemRevertsAndDoesNotPersistOnFailure() {
        let control = FakeLoginItemControl(status: .notRegistered)
        control.registerError = TestError.boom
        let defaults = makeDefaults()
        let service = LaunchAtLoginService(control: control, defaults: defaults)

        service.setLoginItem(enabled: true)

        XCTAssertFalse(service.isEnabled)
        XCTAssertNil(defaults.object(forKey: LaunchAtLoginService.desiredEnabledKey))
    }
}

private enum TestError: Error { case boom }

private final class FakeLoginItemControl: LoginItemControlling {
    var status: SMAppService.Status
    var registerCallCount = 0
    var unregisterCallCount = 0
    var registerError: Error?
    var unregisterError: Error?

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }
}
