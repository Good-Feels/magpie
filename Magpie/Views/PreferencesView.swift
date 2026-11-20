import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AppExclusionsView()
                .tabItem {
                    Label("Exclusions", systemImage: "xmark.app")
                }

            ShortcutSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            MCPSettingsView(sharing: appState.mcpSharing)
                .tabItem {
                    Label("MCP", systemImage: "link")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .frame(width: 560, height: 650)
    }
}
