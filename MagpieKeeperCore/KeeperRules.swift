import Foundation

public enum KeeperFileNames {
    public static let sessionState = "session-state.json"
    public static let intentionalQuit = "intentional-quit.json"
}

public enum KeeperDiagnosticDirectories {
    /// Returns the session-state location used by the sandboxed main app.
    /// `homeDirectory` must be the user's real POSIX home, not App
    /// Sandbox's remapped home directory.
    public static func urls(
        homeDirectory: URL,
        applicationBundleID: String
    ) -> [URL] {
        return [
            homeDirectory
                .appendingPathComponent("Library/Containers", isDirectory: true)
                .appendingPathComponent(applicationBundleID, isDirectory: true)
                .appendingPathComponent("Data", isDirectory: true)
                .appendingPathComponent(
                    "Library/Application Support/Magpie",
                    isDirectory: true
                ),
        ]
    }
}

public struct KeeperSessionState: Codable, Equatable {
    public let id: UUID
    public let startedAt: Date
    public var lastHeartbeatAt: Date
    public var endedCleanly: Bool

    public init(
        id: UUID,
        startedAt: Date,
        lastHeartbeatAt: Date,
        endedCleanly: Bool
    ) {
        self.id = id
        self.startedAt = startedAt
        self.lastHeartbeatAt = lastHeartbeatAt
        self.endedCleanly = endedCleanly
    }
}

public struct KeeperQuitMarker: Codable, Equatable {
    public let auditSessionID: UInt32
    public let recordedAt: Date

    public init(auditSessionID: UInt32, recordedAt: Date) {
        self.auditSessionID = auditSessionID
        self.recordedAt = recordedAt
    }
}

public enum KeeperDecision: Equatable {
    case appAlreadyRunning
    case suppressIntentionalQuit
    case waitAfterCleanTermination(until: Date)
    case relaunch
}

public enum KeeperRules {
    /// Gives Sparkle and move-to-Applications flows time to replace and
    /// reopen the main bundle without a watchdog racing the installer.
    public static let cleanTerminationGraceInterval: TimeInterval = 120

    public static func decision(
        appIsRunning: Bool,
        sessionState: KeeperSessionState?,
        quitMarker: KeeperQuitMarker?,
        currentAuditSessionID: UInt32,
        now: Date
    ) -> KeeperDecision {
        if appIsRunning {
            return .appAlreadyRunning
        }

        if quitMarker?.auditSessionID == currentAuditSessionID {
            return .suppressIntentionalQuit
        }

        if let sessionState, sessionState.endedCleanly {
            let elapsed = now.timeIntervalSince(sessionState.lastHeartbeatAt)
            if elapsed >= 0, elapsed < cleanTerminationGraceInterval {
                return .waitAfterCleanTermination(
                    until: sessionState.lastHeartbeatAt
                        .addingTimeInterval(cleanTerminationGraceInterval)
                )
            }
        }

        return .relaunch
    }

    public static func retryDelay(afterFailureCount failureCount: Int) -> TimeInterval {
        let boundedFailureCount = max(1, min(failureCount, 6))
        return min(60, pow(2, Double(boundedFailureCount)))
    }
}
