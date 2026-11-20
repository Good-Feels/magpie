import SwiftUI
import AppKit
import Combine
import ClipboardEngine
import ImageIO

/// Central app coordinator. Owns the database, clipboard monitor,
/// repository, and exclusion manager. Exposes published state for SwiftUI views.
@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State

    @Published private(set) var historyEntries: [ClipHistoryEntry] = []
    @Published private(set) var historyCount: Int?
    @Published private(set) var historyReadFailed = false
    @Published private(set) var isRefreshingHistory = false
    @Published var preferencesTab: PreferencesTab = .general

    /// The current search query typed in the search bar.
    @Published var searchText: String = "" {
        didSet {
            let oldQuery = oldValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard oldQuery != historyQuery else { return }
            if historyQuery.isEmpty { hasTrackedCurrentSearch = false }
            if isHistoryOpen {
                resetHistory()
                requestHistoryPage(debounceSearch: !historyQuery.isEmpty)
            }
        }
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
    private(set) lazy var monitor = ClipboardMonitor(pollInterval: 0.5)
    let exclusionManager = ExclusionListManager()
    private(set) lazy var accessChecker = ClipboardAccessChecker()
    let mcpHistory: MCPHistoryAccess
    private static let historyPageSize = 60
    private var historyTask: Task<Void, Never>?
    private var isHistoryOpen = false
    private var trackNextHistoryOpen = false
    private var requestedHistoryCount = AppState.historyPageSize
    private var hasTrackedCurrentSearch = false

    private var historyQuery: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: - Init

    convenience init() {
        Self.migrateLegacyDatabaseIfNeeded()
        self.init(database: DatabaseStartup.open(defaults: .standard, makeDatabase: { try DatabaseManager() }))
    }

    init(database: Result<DatabaseManager, Error>) {
        let historyRepository: ClipItemRepository?
        switch database {
        case .success(let dbManager):
            databaseManager = dbManager
            historyRepository = ClipItemRepository(dbPool: dbManager.dbPool)
        case .failure(let error):
            // Opening/migration/permissions errors do not prove that history is
            // unrecoverable. Preserve all database/WAL files for a later retry.
            print("[Magpie] Database unavailable; preserving history: \(error)")
            databaseError = error.localizedDescription
            historyRepository = nil
        }
        repository = historyRepository
        mcpHistory = MCPHistoryAccess(repository: historyRepository)
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
                historyDidChange()
            }
        } catch {
            print("[Magpie] Failed to save clip: \(error)")
        }
    }

    // MARK: - Data Access

    func openHistory() {
        isHistoryOpen = true
        trackNextHistoryOpen = true
        resetHistory()
        requestHistoryPage()
    }

    func closeHistory() {
        isHistoryOpen = false
        trackNextHistoryOpen = false
        resetHistory()
    }

    var hasMoreHistory: Bool { historyEntries.count < (historyCount ?? 0) }

    func loadMoreHistory(after entry: ClipHistoryEntry) {
        guard historyTask == nil, hasMoreHistory, !historyReadFailed,
              historyEntries.last?.id == entry.id else { return }
        requestedHistoryCount = historyEntries.count + Self.historyPageSize
        requestHistoryPage(after: entry)
    }

    func retryHistory() {
        requestHistoryPage()
    }

    private func resetHistory() {
        historyTask?.cancel()
        historyTask = nil
        historyEntries = []
        historyCount = nil
        historyReadFailed = false
        isRefreshingHistory = false
        requestedHistoryCount = Self.historyPageSize
    }

    private func historyDidChange() {
        if isHistoryOpen { requestHistoryPage() }
    }

    private func requestHistoryPage(after cursor: ClipHistoryEntry? = nil, debounceSearch: Bool = false) {
        guard isHistoryOpen, let repository else { return }
        historyTask?.cancel()
        historyReadFailed = false
        isRefreshingHistory = cursor == nil
        let query = historyQuery
        let limit = cursor == nil ? requestedHistoryCount : Self.historyPageSize
        historyTask = Task { [weak self] in
            do {
                if debounceSearch { try await Task.sleep(nanoseconds: 150_000_000) }
                let page = try await repository.historyPage(query: query, after: cursor, limit: limit)
                guard !Task.isCancelled, let self else { return }
                historyTask = nil
                if let count = page.totalCount {
                    if historyEntries != page.entries { historyEntries = page.entries }
                    historyCount = count
                    isRefreshingHistory = false
                    trackHistoryLoad(query: query, count: count)
                } else {
                    historyEntries.append(contentsOf: page.entries)
                    if page.entries.count < limit { historyCount = historyEntries.count }
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                historyTask = nil
                historyReadFailed = true
                isRefreshingHistory = false
            }
        }
    }

    private func trackHistoryLoad(query: String, count: Int) {
        if trackNextHistoryOpen {
            analytics.trackPopoverOpened(itemCount: count)
            trackNextHistoryOpen = false
        }
        if !query.isEmpty, !hasTrackedCurrentSearch {
            analytics.trackSearchPerformed(queryLength: query.count, resultCount: count)
            hasTrackedCurrentSearch = true
        }
    }

    func thumbnail(for id: Int64) async -> CGImage? {
        guard let repository else { return nil }
        return await Self.loadThumbnail(for: id, from: repository)
    }

    private nonisolated static func loadThumbnail(for id: Int64, from repository: ClipItemRepository) async -> CGImage? {
        guard let data = try? await repository.imageData(id: id), !Task.isCancelled else { return nil }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 320,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: - Actions

    /// Copies the given clip's content back to the system clipboard,
    /// triggers the "Copied!" animation, then dismisses the popover.
    func copyToClipboard(id: Int64) {
        guard let item = try? repository?.fetch(id: id) else { return }
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
    func togglePin(id: Int64) {
        do {
            try repository?.togglePin(id: id)
            historyDidChange()
        } catch {
            print("[Magpie] Failed to toggle pin: \(error)")
        }
    }

    /// Deletes a single clip and refreshes the list.
    func deleteClip(id: Int64) {
        do {
            try repository?.delete(id: id)
            historyDidChange()
        } catch {
            print("[Magpie] Failed to delete clip: \(error)")
        }
    }

    /// Deletes all clips and refreshes the list.
    func clearAll() {
        do {
            try repository?.deleteAll()
            historyDidChange()
        } catch {
            print("[Magpie] Failed to clear clips: \(error)")
        }
    }

    /// Opens the settings window via the AppDelegate callback.
    func openSettings() {
        onOpenSettings?()
    }
}
