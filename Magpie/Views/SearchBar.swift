import SwiftUI

/// A search/filter bar for the clipboard history.
/// Includes a magnifying glass icon, text field, and a clear button.
struct SearchBar: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            TextField("Search clips\u{2026}", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .onAppear { isFocused = true }
        .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
    }
}
