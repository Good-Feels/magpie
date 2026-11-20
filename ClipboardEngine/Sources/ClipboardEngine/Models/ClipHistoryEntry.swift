import Foundation
import GRDB

/// The bounded preview and metadata needed by the history list.
public struct ClipHistoryEntry: Identifiable, Equatable, Sendable, FetchableRecord {
    public let id: Int64
    public let contentType: String
    public let previewText: String
    public let textLength: Int?
    public let textByteCount: Int?
    public let imageByteCount: Int?
    public let sourceAppBundleID: String?
    public let sourceAppName: String?
    public let isPinned: Bool
    public let createdAt: Date

    // Keep SQLite's stored value for the page boundary, including its precision.
    let sortTimestamp: DatabaseValue

    public init(row: Row) {
        id = row["id"]
        contentType = row["contentType"]
        textLength = row["textLength"]
        textByteCount = row["textByteCount"]
        imageByteCount = row["imageByteCount"]
        sourceAppBundleID = row["sourceAppBundleID"]
        sourceAppName = row["sourceAppName"]
        isPinned = row["isPinned"]
        createdAt = row["createdAt"]
        sortTimestamp = row["createdAt"]

        let preview: String? = row["previewText"]
        if contentType == "filePath" {
            let path: String? = row["contentFilePath"]
            let file = ClipItem(contentFilePath: path, contentFilePathsJSON: row["contentFilePathsJSON"])
            let fileCount = file.filePaths.count
            previewText = fileCount > 1 ? (preview ?? "\(fileCount) files") : (path ?? preview ?? "")
        } else {
            previewText = preview ?? ""
        }
    }
}
