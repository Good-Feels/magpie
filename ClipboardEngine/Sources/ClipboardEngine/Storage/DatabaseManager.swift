import Foundation
import GRDB

/// Manages the SQLite database lifecycle: connection pool, schema migrations,
/// and database location.
///
/// The database lives at:
///   `~/Library/Application Support/Magpie/clipboard.sqlite`
///
/// Uses GRDB's `DatabasePool` (WAL mode) for concurrent read/write safety
/// and crash resilience.
public final class DatabaseManager: Sendable {
    /// The GRDB connection pool – all repositories read/write through this.
    public let dbPool: DatabasePool

    // MARK: - Initialisation

    /// Creates the database at the standard Application Support location.
    /// Runs all pending migrations automatically.
    public init() throws {
        let appSupportURL = try FileManager.default
            .url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appendingPathComponent("Magpie", isDirectory: true)

        try FileManager.default.createDirectory(
            at: appSupportURL,
            withIntermediateDirectories: true
        )

        let dbPath = appSupportURL
            .appendingPathComponent("clipboard.sqlite")
            .path

        // Restrict directory and database file to owner-only access (0700/0600)
        // to protect clipboard history from other user accounts on the system.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: appSupportURL.path
        )

        dbPool = try DatabasePool(path: dbPath)
        try migrator.migrate(dbPool)

        // Lock down DB files after creation (SQLite also creates -wal and -shm)
        Self.restrictFilePermissions(at: dbPath)
    }

    /// Creates a database manager with a custom DatabasePool
    /// (useful for testing with in-memory databases).
    public init(dbPool: DatabasePool) throws {
        self.dbPool = dbPool
        try migrator.migrate(dbPool)
    }

    // MARK: - File Protection

    /// Sets owner-only (0600) permissions on the database file and its
    /// WAL/SHM companions to prevent other accounts from reading clipboard data.
    private static func restrictFilePermissions(at dbPath: String) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let path = dbPath + suffix
            if fm.fileExists(atPath: path) {
                try? fm.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: path
                )
            }
        }
    }

    // MARK: - Migrations

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // ── v1: Initial schema ──────────────────────────────────────────
        migrator.registerMigration("v1_createClipItems") { db in
            try db.create(table: "clipItems") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("contentText", .text)
                t.column("contentRichData", .blob)
                t.column("contentImageData", .blob)
                t.column("contentFilePath", .text)
                t.column("contentType", .text).notNull().defaults(to: "text")
                t.column("sourceAppBundleID", .text)
                t.column("sourceAppName", .text)
                t.column("isPinned", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("previewText", .text)
            }

            // Index for the default sort order: pinned first, then newest.
            try db.create(
                index: "idx_clipItems_pinned_created",
                on: "clipItems",
                columns: ["isPinned", "createdAt"]
            )
        }

        return migrator
    }
}
