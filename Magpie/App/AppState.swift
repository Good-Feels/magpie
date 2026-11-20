import SwiftUI
import AppKit
import Combine
import ClipboardEngine

/// Central app coordinator. Owns the database, clipboard monitor,
/// repository, and exclusion manager. Exposes published state for SwiftUI views.
@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State

    /// The full list of clips from the database.
    @Published var clips: [ClipItem] = []

    /// The clips currently displayed (filtered by search when active).
    @Published var displayedClips: [ClipItem] = []

    /// The current search query typed in the search bar.
    @Published var searchText: String = "" {
        didSet { updateDisplayedClips() }
    }

    /// Set to the ID of a clip that was just copied — drives the "Copied!" animation.
    @Published var copiedItemID: Int64?

    /// Callback set by AppDelegate to dismiss the popover.
    var onDismiss: (() -> Void)?

    /// Callback set by AppDelegate to open the settings window.
    var onOpenSettings: (() -> Void)?

    /// True when the database failed to initialise and the app is running
    /// with saving paused. Existing history is never automatically reset.
    @Published var databaseError: String?

    // MARK: - Dependencies

    private let analytics = AnalyticsService.shared
    private(set) var databaseManager: DatabaseManager?
    private(set) var repository: ClipItemRepository?
    let monitor: ClipboardMonitor
    let exclusionManager: ExclusionListManager
    let accessChecker: ClipboardAccessChecker
    let mcpSharing = MCPSharing()
    private var hasTrackedCurrentSearch = false

    // MARK: - Init

    init() {
        monitor = ClipboardMonitor(pollInterval: 0.5)
        exclusionManager = ExclusionListManager()
        accessChecker = ClipboardAccessChecker()
        Self.migrateLegacyDatabaseIfNeeded()

        switch DatabaseStartup.open(defaults: .standard, makeDatabase: { try DatabaseManager() }) {
        case .success(let dbManager):
            databaseManager = dbManager
            repository = ClipItemRepository(dbPool: dbManager.dbPool)
        case .failure(let error):
            // Opening/migration/permissions errors do not prove that history is
            // unrecoverable. Preserve all database/WAL files for a later retry.
            print("[Magpie] Database unavailable; preserving history: \(error)")
            databaseError = error.localizedDescription
        }

        loadClips()
    }

    /// One-time migration for users moving from a non-sandbox build
    /// (`~/Library/Application Support/Magpie`) to sandboxed container storage.
    /// If the target DB already exists, migration is skipped.
    private static func migrateLegacyDatabaseIfNeeded() {
        let fm = FileManager.default
        do {
            let targetDir = try fm
                .url(for: .applicationSupportDirectory, in: .userDomainMask,
                     appropriateFor: nil, create: true)
                .appendingPathComponent("Magpie", isDirectory: true)

            let legacyDir = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support/Magpie", isDirectory: true)

            // Non-sandbox builds already use this location; nothing to migrate.
            if targetDir.standardizedFileURL == legacyDir.standardizedFileURL {
                return
            }

            let targetDB = targetDir.appendingPathComponent("clipboard.sqlite")
            let legacyDB = legacyDir.appendingPathComponent("clipboard.sqlite")
            let shouldMigrate = LegacyDatabaseMigrationRules.shouldMigrate(
                targetDir: targetDir,
                legacyDir: legacyDir,
                targetDatabaseExists: fm.fileExists(atPath: targetDB.path),
                legacyDatabaseExists: fm.fileExists(atPath: legacyDB.path)
            )
            if !shouldMigrate {
                return
            }

            try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

            for suffix in LegacyDatabaseMigrationRules.suffixes {
                let from = legacyDir.appendingPathComponent("\(LegacyDatabaseMigrationRules.databaseBaseName)\(suffix)")
                let to = targetDir.appendingPathComponent("\(LegacyDatabaseMigrationRules.databaseBaseName)\(suffix)")
                if fm.fileExists(atPath: from.path) && !fm.fileExists(atPath: to.path) {
                    try fm.copyItem(at: from, to: to)
                }
            }

            print("[Magpie] Migrated clipboard database from \(legacyDir.path) to \(targetDir.path)")
        } catch {
            print("[Magpie] Legacy database migration skipped: \(error)")
        }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        monitor.start { [weak self] pasteboard in
            self?.handleNewClip(from: pasteboard)
        }
    }

    func stopMonitoring() {
        monitor.stop()
    }

    // MARK: - Clip Handling (rich content aware)

    private func handleNewClip(from pasteboard: NSPasteboard) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        guard var item = ClipboardContent.read(
            from: pasteboard,
            sourceBundleID: frontmost?.bundleIdentifier,
            sourceAppName: frontmost?.localizedName,
            observedSourceBundleIDs: monitor.sourceBundleIDsForCurrentChange,
            excludedBundleIDs: exclusionManager.excludedBundleIDs
        ), let repository else { return }
        do {
            if try repository.record(&item, maxUnpinnedCount: HistorySettings.limit(in: .standard)) {
                loadClips()
            }
        } catch {
            print("[Magpie] Failed to save clip: \(error)")
        }
    }

    // MARK: - Data Access

    func loadClips() {
        clips = (try? repository?.fetchAll()) ?? []
        mcpSharing.retainClips(in: clips)
        updateDisplayedClips()
    }

    private func updateDisplayedClips() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            displayedClips = clips
            hasTrackedCurrentSearch = false
        } else {
            displayedClips = (try? repository?.search(query: query)) ?? []
            if !hasTrackedCurrentSearch {
                analytics.trackSearchPerformed(
                    queryLength: query.count,
                    resultCount: displayedClips.count
                )
                hasTrackedCurrentSearch = true
            }
        }
    }

    // MARK: - Actions

    func toggleMCPSharing(for id: Int64) {
        guard let item = clips.first(where: { $0.id == id }) else { return }
        mcpSharing.toggle(item)
    }

    /// Copies the given clip's content back to the system clipboard,
    /// triggers the "Copied!" animation, then dismisses the popover.
    func copyToClipboard(_ item: ClipItem) {
        let pasteboard = NSPasteboard.general
        guard ClipboardContent.restore(item, to: pasteboard) else { return }

        // Tell the monitor to ignore this change
        monitor.lastChangeCount = pasteboard.changeCount
        analytics.trackClipRestored(contentType: item.contentType)

        // Show "Copied!" animation, then dismiss the popover
        copiedItemID = item.id

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.copiedItemID = nil
            self?.searchText = ""
            self?.onDismiss?()
        }
    }

    /// Toggles the pin state on a clip.
    func togglePin(_ item: ClipItem) {
        do {
            try repository?.togglePin(item)
            loadClips()
        } catch {
            print("[Magpie] Failed to toggle pin: \(error)")
        }
    }

    /// Deletes a single clip and refreshes the list.
    func deleteClip(_ item: ClipItem) {
        do {
            try repository?.delete(item)
            loadClips()
        } catch {
            print("[Magpie] Failed to delete clip: \(error)")
        }
    }

    /// Deletes all clips and refreshes the list.
    func clearAll() {
        do {
            try repository?.deleteAll()
            loadClips()
        } catch {
            print("[Magpie] Failed to clear clips: \(error)")
        }
    }

    /// Opens the settings window via the AppDelegate callback.
    func openSettings() {
        onOpenSettings?()
    }
}
