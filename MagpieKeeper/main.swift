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
              let applicationBundleID = Self.applicationBundleIdentifier(
                  applicationURL: applicationURL
              )
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
        let executableURL = resolvedExecutableURL()
        var candidate = executableURL.resolvingSymlinksInPath().deletingLastPathComponent()

        while candidate.path != "/" {
            if candidate.pathExtension == "app" {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }

        return nil
    }

    private static func resolvedExecutableURL() -> URL {
        // launchd may supply BundleProgram as a path relative to the parent
        // app. `_NSGetExecutablePath` always returns the executable image's
        // resolved filesystem path, independent of argv[0] and the working
        // directory.
        var bufferSize: UInt32 = 0
        _NSGetExecutablePath(nil, &bufferSize)
        var buffer = [CChar](repeating: 0, count: Int(bufferSize))
        let result = buffer.withUnsafeMutableBufferPointer { pointer in
            _NSGetExecutablePath(pointer.baseAddress, &bufferSize)
        }

        if result == 0 {
            return URL(fileURLWithPath: String(cString: buffer))
        }

        return URL(fileURLWithPath: CommandLine.arguments[0])
    }

    private static func applicationBundleIdentifier(applicationURL: URL) -> String? {
        // SMAppService launches the agent with XPC_SERVICE_NAME set to the
        // launchd label. Magpie's label is always <app bundle ID>.keeper.
        // This avoids reading the enclosing app's Info.plist, which the
        // helper's deliberately narrow sandbox does not permit.
        if let serviceName = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"],
           serviceName.hasSuffix(".keeper") {
            return String(serviceName.dropLast(".keeper".count))
        }

        // Keep direct development runs useful when the helper is unsigned
        // or otherwise not sandboxed.
        return Bundle(url: applicationURL)?.bundleIdentifier
    }

    private static func diagnosticDirectories(applicationBundleID: String) -> [URL] {
        KeeperDiagnosticDirectories.urls(
            homeDirectory: realUserHomeDirectory(),
            applicationBundleID: applicationBundleID
        )
    }

    /// App Sandbox remaps Foundation's home-directory APIs into the
    /// helper's container. launchd agents need the account's actual home
    /// in order to read Magpie's session markers through their explicit
    /// read-only sandbox exceptions.
    private static func realUserHomeDirectory() -> URL {
        guard let passwordEntry = getpwuid(getuid()),
              let homePath = passwordEntry.pointee.pw_dir
        else {
            return FileManager.default.homeDirectoryForCurrentUser
        }

        return URL(
            fileURLWithFileSystemRepresentation: homePath,
            isDirectory: true,
            relativeTo: nil
        )
    }
}

guard let keeper = MagpieKeeper() else {
    FileHandle.standardError.write(
        Data("MagpieKeeper must run from inside Magpie.app\n".utf8)
    )
    exit(EXIT_FAILURE)
}

keeper.run()
