import SwiftUI
import ClipboardEngine

/// The main popover content: search bar at top, scrollable clip history,
/// and a footer with Settings / Quit.
struct ClipboardHistoryView: View {
    @EnvironmentObject var appState: AppState

    @State private var hoveredClipID: Int64?

    var body: some View {
        VStack(spacing: 0) {
            // ── Search Bar ──────────────────────────────────────────
            SearchBar(text: $appState.searchText)

            Divider()

            // ── Header ──────────────────────────────────────────────
            headerBar

            Divider()

            // ── Clip List ───────────────────────────────────────────
            if !appState.accessChecker.hasAccess {
                ClipboardPermissionView(accessChecker: appState.accessChecker)
            } else if appState.displayedClips.isEmpty {
                emptyState
            } else {
                clipList
            }

            Divider()

            // ── Footer ──────────────────────────────────────────────
            footerBar
        }
        .frame(width: 360, height: 520)
        .onAppear {
            appState.loadClips()
        }
    }

    // MARK: - Subviews

    private var headerBar: some View {
        HStack {
            Text("🐦‍⬛")
                .font(.system(size: 14))
            Text("Magpie")
                .font(.headline)
            Spacer()
            Text("\(appState.displayedClips.count) items")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var clipList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(appState.displayedClips) { clip in
                    ClipItemRow(
                        item: clip,
                        isHovered: hoveredClipID == clip.id,
                        showCopied: appState.copiedItemID == clip.id,
                        onSelect: {
                            appState.copyToClipboard(clip)
                        },
                        onDelete: {
                            appState.deleteClip(clip)
                        },
                        onTogglePin: {
                            appState.togglePin(clip)
                        }
                    )
                    .onHover { isHovering in
                        hoveredClipID = isHovering ? clip.id : nil
                    }

                    if clip.id != appState.displayedClips.last?.id {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            if appState.searchText.isEmpty {
                Image(systemName: "clipboard")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("No clips yet")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text("Copy something to get started")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("No results")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text("No clips match \"\(appState.searchText)\"")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footerBar: some View {
        HStack(spacing: 12) {
            Button {
                openSettings()
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("Settings")

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func openSettings() {
        appState.openSettings()
    }
}
