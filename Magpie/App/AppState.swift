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
    /// in a degraded mode (no persistence, monitoring still works for the session).
    @Published var databaseError: String?

    // MARK: - Dependencies

    private(set) var databaseManager: DatabaseManager?
    private(set) var repository: ClipItemRepository?
    let monitor: ClipboardMonitor
    let exclusionManager: ExclusionListManager

    // MARK: - Init

    init() {
        monitor = ClipboardMonitor(pollInterval: 0.5)
        exclusionManager = ExclusionListManager()

        do {
            let dbManager = try DatabaseManager()
            databaseManager = dbManager
            repository = ClipItemRepository(dbPool: dbManager.dbPool)
        } catch {
            // First failure — try to recover by resetting the database
            print("[Magpie] Database init failed: \(error). Attempting recovery...")
            do {
                try Self.resetDatabaseFile()
                let dbManager = try DatabaseManager()
                databaseManager = dbManager
                repository = ClipItemRepository(dbPool: dbManager.dbPool)
                print("[Magpie] Database recovered successfully (history was reset).")
            } catch {
                // Recovery failed — run in degraded mode
                print("[Magpie] Database recovery failed: \(error). Running without persistence.")
                databaseManager = nil
                repository = nil
                databaseError = error.localizedDescription
            }
        }

        loadClips()
    }

    /// Deletes the database file so it can be recreated fresh.
    private static func resetDatabaseFile() throws {
        let appSupportURL = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: false)
            .appendingPathComponent("Magpie", isDirectory: true)

        let fm = FileManager.default
        for suffix in ["clipboard.sqlite", "clipboard.sqlite-wal", "clipboard.sqlite-shm"] {
            let path = appSupportURL.appendingPathComponent(suffix).path
            if fm.fileExists(atPath: path) {
                try fm.removeItem(atPath: path)
            }
        }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        monitor.start { [weak self] pasteboard in
            Task { @MainActor in
                self?.handleNewClip(from: pasteboard)
            }
        }
    }

    func stopMonitoring() {
        monitor.stop()
    }

    // MARK: - Clip Handling (rich content aware)

    private func handleNewClip(from pasteboard: NSPasteboard) {
        // Check exclusion list
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        if exclusionManager.isExcluded(frontmostApp?.bundleIdentifier) {
            return
        }

        let types = pasteboard.types ?? []

        // Determine content type with priority: image > file > richText > text
        if types.contains(.png) || types.contains(.tiff) {
            handleImageClip(from: pasteboard, frontmostApp: frontmostApp)
        } else if types.contains(.fileURL) {
            handleFileClip(from: pasteboard, frontmostApp: frontmostApp)
        } else if types.contains(.rtf) {
            handleRichTextClip(from: pasteboard, frontmostApp: frontmostApp)
        } else if types.contains(.string) {
            handleTextClip(from: pasteboard, frontmostApp: frontmostApp)
        }
    }

    private func handleTextClip(
        from pasteboard: NSPasteboard,
        frontmostApp: NSRunningApplication?
    ) {
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        // Skip consecutive duplicates
        if let isDup = try? repository?.isDuplicate(of: text), isDup { return }

        var item = ClipItem(
            contentText: text,
            contentType: "text",
            sourceAppBundleID: frontmostApp?.bundleIdentifier,
            sourceAppName: frontmostApp?.localizedName,
            createdAt: Date(),
            previewText: String(text.prefix(200))
        )

        saveClip(&item)
    }

    private func handleRichTextClip(
        from pasteboard: NSPasteboard,
        frontmostApp: NSRunningApplication?
    ) {
        let rtfData = pasteboard.data(forType: .rtf)
        let plainText = pasteboard.string(forType: .string)

        guard rtfData != nil || plainText != nil else { return }

        // Dedup on the plain text representation
        if let text = plainText,
           let isDup = try? repository?.isDuplicate(of: text), isDup {
            return
        }

        var item = ClipItem(
            contentText: plainText,
            contentRichData: rtfData,
            contentType: "richText",
            sourceAppBundleID: frontmostApp?.bundleIdentifier,
            sourceAppName: frontmostApp?.localizedName,
            createdAt: Date(),
            previewText: plainText.map { String($0.prefix(200)) }
        )

        saveClip(&item)
    }

    private func handleImageClip(
        from pasteboard: NSPasteboard,
        frontmostApp: NSRunningApplication?
    ) {
        // Try PNG first, fall back to TIFF
        var imageData = pasteboard.data(forType: .png)
        if imageData == nil, let tiffData = pasteboard.data(forType: .tiff) {
            // Convert TIFF → PNG for consistent storage
            if let bitmapRep = NSBitmapImageRep(data: tiffData) {
                imageData = bitmapRep.representation(using: .png, properties: [:])
            }
        }

        guard let data = imageData else { return }

        // Also grab any text representation (e.g. image alt text)
        let plainText = pasteboard.string(forType: .string)

        var item = ClipItem(
            contentText: plainText,
            contentImageData: data,
            contentType: "image",
            sourceAppBundleID: frontmostApp?.bundleIdentifier,
            sourceAppName: frontmostApp?.localizedName,
            createdAt: Date(),
            previewText: plainText.map { String($0.prefix(200)) } ?? "[Image]"
        )

        saveClip(&item)
    }

    private func handleFileClip(
        from pasteboard: NSPasteboard,
        frontmostApp: NSRunningApplication?
    ) {
        guard let urlString = pasteboard.string(forType: .fileURL),
              let url = URL(string: urlString)
        else { return }

        let path = url.path
        let fileName = url.lastPathComponent

        // Dedup on the file path
        if let isDup = try? repository?.isDuplicate(of: path), isDup { return }

        var item = ClipItem(
            contentText: path,
            contentFilePath: path,
            contentType: "filePath",
            sourceAppBundleID: frontmostApp?.bundleIdentifier,
            sourceAppName: frontmostApp?.localizedName,
            createdAt: Date(),
            previewText: fileName
        )

        saveClip(&item)
    }

    private func saveClip(_ item: inout ClipItem) {
        guard let repository else { return }
        do {
            try repository.insert(&item)

            // Enforce history limit if configured (0 = unlimited)
            let maxSize = UserDefaults.standard.integer(forKey: "maxHistorySize")
            if maxSize > 0 {
                try repository.enforceHistoryLimit(maxSize)
            }

            loadClips()
        } catch {
            print("[Magpie] Failed to save clip: \(error)")
        }
    }

    // MARK: - Data Access

    func loadClips() {
        clips = (try? repository?.fetchAll()) ?? []
        updateDisplayedClips()
    }

    private func updateDisplayedClips() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            displayedClips = clips
        } else {
            displayedClips = (try? repository?.search(query: query)) ?? []
        }
    }

    // MARK: - Actions

    /// Copies the given clip's content back to the system clipboard,
    /// triggers the "Copied!" animation, then dismisses the popover.
    func copyToClipboard(_ item: ClipItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.contentType {
        case "image":
            if let imageData = item.contentImageData {
                pasteboard.setData(imageData, forType: .png)
            }
            if let text = item.contentText {
                pasteboard.setString(text, forType: .string)
            }
        case "richText":
            if let rtfData = item.contentRichData {
                pasteboard.setData(rtfData, forType: .rtf)
            }
            if let text = item.contentText {
                pasteboard.setString(text, forType: .string)
            }
        case "filePath":
            if let path = item.contentFilePath {
                let url = URL(fileURLWithPath: path)
                pasteboard.writeObjects([url as NSURL])
            }
            if let text = item.contentText {
                pasteboard.setString(text, forType: .string)
            }
        default:
            if let text = item.contentText {
                pasteboard.setString(text, forType: .string)
            }
        }

        // Tell the monitor to ignore this change
        monitor.lastChangeCount = pasteboard.changeCount

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
