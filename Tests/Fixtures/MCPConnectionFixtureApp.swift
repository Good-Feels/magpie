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
    @StateObject private var access: MCPHistoryAccess
    @State private var fixtureID: Int64?
    private let repository: ClipItemRepository

    init() {
        let temp = FileManager.default.temporaryDirectory
        let database = try! DatabaseManager(directoryURL: temp.appendingPathComponent(UUID().uuidString))
        let repository = ClipItemRepository(dbPool: database.dbPool)
        self.repository = repository
        _access = StateObject(wrappedValue: MCPHistoryAccess(repository: repository))
        let proof = UUID().uuidString
        let text = "magpie-button-fixture\n" + String(repeating: "synthetic clip\n", count: 60) + "Proof: \(proof)"
        var clip = ClipItem(contentText: text, createdAt: Date(timeIntervalSince1970: 0))
        try! repository.insert(&clip)
        _fixtureID = State(initialValue: clip.id)
        for index in 1...72 {
            var newer = ClipItem(contentText: "Synthetic newer history clip \(index)",
                                 createdAt: Date(timeIntervalSince1970: Double(index)))
            try! repository.insert(&newer)
        }
        try! proof.write(to: temp.appendingPathComponent("magpie-fixture-proof.txt"), atomically: true, encoding: .utf8)
    }

    var body: some Scene {
        WindowGroup("Magpie Connection QA") {
            VStack {
                MCPSettingsView(history: access)
                Button("Delete Synthetic Clip", action: deleteClip)
                    .disabled(fixtureID == nil)
                    .padding(.bottom, 12)
            }
            .frame(width: 560, height: 590)
        }
    }

    @MainActor
    private func deleteClip() {
        guard let fixtureID else { return }
        try! repository.delete(id: fixtureID)
        self.fixtureID = nil
    }
}
