import Foundation
import XCTest
@testable import MagpieKeeperCore

final class KeeperRulesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRunningApplicationNeverRelaunches() {
        XCTAssertEqual(
            decision(appIsRunning: true, sessionState: nil),
            .appAlreadyRunning
        )
    }

    func testUncleanExitRelaunchesImmediately() {
        XCTAssertEqual(
            decision(
                sessionState: state(endedCleanly: false, heartbeatAge: 1)
            ),
            .relaunch
        )
    }

    func testMissingStateRelaunchesImmediately() {
        XCTAssertEqual(decision(sessionState: nil), .relaunch)
    }

    func testIntentionalQuitInCurrentLoginSessionIsRespected() {
        let marker = KeeperQuitMarker(auditSessionID: 42, recordedAt: now)

        XCTAssertEqual(
            decision(
                sessionState: state(endedCleanly: true, heartbeatAge: 500),
                quitMarker: marker,
                auditSessionID: 42
            ),
            .suppressIntentionalQuit
        )
    }

    func testIntentionalQuitFromPriorLoginDoesNotSuppressRelaunch() {
        let marker = KeeperQuitMarker(auditSessionID: 41, recordedAt: now)

        XCTAssertEqual(
            decision(
                sessionState: state(endedCleanly: true, heartbeatAge: 500),
                quitMarker: marker,
                auditSessionID: 42
            ),
            .relaunch
        )
    }

    func testRecentCleanTerminationWaitsForUpdater() {
        let session = state(endedCleanly: true, heartbeatAge: 20)

        XCTAssertEqual(
            decision(sessionState: session),
            .waitAfterCleanTermination(
                until: session.lastHeartbeatAt.addingTimeInterval(
                    KeeperRules.cleanTerminationGraceInterval
                )
            )
        )
    }

    func testStaleCleanTerminationRelaunches() {
        XCTAssertEqual(
            decision(
                sessionState: state(
                    endedCleanly: true,
                    heartbeatAge: KeeperRules.cleanTerminationGraceInterval + 1
                )
            ),
            .relaunch
        )
    }

    func testRetryDelayBacksOffAndCapsAtOneMinute() {
        XCTAssertEqual(KeeperRules.retryDelay(afterFailureCount: 1), 2)
        XCTAssertEqual(KeeperRules.retryDelay(afterFailureCount: 3), 8)
        XCTAssertEqual(KeeperRules.retryDelay(afterFailureCount: 99), 60)
    }

    private func decision(
        appIsRunning: Bool = false,
        sessionState: KeeperSessionState?,
        quitMarker: KeeperQuitMarker? = nil,
        auditSessionID: UInt32 = 42
    ) -> KeeperDecision {
        KeeperRules.decision(
            appIsRunning: appIsRunning,
            sessionState: sessionState,
            quitMarker: quitMarker,
            currentAuditSessionID: auditSessionID,
            now: now
        )
    }

    private func state(
        endedCleanly: Bool,
        heartbeatAge: TimeInterval
    ) -> KeeperSessionState {
        KeeperSessionState(
            id: UUID(),
            startedAt: now.addingTimeInterval(-1_000),
            lastHeartbeatAt: now.addingTimeInterval(-heartbeatAge),
            endedCleanly: endedCleanly
        )
    }
}
