import AppKit
import Darwin
import Foundation
#if canImport(MagpieKeeperCore)
import MagpieKeeperCore
#endif
import OSLog

private final class MagpieKeeper {
    private static let checkInterval: TimeInterval = 2
    private static let launchRegistrationDelay: TimeInterval = 15

    private let applicationURL: URL
    private let applicationBundleID: String
    private let diagnosticDirectories: [URL]
    private let logger: Logger
    private let currentAuditSessionID = audit_session_self()

    private var timer: Timer?
    private var launchInFlight = false
    private var launchFailureCount = 0
    private var nextEligibleLaunchAt = Date.distantPast
    private var lastLoggedDecision: KeeperDecision?

    init?() {
        guard let applicationURL = Self.containingApplicationURL(),
              let bundle = Bundle(url: applicationURL),
              let applicationBundleID = bundle.bundleIdentifier
        else {
            return nil
        }

        self.applicationURL = applicationURL
        self.applicationBundleID = applicationBundleID
        diagnosticDirectories = Self.diagnosticDirectories(
            applicationBundleID: applicationBundleID
        )
        logger = Logger(subsystem: "\(applicationBundleID).keeper", category: "Recovery")
    }

    func run() {
        logger.notice(
            "keeper_started app=\(self.applicationURL.path, privacy: .public) audit_session=\(self.currentAuditSessionID)"
        )
        evaluate()
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.checkInterval,
            repeats: true
        ) { [weak self] _ in
            self?.evaluate()
        }
        timer?.tolerance = 0.5
        RunLoop.main.run()
    }

    private func evaluate() {
        let now = Date()
        let appIsRunning = !NSRunningApplication.runningApplications(
            withBundleIdentifier: applicationBundleID
        ).isEmpty
        let decision = KeeperRules.decision(
            appIsRunning: appIsRunning,
            sessionState: newestSessionState(),
            quitMarker: newestQuitMarker(),
            currentAuditSessionID: currentAuditSessionID,
            now: now
        )

        if decision != lastLoggedDecision {
            log(decision)
            lastLoggedDecision = decision
        }

        if appIsRunning {
            launchFailureCount = 0
            nextEligibleLaunchAt = .distantPast
            return
        }

        guard decision == .relaunch,
              !launchInFlight,
              now >= nextEligibleLaunchAt
        else { return }

        launchApplication()
    }

    private func launchApplication() {
        launchInFlight = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false

        logger.notice("relaunch_requested")
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        ) { [weak self] application, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.launchInFlight = false

                if let error {
                    self.launchFailureCount += 1
                    let delay = KeeperRules.retryDelay(
                        afterFailureCount: self.launchFailureCount
                    )
                    self.nextEligibleLaunchAt = Date().addingTimeInterval(delay)
                    self.logger.error(
                        "relaunch_failed retry_in=\(delay) error=\(error.localizedDescription, privacy: .public)"
                    )
                    return
                }

                self.launchFailureCount = 0
                self.nextEligibleLaunchAt = Date().addingTimeInterval(
                    Self.launchRegistrationDelay
                )
                self.logger.notice(
                    "relaunch_succeeded pid=\(application?.processIdentifier ?? 0)"
                )
            }
        }
    }

    private func newestSessionState() -> KeeperSessionState? {
        newestDecodedValue(
            named: KeeperFileNames.sessionState,
            as: KeeperSessionState.self,
            orderedBy: \KeeperSessionState.startedAt
        )
    }

    private func newestQuitMarker() -> KeeperQuitMarker? {
        newestDecodedValue(
            named: KeeperFileNames.intentionalQuit,
            as: KeeperQuitMarker.self,
            orderedBy: \KeeperQuitMarker.recordedAt
        )
    }

    private func newestDecodedValue<Value: Decodable, Order: Comparable>(
        named fileName: String,
        as type: Value.Type,
        orderedBy keyPath: KeyPath<Value, Order>
    ) -> Value? {
        diagnosticDirectories.compactMap { directory -> Value? in
            let url = directory.appendingPathComponent(fileName)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
        .max { lhs, rhs in
            lhs[keyPath: keyPath] < rhs[keyPath: keyPath]
        }
    }

    private func log(_ decision: KeeperDecision) {
        switch decision {
        case .appAlreadyRunning:
            logger.debug("app_running")
        case .suppressIntentionalQuit:
            logger.notice("relaunch_suppressed reason=intentional_quit")
        case .waitAfterCleanTermination(let date):
            logger.notice(
                "relaunch_delayed reason=clean_termination until=\(date.timeIntervalSince1970)"
            )
        case .relaunch:
            logger.notice("app_missing relaunch_eligible=true")
        }
    }

    private static func containingApplicationURL() -> URL? {
        let executableURL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0])
        var candidate = executableURL.resolvingSymlinksInPath().deletingLastPathComponent()

        while candidate.path != "/" {
            if candidate.pathExtension == "app",
               FileManager.default.fileExists(
                   atPath: candidate
                       .appendingPathComponent("Contents/Info.plist")
                       .path
               ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }

        return nil
    }

    private static func diagnosticDirectories(applicationBundleID: String) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let relativeSupportPath = "Library/Application Support/Magpie"
        return [
            home
                .appendingPathComponent("Library/Containers", isDirectory: true)
                .appendingPathComponent(applicationBundleID, isDirectory: true)
                .appendingPathComponent("Data", isDirectory: true)
                .appendingPathComponent(relativeSupportPath, isDirectory: true),
            home.appendingPathComponent(relativeSupportPath, isDirectory: true),
        ]
    }
}

guard let keeper = MagpieKeeper() else {
    FileHandle.standardError.write(
        Data("MagpieKeeper must run from inside Magpie.app\n".utf8)
    )
    exit(EXIT_FAILURE)
}

keeper.run()
