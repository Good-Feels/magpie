import SwiftUI
import KeyboardShortcuts

/// Shortcuts tab in the preferences window.
struct ShortcutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionCard("Keyboard Shortcuts") {
                HStack {
                    Text("Toggle Clipboard History")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .toggleClipboardHistory)
                }

                Text("Press this shortcut from any app to show or hide Magpie.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 6)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
