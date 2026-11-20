import Foundation
import XCTest
@testable import Magpie

final class UpdateNoticeTests: XCTestCase {
    func testMAG009ExistingInstallGetsTheMCPTipOnce() throws {
        try withDefaults { defaults in
            let notice = try XCTUnwrap(UpdateNotice.forLaunch(
                version: "1.0.21", onboardingComplete: true, defaults: defaults
            ))
            XCTAssertEqual(notice.title, "What’s New in Magpie 1.0.21")
            XCTAssertEqual(notice.action, .openMCPSettings)
            XCTAssertTrue(notice.summary.contains("Allow access to clipboard history"))
            XCTAssertNil(UpdateNotice.forLaunch(version: "1.0.21", onboardingComplete: true, defaults: defaults))
            XCTAssertFalse(defaults.bool(forKey: "mcpClipboardHistoryAccess"))
        }
    }

    func testMAG009FreshInstallUsesOnboardingAndSkipsNoticeForSameVersion() throws {
        try withDefaults { defaults in
            XCTAssertNil(UpdateNotice.forLaunch(version: "1.0.21", onboardingComplete: false, defaults: defaults))
            XCTAssertNil(UpdateNotice.forLaunch(version: "1.0.21", onboardingComplete: true, defaults: defaults))
            XCTAssertEqual(
                UpdateNotice.forLaunch(version: "1.0.22", onboardingComplete: true, defaults: defaults)?.action,
                .viewReleaseNotes
            )
        }
    }

    func testMAG009UpgradeSummarizesCurrentReleaseAndDowngradeDoesNotReplayIt() throws {
        try withDefaults { defaults in
            XCTAssertNil(UpdateNotice.forLaunch(version: "1.0.9", onboardingComplete: true, defaults: defaults))
            XCTAssertEqual(
                UpdateNotice.forLaunch(version: "1.0.22", onboardingComplete: true, defaults: defaults)?.action,
                .openMCPSettings
            )
            let notice = try XCTUnwrap(UpdateNotice.forLaunch(
                version: "1.0.100", onboardingComplete: true, defaults: defaults,
                releaseNotes: "# Magpie 1.0.100\n\nFind **older clips** more quickly.\nOne more detail.\n\nOther changes."
            ))
            XCTAssertEqual(notice.action, .viewReleaseNotes)
            XCTAssertEqual(notice.summary, "Find **older clips** more quickly. One more detail.")
            XCTAssertEqual(notice.releaseNotesURL.lastPathComponent, "v1.0.100")
            XCTAssertNil(UpdateNotice.forLaunch(version: "1.0.22", onboardingComplete: true, defaults: defaults))
            XCTAssertNil(UpdateNotice.forLaunch(version: "1.0.100", onboardingComplete: true, defaults: defaults))
            XCTAssertEqual(
                UpdateNotice.forLaunch(version: "1.0.101", onboardingComplete: true, defaults: defaults)?.summary,
                "Read the release notes to see what changed in this update."
            )
        }
    }

    private func withDefaults(_ test: (UserDefaults) throws -> Void) throws {
        let suite = "magpie-update-notice-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try test(defaults)
    }
}
