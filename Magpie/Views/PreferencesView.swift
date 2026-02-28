import SwiftUI

/// Tabbed preferences window: General, Exclusions, About.
struct PreferencesView: View {
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

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .padding(.top, 8)
        .frame(width: 440, height: 480)
    }
}
