import AppKit
import Foundation
import GRDB
import XCTest
@testable import ClipboardEngine

final class ClipboardEngineTests: XCTestCase {
    private func directory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MagpieTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }
    private func database() throws -> DatabaseManager {
        let db = try DatabaseManager(directoryURL: directory())
        addTeardownBlock { try? db.dbPool.close() }
        return db
    }
    private func defaults() -> UserDefaults {
        let suite = "MagpieTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        // Registration defaults are process-wide even across named suites.
        let registration = defaults.volatileDomain(forName: UserDefaults.registrationDomain)
        defaults.setVolatileDomain([:], forName: UserDefaults.registrationDomain)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            defaults.setVolatileDomain(registration, forName: UserDefaults.registrationDomain)
        }
        return defaults
    }
    @MainActor private func pasteboard() -> NSPasteboard {
        let pb = NSPasteboard.withUniqueName()
        addTeardownBlock { pb.releaseGlobally() }
        return pb
    }
    @MainActor private func read(_ pb: NSPasteboard, observed: Set<String> = [], excluded: Set<String> = []) -> ClipItem? {
        ClipboardContent.read(from: pb, sourceBundleID: "test.editor", sourceAppName: "Test Editor",
                              observedSourceBundleIDs: observed, excludedBundleIDs: excluded)
    }
    func testMAG001CorruptDatabaseSurvivesRepeatedRealOpenFailures() throws {
        let dir = try directory()
        let path = dir.appendingPathComponent("clipboard.sqlite")
        let original = Data("Synthetic damaged database, kept for recovery".utf8)
        try original.write(to: path)
        for _ in 0..<2 {
            let prefs = defaults()
            let result = DatabaseStartup.open(defaults: prefs) { try DatabaseManager(directoryURL: dir) }
            if case .success = result { XCTFail("Damaged database must fail to open") }
            XCTAssertEqual(try Data(contentsOf: path), original)
            XCTAssertEqual(HistorySettings.limit(in: prefs), 0, "Unknown history is preserved as unlimited")
        }
    }
    func testMAG001StartupFailureBeforeSQLitePreservesDatabaseAndSidecars() throws {
        let dir = try directory()
        let names = ["clipboard.sqlite", "clipboard.sqlite-wal", "clipboard.sqlite-shm"]
        for name in names { try Data(name.utf8).write(to: dir.appendingPathComponent(name)) }
        enum OpenError: Error { case unavailable }
        let result = DatabaseStartup.open(defaults: defaults()) { throw OpenError.unavailable }
        if case .success = result { XCTFail("Failed startup must remain a failure") }
        for name in names {
            XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(name)), Data(name.utf8))
        }
    }
    func testMAG001ReopenPreservesPinnedHistoryAndPermissions() throws {
        let dir = try directory()
        do {
            let db = try DatabaseManager(directoryURL: dir)
            var item = ClipItem(contentText: "Synthetic pinned history", isPinned: true)
            try ClipItemRepository(dbPool: db.dbPool).insert(&item)
            try db.dbPool.close()
        }
        let reopened = try DatabaseManager(directoryURL: dir)
        defer { try? reopened.dbPool.close() }
        let rows = try ClipItemRepository(dbPool: reopened.dbPool).fetchAll()
        XCTAssertEqual(rows.map(\.contentText), ["Synthetic pinned history"])
        XCTAssertTrue(try XCTUnwrap(rows.first).isPinned)
        let attrs = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("clipboard.sqlite").path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    @MainActor func testMAG002EverySensitiveMarkerRejectsAllRepresentations() async throws {
        for marker in ClipboardCapturePolicy.ignoredTypes {
            let pb = pasteboard()
            let item = NSPasteboardItem()
            let provider = CountingPasteboardProvider()
            item.setDataProvider(provider, forTypes: [.string, .rtf, .png, .fileURL])
            item.setData(Data(), forType: marker)
            XCTAssertTrue(pb.writeObjects([item]))
            XCTAssertNil(read(pb), "Must reject \(marker.rawValue)")
            XCTAssertEqual(provider.callCount, 0, "Sensitive payloads must not be decoded")
        }
    }
    @MainActor func testMAG002ConcealedMarkerOnLaterItemRejectsWholeSelection() async throws {
        let pb = pasteboard()
        let first = NSPasteboardItem()
        first.setString("file:///synthetic/public", forType: .fileURL)
        let later = NSPasteboardItem()
        later.setString("file:///synthetic/private", forType: .fileURL)
        later.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        XCTAssertTrue(pb.writeObjects([first, later]))
        XCTAssertNil(read(pb))
    }
    @MainActor func testMAG002ExcludedSourceToEditorWithinPollingIntervalIsRejected() async throws {
        let pb = pasteboard()
        XCTAssertTrue(pb.setString("Synthetic password", forType: .string))
        var interval = ClipboardSourceInterval(initialBundleID: "test.password-manager")
        interval.observe("test.editor")
        XCTAssertNil(read(pb, observed: interval.finish(currentBundleID: "test.editor"), excluded: ["test.password-manager"]))
        XCTAssertNotNil(read(pb, observed: interval.finish(currentBundleID: "test.editor"), excluded: ["test.password-manager"]))
    }
    @MainActor func testMAG002BriefExcludedAppBetweenPollsIsRemembered() async throws {
        let pb = pasteboard()
        pb.setString("Synthetic password", forType: .string)
        var interval = ClipboardSourceInterval(initialBundleID: "test.editor")
        interval.observe("test.password-manager")
        interval.observe("test.editor")
        XCTAssertNil(read(pb, observed: interval.finish(currentBundleID: "test.editor"), excluded: ["test.password-manager"]))
    }
    @MainActor func testMAG002MonitorActivationNotificationsReachCaptureGate() async throws {
        let pb = pasteboard()
        let center = NotificationCenter()
        var notificationCount = 0
        let monitor = ClipboardMonitor(pollInterval: 0.02, pasteboard: pb,
            currentSourceBundleID: { "test.editor" }, activationCenter: center,
            activatedBundleID: {
                notificationCount += 1
                return $0.userInfo?["testBundleID"] as? String
            })
        var received = false
        monitor.start { changed in
            XCTAssertTrue(monitor.sourceBundleIDsForCurrentChange.contains("test.password-manager"))
            XCTAssertNil(self.read(changed, observed: monitor.sourceBundleIDsForCurrentChange,
                                   excluded: ["test.password-manager"]))
            monitor.stop()
            received = true
        }
        defer { monitor.stop() }
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                    userInfo: ["testBundleID": "test.password-manager"])
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                    userInfo: ["testBundleID": "test.editor"])
        XCTAssertEqual(notificationCount, 2, "Source evidence is processed synchronously before polling")
        pb.clearContents()
        pb.setString("Synthetic private copy", forType: .string)
        monitor.checkForChanges()
        XCTAssertTrue(received)
    }
    @MainActor func testMAG002GenerationChangeDuringLazyPayloadIsRejected() async throws {
        let pb = pasteboard()
        let provider = ReplacingPasteboardProvider()
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.string])
        XCTAssertTrue(pb.writeObjects([item]))
        XCTAssertNil(read(pb))
        XCTAssertTrue(provider.wasCalled)
    }
    @MainActor func testMAG002SourceHintCannotOverrideObservedExclusion() async throws {
        let pb = pasteboard()
        let item = NSPasteboardItem()
        item.setString("Synthetic secret", forType: .string)
        item.setString("test.editor", forType: ClipboardCapturePolicy.sourceType)
        pb.writeObjects([item])
        XCTAssertNil(read(pb, observed: ["test.password-manager"], excluded: ["test.password-manager"]))
        pb.clearContents()
        let hinted = NSPasteboardItem()
        hinted.setString("Synthetic secret", forType: .string)
        hinted.setString("test.password-manager", forType: ClipboardCapturePolicy.sourceType)
        pb.writeObjects([hinted])
        XCTAssertNil(read(pb, excluded: ["test.password-manager"]))
    }
    @MainActor func testMAG002AllowedTextAndRichTextStillCaptureAndRestore() async throws {
        let pb = pasteboard()
        pb.setString("Normal synthetic copy", forType: .string)
        let text = try XCTUnwrap(read(pb))
        let output = pasteboard()
        XCTAssertTrue(ClipboardContent.restore(text, to: output))
        XCTAssertEqual(output.string(forType: .string), text.contentText)
        let rich = ClipItem(contentText: "Rich text", contentRichData: Data("{\\rtf1 Rich text}".utf8), contentType: "richText")
        XCTAssertTrue(ClipboardContent.restore(rich, to: output))
        XCTAssertEqual(output.data(forType: .rtf), rich.contentRichData)
        XCTAssertEqual(read(output)?.contentType, "richText")
    }
    func testMAG003FreshInstallUses200AndPreservesPins() throws {
        let prefs = defaults()
        let db = try DatabaseStartup.open(defaults: prefs) { try database() }.get()
        let repo = ClipItemRepository(dbPool: db.dbPool)
        XCTAssertEqual(HistorySettings.limit(in: prefs), 200)
        var pinned = ClipItem(contentText: "Pinned", isPinned: true, createdAt: Date(timeIntervalSince1970: 1))
        try repo.record(&pinned, maxUnpinnedCount: HistorySettings.limit(in: prefs))
        for n in 0..<205 {
            var item = ClipItem(contentText: "Clip \(n)", createdAt: Date(timeIntervalSince1970: Double(n + 2)))
            try repo.record(&item, maxUnpinnedCount: HistorySettings.limit(in: prefs))
        }
        let rows = try repo.fetchAll()
        XCTAssertEqual(rows.count, 201)
        XCTAssertEqual(rows.filter(\.isPinned).map(\.contentText), ["Pinned"])
        XCTAssertFalse(rows.contains { $0.contentText == "Clip 0" })
        XCTAssertTrue(rows.contains { $0.contentText == "Clip 204" })
    }
    func testMAG003LegacyMissingPreferencePreservesAllHistoryAsUnlimited() throws {
        let db = try database()
        let repo = ClipItemRepository(dbPool: db.dbPool)
        for n in 0..<205 { var item = ClipItem(contentText: "Legacy \(n)"); try repo.insert(&item) }
        let prefs = defaults()
        XCTAssertNil(prefs.object(forKey: HistorySettings.key))
        _ = try DatabaseStartup.open(defaults: prefs) { db }.get()
        XCTAssertEqual(HistorySettings.limit(in: prefs), 0)
        var next = ClipItem(contentText: "After upgrade")
        try repo.record(&next, maxUnpinnedCount: HistorySettings.limit(in: prefs))
        XCTAssertEqual(try repo.fetchAll().count, 206)
        HistorySettings.prepare(defaults: prefs, hasExistingHistory: true)
        XCTAssertEqual(prefs.integer(forKey: HistorySettings.key), 0)
    }
    func testMAG003ExplicitUnlimitedAndFinitePreferencesAreRespected() throws {
        let prefs = defaults()
        prefs.set(0, forKey: HistorySettings.key)
        HistorySettings.prepare(defaults: prefs, hasExistingHistory: false)
        XCTAssertEqual(HistorySettings.limit(in: prefs), 0)
        prefs.set(50, forKey: HistorySettings.key)
        HistorySettings.prepare(defaults: prefs, hasExistingHistory: true)
        XCTAssertEqual(HistorySettings.limit(in: prefs), 50)
        let db = try database()
        let repo = ClipItemRepository(dbPool: db.dbPool)
        for n in 0..<55 { var item = ClipItem(contentText: "Cap \(n)"); try repo.record(&item, maxUnpinnedCount: 50) }
        XCTAssertEqual(try repo.fetchAll().count, 50)
        prefs.set(-1, forKey: HistorySettings.key)
        XCTAssertEqual(HistorySettings.limit(in: prefs), 200)
    }

    func testMAG007UnlimitedPagesReachOldClipsWithIdenticalTimestamps() async throws {
        let prefs = defaults()
        prefs.set(0, forKey: HistorySettings.key)
        let db = try database()
        let repo = ClipItemRepository(dbPool: db.dbPool)
        let timestamp = Date(timeIntervalSince1970: 1_000.123)
        let limit = HistorySettings.limit(in: prefs)
        var pinned: [Int64] = []
        var unpinned: [Int64] = []
        for index in 0..<1_207 {
            var item = ClipItem(
                contentText: index.isMultiple(of: 23) ? "Searchable sample \(index)" : "Clip \(index)",
                isPinned: index.isMultiple(of: 20),
                createdAt: timestamp
            )
            XCTAssertTrue(try repo.record(&item, maxUnpinnedCount: limit))
            let id = try XCTUnwrap(item.id)
            if item.isPinned { pinned.append(id) } else { unpinned.append(id) }
        }

        let first = try await repo.historyPage(query: "", after: nil, limit: 60)
        XCTAssertEqual(first.totalCount, 1_207)
        XCTAssertEqual(first.entries.count, 60)
        var found = first.entries
        for _ in 0..<21 {
            let boundary = try XCTUnwrap(found.last)
            let page = try await repo.historyPage(query: "", after: boundary, limit: 60)
            XCTAssertNil(page.totalCount)
            found.append(contentsOf: page.entries)
        }
        XCTAssertEqual(found.map(\.id), Array(pinned.reversed()) + Array(unpinned.reversed()))

        let expected = found.filter { $0.previewText.hasPrefix("Searchable sample") }
        let search = try await repo.historyPage(query: "SEARCHABLE SAMPLE", after: nil, limit: 10)
        XCTAssertEqual(search.totalCount, expected.count)
        XCTAssertEqual(search.entries.map(\.id), expected.prefix(10).map(\.id))
        let boundary = try XCTUnwrap(search.entries.last)
        try repo.delete(id: boundary.id)
        let next = try await repo.historyPage(query: "SEARCHABLE SAMPLE", after: boundary, limit: 10)
        XCTAssertEqual(next.entries.map(\.id), expected.dropFirst(10).prefix(10).map(\.id))
    }

    func testMAG007PagedPreviewsPreserveClipActionsAndSharedIDs() async throws {
        let db = try database()
        let repo = ClipItemRepository(dbPool: db.dbPool)
        var image = ClipItem(contentImageData: Data(repeating: 1, count: 120_000), contentType: "image")
        var text = ClipItem(contentText: String(repeating: "🪶", count: 900) + "deep search term",
                            contentRichData: Data("synthetic RTF".utf8), contentType: "richText")
        var legacyFile = ClipItem(contentFilePath: "/synthetic/legacy.txt", contentType: "filePath",
                                  previewText: "legacy.txt")
        try repo.insert(&image)
        try repo.insert(&text)
        try repo.insert(&legacyFile)
        let imageID = try XCTUnwrap(image.id)
        let textID = try XCTUnwrap(text.id)
        let fileID = try XCTUnwrap(legacyFile.id)

        let first = try await repo.historyPage(query: "", after: nil, limit: 10)
        XCTAssertEqual(first.totalCount, 3)
        XCTAssertEqual(first.entries.first(where: { $0.id == imageID })?.imageByteCount, 120_000)
        XCTAssertEqual(first.entries.first(where: { $0.id == fileID })?.previewText, "/synthetic/legacy.txt")
        let search = try await repo.historyPage(query: "deep search term", after: nil, limit: 10)
        XCTAssertEqual(search.entries.map(\.id), [textID])
        let summary = try XCTUnwrap(search.entries.first)
        XCTAssertEqual(summary.previewText.count, 500)
        XCTAssertEqual(summary.textByteCount, text.contentText?.utf8.count)
        let imagePayload = try await repo.imageData(id: imageID)
        XCTAssertEqual(imagePayload, image.contentImageData)
        XCTAssertEqual(try repo.fetch(id: textID)?.contentRichData, text.contentRichData)
        XCTAssertEqual(try repo.fetch(id: fileID)?.filePaths, ["/synthetic/legacy.txt"])

        try repo.togglePin(id: imageID)
        try repo.enforceHistoryLimit(1)
        let retained = try await repo.historyPage(query: "", after: nil, limit: 10)
        XCTAssertEqual(retained.entries.map(\.id), [imageID, fileID])
        XCTAssertEqual(try repo.existingIDs([imageID, textID, fileID]), Set([imageID, fileID]))
        try repo.deleteAll()
        XCTAssertTrue(try repo.existingIDs([imageID, fileID]).isEmpty)
    }

    @MainActor func testMAG004TwoFilesPersistReopenAndRestoreInOrder() async throws {
        let dir = try directory()
        let pb = pasteboard()
        let paths = ["/synthetic/first.txt", "/synthetic/second.txt"]
        XCTAssertTrue(pb.writeObjects(paths.map { NSURL(fileURLWithPath: $0) }))
        var item = try XCTUnwrap(read(pb))
        XCTAssertEqual(item.filePaths, paths)
        do {
            let db = try DatabaseManager(directoryURL: dir)
            try ClipItemRepository(dbPool: db.dbPool).record(&item, maxUnpinnedCount: 200)
            try db.dbPool.close()
        }
        let reopened = try DatabaseManager(directoryURL: dir)
        defer { try? reopened.dbPool.close() }
        let saved = try XCTUnwrap(ClipItemRepository(dbPool: reopened.dbPool).fetchAll().first)
        XCTAssertEqual(saved.filePaths, paths)
        let output = pasteboard()
        XCTAssertTrue(ClipboardContent.restore(saved, to: output))
        XCTAssertEqual(read(output)?.filePaths, paths)
    }
    @MainActor func testMAG004ChangedSecondFileAndOrderAreNotDeduplicated() async throws {
        let db = try database()
        let repo = ClipItemRepository(dbPool: db.dbPool)
        let pb = pasteboard()
        for paths in [["/a", "/b"], ["/a", "/c"], ["/c", "/a"]] {
            pb.clearContents()
            pb.writeObjects(paths.map { NSURL(fileURLWithPath: $0) })
            var item = try XCTUnwrap(read(pb))
            XCTAssertTrue(try repo.record(&item, maxUnpinnedCount: 200))
            var duplicate = item
            XCTAssertFalse(try repo.record(&duplicate, maxUnpinnedCount: 200))
        }
        XCTAssertEqual(try repo.fetchAll().count, 3)
    }
    @MainActor func testMAG004LegacySingleFileAndMalformedGroupFallback() async throws {
        for json in [nil, "invalid-json", "[]", "[\"relative/path\"]"] as [String?] {
            let item = ClipItem(contentText: "/legacy/file.txt", contentFilePath: "/legacy/file.txt", contentFilePathsJSON: json, contentType: "filePath")
            XCTAssertEqual(item.filePaths, ["/legacy/file.txt"])
            let output = pasteboard()
            XCTAssertTrue(ClipboardContent.restore(item, to: output))
            XCTAssertEqual(read(output)?.filePaths, ["/legacy/file.txt"])
        }
    }
    func testMAG004V1MigrationPreservesLegacyPinnedSingleFile() throws {
        let dir = try directory()
        let queue = try DatabaseQueue(path: dir.appendingPathComponent("clipboard.sqlite").path)
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY); INSERT INTO grdb_migrations VALUES ('v1_createClipItems')")
            try db.execute(sql: """
                CREATE TABLE clipItems (id INTEGER PRIMARY KEY AUTOINCREMENT, contentText TEXT,
                contentRichData BLOB, contentImageData BLOB, contentFilePath TEXT, contentType TEXT NOT NULL,
                sourceAppBundleID TEXT, sourceAppName TEXT, isPinned BOOLEAN NOT NULL DEFAULT 0,
                createdAt DATETIME NOT NULL, previewText TEXT);
                INSERT INTO clipItems (contentText, contentFilePath, contentType, isPinned, createdAt)
                VALUES ('/legacy/kept.txt', '/legacy/kept.txt', 'filePath', 1, '2026-11-17 00:00:00.000');
                """)
        }
        try queue.close()
        let db = try DatabaseManager(directoryURL: dir)
        defer { try? db.dbPool.close() }
        let legacy = try XCTUnwrap(ClipItemRepository(dbPool: db.dbPool).fetchAll().first)
        XCTAssertEqual(legacy.filePaths, ["/legacy/kept.txt"])
        XCTAssertNil(legacy.contentFilePathsJSON)
        XCTAssertTrue(legacy.isPinned)
    }
    @MainActor func testMAG004InvalidPayloadDoesNotEraseDestination() async throws {
        let output = pasteboard()
        output.setString("Keep destination", forType: .string)
        XCTAssertFalse(ClipboardContent.restore(ClipItem(contentType: "filePath"), to: output))
        XCTAssertEqual(output.string(forType: .string), "Keep destination")
        let input = pasteboard()
        input.setString("https://example.invalid/not-a-file", forType: .fileURL)
        XCTAssertNil(read(input))
    }
    func testFullPayloadDedupPreservesFormattingAndContentType() throws {
        let db = try database()
        let repo = ClipItemRepository(dbPool: db.dbPool)
        var plain = ClipItem(contentText: "Same text")
        XCTAssertTrue(try repo.record(&plain, maxUnpinnedCount: 200))
        var rich = ClipItem(contentText: "Same text", contentRichData: Data("bold".utf8), contentType: "richText")
        XCTAssertTrue(try repo.record(&rich, maxUnpinnedCount: 200))
        var different = rich
        different.id = nil
        different.contentRichData = Data("italic".utf8)
        XCTAssertTrue(try repo.record(&different, maxUnpinnedCount: 200))
        XCTAssertEqual(try repo.fetchAll().count, 3)
    }
}

private final class ReplacingPasteboardProvider: NSObject, NSPasteboardItemDataProvider {
    var wasCalled = false
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        wasCalled = true
        let replacement = NSPasteboardItem()
        replacement.setString("Synthetic concealed replacement", forType: .string)
        replacement.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        pasteboard?.clearContents()
        pasteboard?.writeObjects([replacement])
        item.setString("Synthetic stale payload", forType: type)
    }
}

private final class CountingPasteboardProvider: NSObject, NSPasteboardItemDataProvider {
    var callCount = 0
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        callCount += 1
        item.setData(Data("Synthetic forbidden payload".utf8), forType: type)
    }
}
