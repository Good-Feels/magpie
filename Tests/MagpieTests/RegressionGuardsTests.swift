import XCTest
import KeyboardShortcuts
import ServiceManagement
@testable import Magpie

final class RegressionGuardsTests: XCTestCase {
    func testLoginItemRepairRunsWhenDesiredAndRegistrationDropped() {
        XCTAssertTrue(
            LoginItemRepairRules.shouldAttemptRepair(
                desiredEnabled: true,
                status: .notRegistered,
                alreadyRepairedInThisEnvironment: false
            )
        )
        XCTAssertTrue(
            LoginItemRepairRules.shouldAttemptRepair(
                desiredEnabled: true,
                status: .notFound,
                alreadyRepairedInThisEnvironment: false
            )
        )
    }

    func testLoginItemRepairSkippedWhenAlreadyEnabledOrAwaitingApproval() {
        XCTAssertFalse(
            LoginItemRepairRules.shouldAttemptRepair(
                desiredEnabled: true,
                status: .enabled,
                alreadyRepairedInThisEnvironment: false
            )
        )
        XCTAssertFalse(
            LoginItemRepairRules.shouldAttemptRepair(
                desiredEnabled: true,
                status: .requiresApproval,
                alreadyRepairedInThisEnvironment: false
            )
        )
    }

    func testLoginItemRepairSkippedWhenUserNeverOptedIn() {
        XCTAssertFalse(
            LoginItemRepairRules.shouldAttemptRepair(
                desiredEnabled: false,
                status: .notRegistered,
                alreadyRepairedInThisEnvironment: false
            )
        )
    }

    func testLoginItemRepairRespectsUserRemovalInSameEnvironment() {
        // Same (build, OS) environment already repaired once — a second
        // drop means the user removed it in System Settings; don't fight.
        XCTAssertFalse(
            LoginItemRepairRules.shouldAttemptRepair(
                desiredEnabled: true,
                status: .notRegistered,
                alreadyRepairedInThisEnvironment: true
            )
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

    func testManualDownloadOfferedOnlyForUserInitiatedRealFailures() {
        let realFailure = 1002 // SUAppcastError

        XCTAssertTrue(
            UpdateFailureRules.shouldOfferManualDownload(
                errorDomain: "SUSparkleErrorDomain",
                errorCode: realFailure,
                userInitiated: true
            )
        )
        // Background scheduled check failing (offline laptop) — silent.
        XCTAssertFalse(
            UpdateFailureRules.shouldOfferManualDownload(
                errorDomain: "SUSparkleErrorDomain",
                errorCode: realFailure,
                userInitiated: false
            )
        )
    }

    func testManualDownloadNotOfferedForRoutineAborts() {
        let noUpdateFound = 1001 // SUNoUpdateError
        let userCanceled = 4007  // SUInstallationCanceledError

        XCTAssertFalse(
            UpdateFailureRules.shouldOfferManualDownload(
                errorDomain: "SUSparkleErrorDomain",
                errorCode: noUpdateFound,
                userInitiated: true
            )
        )
        XCTAssertFalse(
            UpdateFailureRules.shouldOfferManualDownload(
                errorDomain: "SUSparkleErrorDomain",
                errorCode: userCanceled,
                userInitiated: true
            )
        )
    }

    func testManualDownloadNotOfferedForNonSparkleErrors() {
        XCTAssertFalse(
            UpdateFailureRules.shouldOfferManualDownload(
                errorDomain: "NSURLErrorDomain",
                errorCode: -1009,
                userInitiated: true
            )
        )
    }

    func testStatusItemEvictedWhenPushedOffAllScreens() {
        let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982)]
        // macOS parks evicted status items far outside the screen bounds.
        let evictedFrame = CGRect(x: 20000, y: 960, width: 24, height: 22)

        XCTAssertTrue(
            StatusItemVisibilityRules.isConfidentlyEvicted(
                buttonWindowFrame: evictedFrame,
                screenFrames: screens
            )
        )
    }

