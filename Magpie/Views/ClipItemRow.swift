import SwiftUI
import AppKit
import ClipboardEngine

/// A single row in the clipboard history list.
/// Shows a source app icon, the text preview (or image thumbnail),
/// source app name, and a relative timestamp.
/// When `showCopied` is true, a "Copied!" overlay animates in.
struct ClipItemRow: View {
    let item: ClipItem
    let isHovered: Bool
    let showCopied: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void

    @State private var appIcon: NSImage?

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                // ── Main content ────────────────────────────────────
                rowContent
                    .opacity(showCopied ? 0.15 : 1.0)

                // ── "Copied!" overlay ───────────────────────────────
                if showCopied {
                    copiedOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showCopied)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(item.isPinned ? "Unpin" : "Pin") {
                onTogglePin()
            }
            Divider()
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
        .onAppear { loadAppIcon() }
    }

    // MARK: - Row Content

    private var rowContent: some View {
        HStack(spacing: 10) {
            // Source app icon (or content-type fallback)
            sourceIcon
                .frame(width: 24, height: 24)

            // Text preview or image thumbnail + metadata
            VStack(alignment: .leading, spacing: 3) {
                contentPreview

                HStack(spacing: 6) {
                    if let appName = item.sourceAppName {
                        Text(appName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    Text("\u{00B7}")
                        .foregroundColor(.secondary.opacity(0.5))

                    Text(item.createdAt, style: .relative)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))

                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer(minLength: 4)

            // Size badge
            sizeBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
        )
    }

    // MARK: - Content Preview

    @ViewBuilder
    private var contentPreview: some View {
        switch item.contentType {
        case "image":
            if let imageData = item.contentImageData,
               let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 48)
                    .cornerRadius(4)
            } else {
                Text("[Image]")
                    .lineLimit(1)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        case "filePath":
            HStack(spacing: 4) {
                Image(systemName: "doc")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(item.contentFilePath ?? item.previewText ?? "")
                    .lineLimit(2)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
            }
        default:
            Text(item.previewText ?? item.contentText ?? "")
                .lineLimit(2)
                .font(.system(size: 12))
                .foregroundColor(.primary)
        }
    }

    // MARK: - Source App Icon

    @ViewBuilder
    private var sourceIcon: some View {
        if let icon = appIcon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 24, height: 24)
                .cornerRadius(4)
        } else {
            contentTypeIcon
                .foregroundColor(.accentColor.opacity(0.8))
        }
    }

    @ViewBuilder
    private var contentTypeIcon: some View {
        switch item.contentType {
        case "image":
            Image(systemName: "photo")
        case "richText":
            Image(systemName: "doc.richtext")
        case "filePath":
            Image(systemName: "folder")
        default:
            Image(systemName: "doc.text")
        }
    }

    // MARK: - Size Badge

    @ViewBuilder
    private var sizeBadge: some View {
        if item.contentType == "image", let data = item.contentImageData {
            Text(formatBytes(data.count))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.1))
                )
        } else if let text = item.contentText {
            Text("\(text.count)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.1))
                )
        }
    }

    // MARK: - Copied Overlay

    private var copiedOverlay: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.green)
            Text("Copied!")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func loadAppIcon() {
        guard let bundleID = item.sourceAppBundleID else { return }
        appIcon = AppResolver.iconForBundleID(bundleID)
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024
        return String(format: "%.1f MB", mb)
    }
}
