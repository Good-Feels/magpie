import SwiftUI
import AppKit
import ClipboardEngine

@main
enum MagpieEntryPoint {
    @MainActor
    static func main() {
        if CommandLine.arguments.dropFirst().first == "--mcp-stdio" {
            MCPStdioBridge.run()
        } else {
            MagpieApp.main()
        }
    }
}

struct MagpieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The menu bar icon and popover are managed by AppDelegate
        // using NSStatusItem + NSPopover for reliable behavior.
        // This Settings scene is kept as a fallback for the standard
        // macOS app menu, but the primary path is AppDelegate.openSettings().
        Settings {
            PreferencesView()
                .environmentObject(appDelegate.appState)
                .environmentObject(appDelegate.appState.exclusionManager)
        }
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Magpie") {
                    AppSessionDiagnostics.shared.markIntentionalQuit()
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}
