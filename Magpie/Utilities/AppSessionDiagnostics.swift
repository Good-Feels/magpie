import Foundation
import OSLog

/// Persists a small, content-free lifecycle trail so a future report can
/// distinguish a real process exit from a hidden UI or a stalled main thread.
/// Clipboard contents are never written here.
@MainActor
final class AppSessionDiagnostics {
    static let shared = AppSessionDiagnostics()

    private struct SessionState: Codable {
        let id: UUID
        let startedAt: Date
        var lastHeartbeatAt: Date
        var endedCleanly: Bool
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.magpie.app",
        category: "Lifecycle"
    )
    private let fileManager = FileManager.default
    private let stateURL: URL?
    private let logURL: URL?
    private var session: SessionState?

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
            stateURL = directory.appendingPathComponent("session-state.json")
            logURL = directory.appendingPathComponent("lifecycle.log")
        } else {
            stateURL = nil
            logURL = nil
        }
    }

    func beginSession() {
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
        session = SessionState(
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

    func record(_ event: String) {
        logger.notice("\(event, privacy: .public)")
        appendToLocalLog("\(Self.timestamp(Date())) \(event)\n")
    }

    private func loadState() -> SessionState? {
        guard let stateURL,
              let data = try? Data(contentsOf: stateURL)
        else { return nil }

        return try? JSONDecoder().decode(SessionState.self, from: data)
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
