import AppKit
import ClipboardEngine
import SwiftUI

@main
enum MCPConnectionFixtureEntry {
    @MainActor
    static func main() {
        let temp = FileManager.default.temporaryDirectory
        setenv("LLVM_PROFILE_FILE", temp.appendingPathComponent("magpie-qa-%p.profraw").path, 1)
        if CommandLine.arguments.dropFirst().first == "--mcp-stdio" {
            MCPStdioBridge.run()
        } else {
            MCPConnectionFixtureApp.main()
        }
    }
}

private struct MCPConnectionFixtureApp: App {
    @StateObject private var sharing = MCPSharing()

    var body: some Scene {
        WindowGroup("Magpie Connection QA") {
            VStack {
                MCPSettingsView(sharing: sharing)
                Button(sharing.contains(1) ? "Revoke Synthetic Clip" : "Share Synthetic Clip", action: toggleClip)
                    .disabled(!sharing.isAvailable)
                    .padding(.bottom, 12)
            }
            .frame(width: 560, height: 590)
        }
    }

    @MainActor
    private func toggleClip() {
        if sharing.contains(1) {
            sharing.clear()
            return
        }
        let query = "magpie-button-fixture"
        let proof = UUID().uuidString
        let text = query + "\n" + String(repeating: "synthetic clip\n", count: 60) + "Proof: \(proof)"
        sharing.toggle(ClipItem(id: 1, contentText: text))
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("magpie-fixture-proof.txt")
        try? proof.write(to: cache, atomically: true, encoding: .utf8)
    }
}
