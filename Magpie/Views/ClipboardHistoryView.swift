import SwiftUI
import ClipboardEngine

/// The main popover content: search bar at top, scrollable clip history,
/// and a footer with Settings / Quit.
struct ClipboardHistoryView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // ── Search Bar ──────────────────────────────────────────
            SearchBar(text: $appState.searchText)

            Divider()

            // ── Header ──────────────────────────────────────────────
            headerBar

            Divider()

            // ── Clip List ───────────────────────────────────────────
            if appState.databaseError != nil {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.largeTitle)
                    Text("Clipboard saving is paused").font(.headline)
                    Text("Magpie could not open its history. Your saved history has been preserved. Quit and reopen Magpie to try again.")
                        .font(.caption).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !appState.accessChecker.hasAccess {
                ClipboardPermissionView(accessChecker: appState.accessChecker)
            } else if appState.historyEntries.isEmpty && appState.historyReadFailed {
                HistoryRetryView(action: appState.retryHistory)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.historyCount == nil {
                ProgressView("Loading clips…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.historyEntries.isEmpty {
                emptyState
            } else {
                ClipHistoryList()
            }

            Divider()

            // ── Footer ──────────────────────────────────────────────
            footerBar
        }
        .frame(width: 360, height: 520)
    }

    // MARK: - Subviews

    private var headerBar: some View {
        HStack {
            Text("🐦‍⬛")
                .font(.system(size: 14))
            Text("Magpie")
                .font(.headline)
            Spacer()
            if let count = appState.historyCount {
                Text("\(count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
                AppSessionDiagnostics.shared.markIntentionalQuit()
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

struct ClipHistoryList: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(appState.historyEntries) { entry in
                    VStack(spacing: 0) {
                        ClipItemRow(
                            item: entry,
                            showCopied: appState.copiedItemID == entry.id,
                            onSelect: { appState.copyToClipboard(id: entry.id) },
                            onDelete: { appState.deleteClip(id: entry.id) },
                            onTogglePin: { appState.togglePin(id: entry.id) },
                            loadThumbnail: { await appState.thumbnail(for: entry.id) }
                        )
                        if entry.id != appState.historyEntries.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }

                if appState.historyReadFailed {
                    HistoryRetryView(action: appState.retryHistory).padding(12)
                } else if appState.hasMoreHistory, let last = appState.historyEntries.last {
                    ProgressView("Loading more clips…")
                        .controlSize(.small)
                        .padding(12)
                        .task(id: appState.isRefreshingHistory) {
                            appState.loadMoreHistory(after: last)
                        }
                        .id(last.id)
                }
            }
        }
    }
}

private struct HistoryRetryView: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("Couldn’t load clips.").foregroundStyle(.secondary)
            Button("Try Again", action: action)
        }
    }
}
