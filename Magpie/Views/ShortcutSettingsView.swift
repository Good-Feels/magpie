import SwiftUI
import KeyboardShortcuts

/// Shortcuts tab in the preferences window.
///
/// Uses simple controls instead of `KeyboardShortcuts.Recorder` because
/// Recorder currently crashes in this app on macOS 15 when the tab opens.
struct ShortcutSettingsView: View {
    @State private var hasShortcut = KeyboardShortcuts.getShortcut(for: .toggleClipboardHistory) != nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionCard("Keyboard Shortcut") {
                HStack {
                    Text("Toggle Clipboard History")
                    Spacer()
                    Text(hasShortcut ? "Configured" : "Not set")
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 10) {
                    Button("Set Default (⌘⇧V)") {
                        KeyboardShortcuts.setShortcut(
                            .init(.v, modifiers: [.command, .shift]),
                            for: .toggleClipboardHistory
                        )
                        refresh()
                    }

                    Button("Clear Shortcut") {
                        KeyboardShortcuts.setShortcut(nil, for: .toggleClipboardHistory)
                        refresh()
                    }
                }

                Text("Temporary fallback UI while we fix the recorder crash on macOS 15.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 6)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            refresh()
        }
    }

    private func refresh() {
        hasShortcut = KeyboardShortcuts.getShortcut(for: .toggleClipboardHistory) != nil
    }

    private func sectionCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }
}
