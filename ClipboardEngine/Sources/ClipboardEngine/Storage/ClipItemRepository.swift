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
    public func fetchAll(limit: Int = 200) throws -> [ClipItem] {
        try dbPool.read { db in
            try ClipItem
                .order(
                    ClipItem.Columns.isPinned.desc,
                    ClipItem.Columns.createdAt.desc
                )
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Searches clips whose text content contains the given query (case-insensitive).
    public func search(query: String, limit: Int = 200) throws -> [ClipItem] {
        let pattern = "%\(query)%"
        return try dbPool.read { db in
            try ClipItem
                .filter(
                    ClipItem.Columns.contentText.like(pattern)
                    || ClipItem.Columns.previewText.like(pattern)
                )
                .order(
                    ClipItem.Columns.isPinned.desc,
                    ClipItem.Columns.createdAt.desc
                )
                .limit(limit)
                .fetchAll(db)
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

    /// Returns `true` if the most recent clip has the same text content,
    /// preventing consecutive duplicate entries.
    public func isDuplicate(of text: String) throws -> Bool {
        try dbPool.read { db in
            let latestClip = try ClipItem
                .order(ClipItem.Columns.createdAt.desc)
                .limit(1)
                .fetchOne(db)

            return latestClip?.contentText == text
        }
    }

    // MARK: - History Limit Enforcement

    /// Prunes the oldest unpinned clips so that the total unpinned count
    /// does not exceed `maxCount`.
    public func enforceHistoryLimit(_ maxCount: Int) throws {
        try dbPool.write { db in
            let unpinnedCount = try ClipItem
                .filter(ClipItem.Columns.isPinned == false)
                .fetchCount(db)

            guard unpinnedCount > maxCount else { return }

            let excess = unpinnedCount - maxCount
            let oldestIDs = try ClipItem
                .filter(ClipItem.Columns.isPinned == false)
                .order(ClipItem.Columns.createdAt.asc)
                .limit(excess)
                .fetchAll(db)
                .compactMap(\.id)

            _ = try ClipItem
                .filter(oldestIDs.contains(ClipItem.Columns.id))
                .deleteAll(db)
        }
    }
}
