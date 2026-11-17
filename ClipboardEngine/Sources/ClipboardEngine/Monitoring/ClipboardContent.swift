import AppKit
import Foundation

/// Converts an allowed pasteboard snapshot to one persisted clip. No network or
/// file-content reads. Call on the main actor before yielding the polling callback.
@MainActor
public enum ClipboardContent {
    public static func read(
        from pasteboard: NSPasteboard,
        sourceBundleID: String?,
        sourceAppName: String?,
        observedSourceBundleIDs: Set<String>,
        excludedBundleIDs: Set<String>
    ) -> ClipItem? {
        let generation = pasteboard.changeCount
        let items = pasteboard.pasteboardItems ?? []
        let types = Set((pasteboard.types ?? []) + items.flatMap(\.types))
        var sourceIDs = observedSourceBundleIDs
        if let sourceBundleID { sourceIDs.insert(sourceBundleID) }

        // Inspect type metadata first. Never decode any representation of a
        // confidential/transient item, including a marker on a later file item.
        guard ClipboardCapturePolicy.allows(types: types, sourceBundleIDs: sourceIDs,
                                           excludedBundleIDs: excludedBundleIDs) else { return nil }
        for item in items {
            if let hintedSource = item.string(forType: ClipboardCapturePolicy.sourceType) {
                sourceIDs.insert(hintedSource)
            }
        }
        guard sourceIDs.isDisjoint(with: excludedBundleIDs) else { return nil }

        var clip = ClipItem(sourceAppBundleID: sourceBundleID, sourceAppName: sourceAppName)
        if types.contains(.fileURL) {
            let paths = items.compactMap { item -> String? in
                guard let raw = item.string(forType: .fileURL),
                      let url = URL(string: raw), url.isFileURL else { return nil }
                return url.path
            }
            guard !paths.isEmpty else { return nil }
            clip.contentType = "filePath"
            clip.contentFilePath = paths[0]
            clip.contentFilePathsJSON = try? String(data: JSONEncoder().encode(paths), encoding: .utf8)
            clip.contentText = paths.joined(separator: "\n")
            let names = paths.map { URL(fileURLWithPath: $0).lastPathComponent }
            clip.previewText = paths.count == 1 ? names[0] : "\(paths.count) files: " + names.joined(separator: ", ")
        } else if types.contains(.png) || types.contains(.tiff) {
            var imageData = pasteboard.data(forType: .png)
            if imageData == nil, let tiff = pasteboard.data(forType: .tiff),
               let bitmap = NSBitmapImageRep(data: tiff) {
                imageData = bitmap.representation(using: .png, properties: [:])
            }
            guard let imageData else { return nil }
            clip.contentType = "image"
            clip.contentImageData = imageData
            clip.contentText = pasteboard.string(forType: .string)
            clip.previewText = clip.contentText.map { String($0.prefix(200)) } ?? "[Image]"
        } else if types.contains(.rtf) {
            clip.contentRichData = pasteboard.data(forType: .rtf)
            clip.contentText = pasteboard.string(forType: .string)
            guard clip.contentRichData != nil || clip.contentText != nil else { return nil }
            clip.contentType = "richText"
            clip.previewText = clip.contentText.map { String($0.prefix(200)) }
        } else if let text = pasteboard.string(forType: .string),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clip.contentText = text
            clip.previewText = String(text.prefix(200))
        } else {
            return nil
        }
        // An external writer may replace the clipboard while a lazy data provider
        // resolves a payload. Metadata from one generation cannot authorize another.
        guard pasteboard.changeCount == generation else { return nil }
        return clip
    }

    /// Writes every file reference together. Invalid/empty saved payloads leave
    /// the destination pasteboard untouched and do not report a successful copy.
    @discardableResult
    public static func restore(_ clip: ClipItem, to pasteboard: NSPasteboard) -> Bool {
        if clip.contentType == "filePath" {
            let urls = clip.filePaths.map { NSURL(fileURLWithPath: $0) }
            guard !urls.isEmpty else { return false }
            pasteboard.clearContents()
            return pasteboard.writeObjects(urls)
        }

        let item = NSPasteboardItem()
        if clip.contentType == "image", let data = clip.contentImageData {
            item.setData(data, forType: .png)
        } else if clip.contentType == "richText", let data = clip.contentRichData {
            item.setData(data, forType: .rtf)
        }
        if let text = clip.contentText { item.setString(text, forType: .string) }
        guard !item.types.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}
