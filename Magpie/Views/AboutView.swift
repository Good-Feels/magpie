import SwiftUI

/// About tab in the preferences window.
struct AboutView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            VStack(spacing: 12) {
                Text("🐦‍⬛")
                    .font(.system(size: 56))

                Text("Magpie")
                    .font(.title2.bold())

                Text("Version 1.0.0")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Copy freely. Everything is saved.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)

            VStack(spacing: 8) {
                featureRow(icon: "magnifyingglass", text: "Search your clipboard history")
                featureRow(icon: "pin.fill", text: "Pin your favorite clips")
                featureRow(icon: "keyboard", text: "Global keyboard shortcut")
                featureRow(icon: "xmark.app", text: "Exclude sensitive apps")
            }
            .padding(14)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )

            Spacer(minLength: 6)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
