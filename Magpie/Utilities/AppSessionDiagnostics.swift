import Darwin
import Foundation
#if canImport(MagpieKeeperCore)
import MagpieKeeperCore
#endif
import OSLog

/// Persists a small, content-free lifecycle trail so a future report can
/// distinguish a real process exit from a hidden UI or a stalled main thread.
/// Clipboard contents are never written here.
@MainActor
final class AppSessionDiagnostics {
    static let shared = AppSessionDiagnostics()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.magpie.app",
        category: "Lifecycle"
    )
    private let fileManager = FileManager.default
    private let stateURL: URL?
    private let quitMarkerURL: URL?
    private let logURL: URL?
    private var session: KeeperSessionState?

    private init() {
        let directory = try? fileManager
            .url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appendingPathComponent("Magpie", isDirectory: true)

        if let directory {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            stateURL = directory.appendingPathComponent(KeeperFileNames.sessionState)
            quitMarkerURL = directory.appendingPathComponent(KeeperFileNames.intentionalQuit)
            logURL = directory.appendingPathComponent("lifecycle.log")
        } else {
            stateURL = nil
            quitMarkerURL = nil
            logURL = nil
        }
    }

    func beginSession() {
        clearIntentionalQuitMarker()
        let previous = loadState()
        if SessionHealthRules.previousSessionEndedUnexpectedly(
            hasPreviousSession: previous != nil,
            endedCleanly: previous?.endedCleanly ?? true
        ), let previous {
            record(
                "previous_session_unclean id=\(previous.id.uuidString) "
                    + "last_heartbeat=\(Self.timestamp(previous.lastHeartbeatAt))"
            )
        }

        let now = Date()
        session = KeeperSessionState(
            id: UUID(),
            startedAt: now,
            lastHeartbeatAt: now,
            endedCleanly: false
        )
        persistState()

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "unknown"
        record("session_started version=\(version) build=\(build)")
    }

    func heartbeat() {
        guard session != nil else { return }
        session?.lastHeartbeatAt = Date()
        persistState()
    }

    func endSession() {
        guard session != nil else { return }
        session?.lastHeartbeatAt = Date()
        session?.endedCleanly = true
        persistState()
        record("session_ended_cleanly")
    }

    /// Suppresses watchdog recovery for an explicit Quit during this login
    /// session. A new login has a different audit session ID, so launch at
    /// login still works without requiring a persistent user preference.
    func markIntentionalQuit() {
        let marker = KeeperQuitMarker(
            auditSessionID: audit_session_self(),
            recordedAt: Date()
        )
        guard let quitMarkerURL,
              let data = try? JSONEncoder().encode(marker)
        else { return }

        do {
            try data.write(to: quitMarkerURL, options: .atomic)
            record("intentional_quit audit_session=\(marker.auditSessionID)")
        } catch {
            record("intentional_quit_marker_failed error=\(error.localizedDescription)")
        }
    }

    func record(_ event: String) {
        logger.notice("\(event, privacy: .public)")
        appendToLocalLog("\(Self.timestamp(Date())) \(event)\n")
    }

    private func loadState() -> KeeperSessionState? {
        guard let stateURL,
              let data = try? Data(contentsOf: stateURL)
        else { return nil }

        return try? JSONDecoder().decode(KeeperSessionState.self, from: data)
    }

    private func clearIntentionalQuitMarker() {
        guard let quitMarkerURL,
              fileManager.fileExists(atPath: quitMarkerURL.path)
        else { return }

        try? fileManager.removeItem(at: quitMarkerURL)
    }

    private func persistState() {
        guard let stateURL, let session,
              let data = try? JSONEncoder().encode(session)
        else { return }

        try? data.write(to: stateURL, options: .atomic)
    }

    private func appendToLocalLog(_ line: String) {
        guard let logURL, let lineData = line.data(using: .utf8) else { return }

        // Keep the diagnostic trail bounded. Preserve the newest half when
        // it reaches 512 KiB rather than allowing an unbounded support file.
        if let attributes = try? fileManager.attributesOfItem(atPath: logURL.path),
           let size = attributes[.size] as? NSNumber,
           size.intValue > 512 * 1024,
           let existing = try? Data(contentsOf: logURL) {
            try? Data(existing.suffix(256 * 1024)).write(to: logURL, options: .atomic)
        }

        if !fileManager.fileExists(atPath: logURL.path) {
            fileManager.createFile(atPath: logURL.path, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: lineData)
            try handle.close()
        } catch {
            try? handle.close()
        }
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
