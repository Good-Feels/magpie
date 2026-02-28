import SwiftUI

/// General preferences: launch at login, history limits, display options.
struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var loginService = LaunchAtLoginService()

    @AppStorage("maxHistorySize") private var maxHistorySize: Int = 200
    @AppStorage("showSourceApp") private var showSourceApp: Bool = true
    @AppStorage("showTimestamps") private var showTimestamps: Bool = true

    @State private var showClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Startup ──────────────────────────────────────────────
            sectionHeader("Startup")
            Group {
                Toggle("Launch at Login", isOn: $loginService.isEnabled)
                if loginService.statusDescription.contains("not found")
                    || loginService.statusDescription.contains("approval") {
                    Text(loginService.statusDescription)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 4)

            sectionDivider()

            // ── History ──────────────────────────────────────────────
            sectionHeader("History")
            Picker("Max history size", selection: $maxHistorySize) {
                Text("50 clips").tag(50)
                Text("100 clips").tag(100)
                Text("200 clips").tag(200)
                Text("500 clips").tag(500)
                Text("1,000 clips").tag(1000)
                Text("Unlimited").tag(0)
            }
            .labelsHidden()
            .padding(.horizontal, 4)
            .onChange(of: maxHistorySize) { newValue in
                if newValue > 0 {
                    try? appState.repository.enforceHistoryLimit(newValue)
                    appState.loadClips()
                }
            }

            sectionDivider()

            // ── Display ──────────────────────────────────────────────
            sectionHeader("Display")
            Group {
                Toggle("Show source app name", isOn: $showSourceApp)
                Toggle("Show timestamps", isOn: $showTimestamps)
            }
            .padding(.horizontal, 4)

            sectionDivider()

            // ── Data ─────────────────────────────────────────────────
            sectionHeader("Data")
            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("Clear All History")
                }
            }
            .padding(.horizontal, 4)
            .confirmationDialog(
                "Clear all clipboard history?",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) {
                    appState.clearAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all saved clips. Pinned clips will also be removed.")
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.bottom, 6)
    }

    private func sectionDivider() -> some View {
        Divider()
            .padding(.vertical, 12)
    }
}
