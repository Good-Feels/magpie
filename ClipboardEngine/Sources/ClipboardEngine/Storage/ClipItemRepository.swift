import Foundation
import GRDB

/// Provides CRUD operations for `ClipItem` records.
///
/// Thread-safe: all operations go through the GRDB `DatabasePool`
/// which serialises writes and allows concurrent reads.
public struct ClipItemRepository: Sendable {
    private let dbPool: DatabasePool

    public init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    // MARK: - Create

    /// Inserts a new clip item. The `id` property is populated after insertion.
    @discardableResult
    public func insert(_ item: inout ClipItem) throws -> ClipItem {
        try dbPool.write { db in
            try item.insert(db)
        }
        return item
    }

    // MARK: - Read

    /// Fetches all clips ordered by: pinned first, then newest first.
    /// Pass `limit: nil` (the default) for no cap — the history limit
    /// is enforced at write time by `enforceHistoryLimit`, not at read time.
    public func fetchAll(limit: Int? = nil) throws -> [ClipItem] {
        try dbPool.read { db in
            var request = orderedHistory(ClipItem.all())
            if let limit { request = request.limit(limit) }
            return try request.fetchAll(db)
        }
    }

    /// Searches clips whose text content contains the given query (case-insensitive).
    public func search(query: String, limit: Int? = nil) throws -> [ClipItem] {
        try dbPool.read { db in
            var request = orderedHistory(matchingHistory(query))
            if let limit { request = request.limit(limit) }
            return try request.fetchAll(db)
        }
    }

    /// Reads one page of previews. The first page includes the total count for
    /// the same database snapshot. Search always covers the whole history.
    public func historyPage(query: String, after cursor: ClipHistoryEntry?, limit: Int)
        async throws -> (entries: [ClipHistoryEntry], totalCount: Int?) {
        try await dbPool.read { db in
            let matches = matchingHistory(query)
            var page = orderedHistory(matches)
            if let cursor {
                page = page.filter(
                    sql: "(isPinned, createdAt, id) < (?, ?, ?)",
                    arguments: [cursor.isPinned, cursor.sortTimestamp, cursor.id]
                )
            }
            let entries = try page.select(sql: """
                id, contentType, sourceAppBundleID, sourceAppName, isPinned, createdAt,
                contentFilePath, contentFilePathsJSON,
                substr(coalesce(previewText, contentText), 1, 500) AS previewText,
                length(contentText) AS textLength,
                length(CAST(contentText AS BLOB)) AS textByteCount,
                length(contentImageData) AS imageByteCount
                """, as: ClipHistoryEntry.self)
                .limit(limit)
                .fetchAll(db)
            let total = cursor == nil ? try matches.fetchCount(db) : nil
            return (entries, total)
        }
    }

    public func fetch(id: Int64) throws -> ClipItem? {
        try dbPool.read { db in try ClipItem.fetchOne(db, key: id) }
    }

    public func imageData(id: Int64) async throws -> Data? {
        try await dbPool.read { db in
            try ClipItem.filter(key: id).select(sql: "contentImageData", as: Data?.self).fetchOne(db) ?? nil
        }
    }

    public func existingIDs(_ ids: [Int64]) throws -> Set<Int64> {
        try dbPool.read { db in
            try ClipItem.filter(keys: ids).select(ClipItem.Columns.id, as: Int64.self).fetchSet(db)
        }
    }

    private func matchingHistory(_ query: String) -> QueryInterfaceRequest<ClipItem> {
        guard !query.isEmpty else { return ClipItem.all() }
        let pattern = "%\(query)%"
        return ClipItem.filter(
            ClipItem.Columns.contentText.like(pattern) || ClipItem.Columns.previewText.like(pattern)
        )
    }

    private func orderedHistory(_ request: QueryInterfaceRequest<ClipItem>) -> QueryInterfaceRequest<ClipItem> {
        request.order(ClipItem.Columns.isPinned.desc, ClipItem.Columns.createdAt.desc, ClipItem.Columns.id.desc)
    }

    // MARK: - Update

    /// Toggles the `isPinned` flag on a clip.
    public func togglePin(_ item: ClipItem) throws {
        if let id = item.id { try togglePin(id: id) }
    }

    public func togglePin(id: Int64) throws {
        try dbPool.write { db in
            try db.execute(sql: "UPDATE clipItems SET isPinned = NOT isPinned WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Delete

    /// Deletes a single clip.
    public func delete(_ item: ClipItem) throws {
        if let id = item.id { try delete(id: id) }
    }

    public func delete(id: Int64) throws {
        _ = try dbPool.write { db in try ClipItem.deleteOne(db, key: id) }
    }

    /// Deletes all clips from the database.
    public func deleteAll() throws {
        _ = try dbPool.write { db in
            try ClipItem.deleteAll(db)
        }
    }

    // MARK: - Deduplication

    /// Full payload identity: equal plain text must not discard different rich
    /// formatting, images or a changed second file in a selection.
    public func isDuplicate(of item: ClipItem) throws -> Bool {
        try dbPool.read { db in try isDuplicate(item, in: db) }
    }

    /// Deduplicate, insert and enforce the configured limit atomically.
    /// Zero means unlimited; pinned rows are excluded from retention pruning.
    @discardableResult
    public func record(_ item: inout ClipItem, maxUnpinnedCount: Int) throws -> Bool {
        try dbPool.write { db in
            guard try !isDuplicate(item, in: db) else { return false }
            try item.insert(db)
            if maxUnpinnedCount > 0 { try prune(maxUnpinnedCount, in: db) }
            return true
        }
    }

    private func isDuplicate(_ item: ClipItem, in db: Database) throws -> Bool {
        guard let latest = try ClipItem.order(ClipItem.Columns.createdAt.desc, ClipItem.Columns.id.desc)
            .limit(1).fetchOne(db) else { return false }
        return latest.contentType == item.contentType
            && latest.contentText == item.contentText
            && latest.contentRichData == item.contentRichData
            && latest.contentImageData == item.contentImageData
            && latest.filePaths == item.filePaths
    }

    // MARK: - History Limit Enforcement

    /// Prunes the oldest unpinned clips so that the total unpinned count
    /// does not exceed `maxCount`.
    public func enforceHistoryLimit(_ maxCount: Int) throws {
        guard maxCount > 0 else { return }
        try dbPool.write { db in try prune(maxCount, in: db) }
    }

    private func prune(_ maxCount: Int, in db: Database) throws {
        let unpinned = ClipItem.filter(ClipItem.Columns.isPinned == false)
        let excess = try unpinned.fetchCount(db) - maxCount
        guard excess > 0 else { return }
        try db.execute(sql: """
            DELETE FROM clipItems WHERE id IN (
                SELECT id FROM clipItems WHERE isPinned = 0
                ORDER BY createdAt ASC, id ASC LIMIT ?
            )
            """, arguments: [excess])
    }
}