    func testStatusItemNotEvictedWhenOnScreenEvenIfOccluded() {
        // Locked screen / fullscreen app / auto-hidden menu bar: the item
        // stays inside the screen frame, so no "menu bar full" warning.
        let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982)]
        let onScreenFrame = CGRect(x: 1200, y: 960, width: 24, height: 22)

        XCTAssertFalse(
            StatusItemVisibilityRules.isConfidentlyEvicted(
                buttonWindowFrame: onScreenFrame,
                screenFrames: screens
            )
        )
    }

    func testHiddenStatusItemAlertRendersLiveShortcut() {
        let body = HiddenStatusItemCopy.alertBody(shortcutText: "⌃⌥C")

        XCTAssertTrue(body.contains("⌃⌥C"))
        XCTAssertFalse(body.contains("⌘⇧V"))
    }

    func testHiddenStatusItemAlertHandlesClearedShortcut() {
        let body = HiddenStatusItemCopy.alertBody(shortcutText: nil)

        XCTAssertFalse(body.contains("⌘⇧V"))
        XCTAssertTrue(body.localizedCaseInsensitiveContains("settings"))
    }

    // MARK: - Keyboard layout

    func testDefaultShortcutTypesVOnCurrentLayout() {
        // The default must follow the key that TYPES "v" — on Dvorak the
        // physical QWERTY-V position types "k", so a position-based
        // default advertises a hotkey that doesn't exist.
        let label = String(describing: KeyboardShortcuts.Shortcut.layoutAwareDefault)

        XCTAssertTrue(
            label.hasSuffix("V"),
            "Layout-aware default should render as ⌘⇧V on every layout, got \(label)"
        )
    }

    func testKeyCodeLookupRoundTrips() {
        let code = KeyboardLayoutResolver.keyCode(forCharacter: "v")

        XCTAssertNotNil(code, "Every Latin layout has a key that types 'v'")
    }

    func testLegacyShortcutMigratesOnlyWhenItIsTheStoredDefault() {
        let legacy = KeyboardShortcuts.Shortcut(.v, modifiers: [.command, .shift])
        let layoutAware = KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .shift])
        let custom = KeyboardShortcuts.Shortcut(.c, modifiers: [.command, .option])

        // Stored legacy default on a layout where "v" moved → migrate.
        XCTAssertTrue(
            ShortcutLayoutRules.shouldMigrateStoredShortcut(
                stored: legacy, legacyDefault: legacy, layoutAwareDefault: layoutAware
            )
        )
        // User customized their shortcut → never touch it.
        XCTAssertFalse(
            ShortcutLayoutRules.shouldMigrateStoredShortcut(
                stored: custom, legacyDefault: legacy, layoutAwareDefault: layoutAware
            )
        )
        // QWERTY (layout-aware == legacy) → nothing to migrate.
        XCTAssertFalse(
            ShortcutLayoutRules.shouldMigrateStoredShortcut(
                stored: legacy, legacyDefault: legacy, layoutAwareDefault: legacy
            )
        )
        // Nothing stored → the Name default applies on its own.
        XCTAssertFalse(
            ShortcutLayoutRules.shouldMigrateStoredShortcut(
                stored: nil, legacyDefault: legacy, layoutAwareDefault: layoutAware
            )
        )
    }

    func testFallbackPopoverAnchorSitsAtTopCenterOfScreen() {
        // Hotkey with a hidden status item must anchor the popover
        // on-screen, not to the off-screen status item window.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 950)

        let anchor = PopoverAnchorRules.fallbackAnchorRect(visibleFrame: screen)

        XCTAssertTrue(screen.contains(anchor), "Anchor must be on-screen")
        XCTAssertEqual(anchor.midX, screen.midX, accuracy: 1)
        XCTAssertEqual(anchor.maxY, screen.maxY, accuracy: 1)
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

    @MainActor
    func testDisableWinsEvenWhenUnregisterThrows() {
        // A stale .notFound registration mustn't trap the user with a
        // toggle that snaps back on and a heal loop that re-registers.
        let control = FakeLoginItemControl(status: .notFound)
        control.unregisterError = TestError.boom
        let defaults = makeDefaults()
        defaults.set(true, forKey: LaunchAtLoginService.desiredEnabledKey)
        let service = LaunchAtLoginService(control: control, defaults: defaults)

        service.setLoginItem(enabled: false)

        XCTAssertEqual(
            defaults.object(forKey: LaunchAtLoginService.desiredEnabledKey) as? Bool,
            false
        )
        XCTAssertFalse(service.isEnabled)
    }

    @MainActor
    func testHealRepairsOnlyOncePerEnvironment() {
        let control = FakeLoginItemControl(status: .notRegistered)
        let defaults = makeDefaults()
        defaults.set(true, forKey: LaunchAtLoginService.desiredEnabledKey)
        let service = LaunchAtLoginService(control: control, defaults: defaults)

        XCTAssertTrue(service.healRegistrationIfNeeded())

        // User removes Magpie in System Settings > Login Items; the next
        // launch in the same (build, OS) environment must respect that.
        control.status = .notRegistered
        XCTAssertFalse(service.healRegistrationIfNeeded())
        XCTAssertEqual(control.registerCallCount, 1)
    }

    @MainActor
    func testExplicitReenableResetsRepairBudget() {
        let control = FakeLoginItemControl(status: .notRegistered)
        let defaults = makeDefaults()
        defaults.set(true, forKey: LaunchAtLoginService.desiredEnabledKey)
        let service = LaunchAtLoginService(control: control, defaults: defaults)

        service.healRegistrationIfNeeded()      // consumes the repair budget
        service.setLoginItem(enabled: true)     // fresh explicit opt-in

        control.status = .notRegistered         // macOS drops it again
        XCTAssertTrue(service.healRegistrationIfNeeded())
    }

    @MainActor
    func testRefreshStatusPublishesExternalApproval() {
        // User approves the item in System Settings and switches back —
        // the requires-approval notice must clear.
        let control = FakeLoginItemControl(status: .requiresApproval)
        let service = LaunchAtLoginService(control: control, defaults: makeDefaults())
        XCTAssertTrue(service.requiresApproval)

        control.status = .enabled
        service.refreshStatus()

        XCTAssertFalse(service.requiresApproval)
        XCTAssertEqual(service.statusDescription, "Enabled")
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
