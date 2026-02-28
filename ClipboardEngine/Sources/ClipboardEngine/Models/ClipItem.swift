import Foundation
import GRDB

/// Core data model representing a single clipboard entry.
/// Conforms to GRDB's `FetchableRecord` and `MutablePersistableRecord` for
/// seamless SQLite round-tripping.
public struct ClipItem: Codable, Identifiable, Sendable, Hashable {
    /// Auto-incremented database row ID.
    public var id: Int64?

    /// The plain-text content (always captured when available, even for rich types).
    public var contentText: String?

    /// RTF data for rich-text clips (Phase 2).
    public var contentRichData: Data?

    /// PNG image data for image clips (Phase 2).
    public var contentImageData: Data?

    /// File path string for file-reference clips (Phase 2).
    public var contentFilePath: String?

    /// Discriminator: "text", "richText", "image", "filePath".
    public var contentType: String

    /// Bundle ID of the app the clip was copied from.
    public var sourceAppBundleID: String?

    /// Display name of the source app.
    public var sourceAppName: String?

    /// Whether the user has pinned this clip as a favourite.
    public var isPinned: Bool

    /// Timestamp of when the clip was captured.
    public var createdAt: Date

    /// A short preview string (truncated) for display in the list.
    public var previewText: String?

    // MARK: - Initialiser

    public init(
        id: Int64? = nil,
        contentText: String? = nil,
        contentRichData: Data? = nil,
        contentImageData: Data? = nil,
        contentFilePath: String? = nil,
        contentType: String = "text",
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        previewText: String? = nil
    ) {
        self.id = id
        self.contentText = contentText
        self.contentRichData = contentRichData
        self.contentImageData = contentImageData
        self.contentFilePath = contentFilePath
        self.contentType = contentType
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.previewText = previewText
    }
}

// MARK: - GRDB Record Conformance

extension ClipItem: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "clipItems"

    /// Called after a successful INSERT – captures the auto-generated row ID.
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Column Helpers

extension ClipItem {
    /// Typed column references for building queries.
    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let contentText = Column(CodingKeys.contentText)
        public static let contentType = Column(CodingKeys.contentType)
        public static let sourceAppBundleID = Column(CodingKeys.sourceAppBundleID)
        public static let sourceAppName = Column(CodingKeys.sourceAppName)
        public static let isPinned = Column(CodingKeys.isPinned)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let previewText = Column(CodingKeys.previewText)
    }
}
