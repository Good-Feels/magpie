import ClipboardEngine
import Foundation

/// Runs the production MCP transport and RPC handler against synthetic clips only.
private actor ClientFixture {
    let directory: URL
    let repository: ClipItemRepository
    let clips: [String: ClipItem]
    var observedIDs: [String: String] = [:]
    var removed: Set<String> = []

    init(directory: URL) throws {
        self.directory = directory
        let database = try DatabaseManager(directoryURL: directory.appendingPathComponent("history"))
        let repository = ClipItemRepository(dbPool: database.dbPool)
        self.repository = repository
        clips = try Dictionary(uniqueKeysWithValues: ["claude", "chatgpt"].map { client in
            let query = "magpie-\(client)-\(directory.lastPathComponent)"
            let text = "\(query)\n" + String(repeating: "synthetic clipboard sample\n", count: 320)
                + "\nProof: \(UUID().uuidString)"
            var clip = ClipItem(contentText: text)
            try repository.insert(&clip)
            return (client, clip)
        })
    }

    func respond(to request: Data) -> Data? {
        for (client, clip) in clips where !removed.contains(client) {
            if FileManager.default.fileExists(atPath: marker(client, "deleted").path) {
                do {
                    try repository.delete(clip)
                    removed.insert(client)
                } catch {
                    fputs("Couldn’t remove the synthetic fixture clip\n", stderr)
                }
            }
        }
        let response = MCPProtocol.respond(to: request, repository: repository)
        guard let response,
              let parameters = (try? JSONSerialization.jsonObject(with: request) as? [String: Any])?["params"] as? [String: Any],
              let tool = parameters["name"] as? String,
              let arguments = parameters["arguments"] as? [String: Any],
              let result = (try? JSONSerialization.jsonObject(with: response) as? [String: Any])?["result"] as? [String: Any],
              let text = (result["content"] as? [[String: String]])?.first?["text"] else { return response }

        for (client, clip) in clips {
            let deleted = removed.contains(client)
            if ["search_clips", "search_shared_clips"].contains(tool), arguments["query"] as? String == query(client),
               let payload = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
               let matches = payload["clips"] as? [[String: String]] {
                if deleted && matches.isEmpty {
                    record(client, "deleted-empty-search")
                } else if !deleted, matches.count == 1, let match = matches.first,
                          let id = match["id"], match["preview"]?.hasPrefix(query(client)) == true {
                    observedIDs[client] = id
                    record(client, "present-search")
                }
            } else if ["get_clip", "get_shared_clip"].contains(tool), let id = observedIDs[client],
                      arguments["id"] as? String == id {
                if deleted && result["isError"] as? Bool == true {
                    record(client, "deleted-fetch-denied")
                } else if !deleted && text == clip.contentText {
                    record(client, "present-fetch")
                }
            }
        }
        return response
    }

    private func query(_ client: String) -> String {
        "magpie-\(client)-\(directory.lastPathComponent)"
    }

    private func marker(_ client: String, _ name: String) -> URL {
        directory.appendingPathComponent("\(client).\(name)")
    }

    private func record(_ client: String, _ scenario: String) {
        try? Data().write(to: marker(client, scenario), options: .atomic)
    }
}

@main
enum MCPLiveClientFixture {
    static func main() throws {
        let directory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let fixture = try ClientFixture(directory: directory)
        let server = try MCPLocalServer(address: .current, onState: { state in
            if case .ready = state {
                print("Magpie fixture ready")
                fflush(stdout)
            } else if case .failed(let error) = state {
                fputs("MCP fixture could not listen: \(error)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }, respond: { request in await fixture.respond(to: request) })
        withExtendedLifetime(server) { _ = readLine() }
    }
}
