import SwiftUI

/// General preferences: history limits, display options, launch at login.
struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var loginService = LaunchAtLoginService()

    @AppStorage("maxHistorySize") private var maxHistorySize: Int = 200
    @AppStorage("showSourceApp") private var showSourceApp: Bool = true
    @AppStorage("showTimestamps") private var showTimestamps: Bool = true
    @AppStorage("pasteOnSelect") private var pasteOnSelect: Bool = false

    @State private var showClearConfirmation = false

    var body: some View {
        Form {
            // ── Startup ─────────────────────────────────────────────
            Section {
                Toggle("Launch at Login", isOn: $loginService.isEnabled)

                if loginService.statusDescription.contains("not found")
                    || loginService.statusDescription.contains("approval") {
                    Text(loginService.statusDescription)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } header: {
                Text("Startup")
            }

            // ── History ─────────────────────────────────────────────
            Section {
                Picker("Max history size:", selection: $maxHistorySize) {
                    Text("50 clips").tag(50)
                    Text("100 clips").tag(100)
                    Text("200 clips").tag(200)
                    Text("500 clips").tag(500)
                    Text("1,000 clips").tag(1000)
                    Text("Unlimited").tag(0)
                }
                .onChange(of: maxHistorySize) { newValue in
                    if newValue > 0 {
                        try? appState.repository.enforceHistoryLimit(newValue)
                        appState.loadClips()
                    }
                }
            } header: {
                Text("History")
            }

            // ── Display ─────────────────────────────────────────────
            Section {
                Toggle("Show source app name", isOn: $showSourceApp)
                Toggle("Show timestamps", isOn: $showTimestamps)
            } header: {
                Text("Display")
            }

            // ── Danger Zone ─────────────────────────────────────────
            Section {
                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear All History")
                    }
                }
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
            } header: {
                Text("Data")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
