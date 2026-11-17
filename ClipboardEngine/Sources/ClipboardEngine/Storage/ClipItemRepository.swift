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
            var request = ClipItem
                .order(
                    ClipItem.Columns.isPinned.desc,
                    ClipItem.Columns.createdAt.desc
                )
            if let limit { request = request.limit(limit) }
            return try request.fetchAll(db)
        }
    }

    /// Searches clips whose text content contains the given query (case-insensitive).
    public func search(query: String, limit: Int? = nil) throws -> [ClipItem] {
        let pattern = "%\(query)%"
        return try dbPool.read { db in
            var request = ClipItem
                .filter(
                    ClipItem.Columns.contentText.like(pattern)
                    || ClipItem.Columns.previewText.like(pattern)
                )
                .order(
                    ClipItem.Columns.isPinned.desc,
                    ClipItem.Columns.createdAt.desc
                )
            if let limit { request = request.limit(limit) }
            return try request.fetchAll(db)
        }
    }

    // MARK: - Update

    /// Toggles the `isPinned` flag on a clip.
    public func togglePin(_ item: ClipItem) throws {
        try dbPool.write { db in
            var mutable = item
            mutable.isPinned.toggle()
            try mutable.update(db)
        }
    }

    // MARK: - Delete

    /// Deletes a single clip.
    public func delete(_ item: ClipItem) throws {
        _ = try dbPool.write { db in
            try item.delete(db)
        }
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
        let oldestIDs = try unpinned
            .order(ClipItem.Columns.createdAt.asc, ClipItem.Columns.id.asc)
            .limit(excess).fetchAll(db).compactMap(\.id)
        _ = try ClipItem.filter(oldestIDs.contains(ClipItem.Columns.id)).deleteAll(db)
    }
}
