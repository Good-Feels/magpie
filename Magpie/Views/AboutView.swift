import SwiftUI

/// About tab in the preferences window.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("🐦‍⬛")
                .font(.system(size: 56))

            Text("Magpie")
                .font(.title2.bold())

            Text("Version 1.0")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Copy freely. Everything is saved.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Divider()
                .frame(width: 200)

            VStack(spacing: 6) {
                featureRow(icon: "magnifyingglass", text: "Search your clipboard history")
                featureRow(icon: "pin.fill", text: "Pin your favorite clips")
                featureRow(icon: "keyboard", text: "Global keyboard shortcut (coming soon)")
                featureRow(icon: "xmark.app", text: "Exclude sensitive apps")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
