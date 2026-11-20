import SwiftUI

enum PreferencesTab: Hashable {
    case general, exclusions, shortcuts, mcp, about
}

struct PreferencesView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.preferencesTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(PreferencesTab.general)

            AppExclusionsView()
                .tabItem {
                    Label("Exclusions", systemImage: "xmark.app")
                }
                .tag(PreferencesTab.exclusions)

            ShortcutSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                .tag(PreferencesTab.shortcuts)

            MCPSettingsView(history: appState.mcpHistory)
                .tabItem {
                    Label("MCP", systemImage: "link")
                }
                .tag(PreferencesTab.mcp)

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(PreferencesTab.about)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .frame(width: 560, height: 650)
    }
}
