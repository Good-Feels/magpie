import Foundation

/// Runs the production MCP transport and RPC handler against synthetic clips only.
private actor ClientFixture {
    let directory: URL
    let clips: [String: MCPSharedClip]

    init(directory: URL) {
        self.directory = directory
        clips = Dictionary(uniqueKeysWithValues: ["claude", "chatgpt"].enumerated().map { index, client in
            let query = "magpie-\(client)-\(directory.lastPathComponent)"
            let text = "\(query)\n" + String(repeating: "synthetic clipboard sample ", count: 12)
                + "\nProof: \(UUID().uuidString)"
            return (client, MCPSharedClip(historyID: Int64(index + 1), text: text, createdAt: .now))
        })
    }

    func respond(to request: Data) -> Data? {
        let shared = clips.filter { !FileManager.default.fileExists(atPath: marker($0.key, "revoked").path) }
        let response = MCPProtocol.respond(to: request, clips: Array(shared.values))
        guard let response,
              let parameters = (try? JSONSerialization.jsonObject(with: request) as? [String: Any])?["params"] as? [String: Any],
              let tool = parameters["name"] as? String,
              let arguments = parameters["arguments"] as? [String: Any],
              let result = (try? JSONSerialization.jsonObject(with: response) as? [String: Any])?["result"] as? [String: Any],
              let text = (result["content"] as? [[String: String]])?.first?["text"] else { return response }

        for (client, clip) in clips {
            let revoked = shared[client] == nil
            if tool == "search_shared_clips", arguments["query"] as? String == query(client),
               let payload = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
               let matches = payload["clips"] as? [[String: String]] {
                if revoked && matches.isEmpty {
                    record(client, "revoked-empty-search")
                } else if !revoked && matches.count == 1 && matches.first?["id"] == clip.id.uuidString {
                    record(client, "shared-search")
                }
            } else if tool == "get_shared_clip", arguments["id"] as? String == clip.id.uuidString {
                if revoked && result["isError"] as? Bool == true {
                    record(client, "revoked-fetch-denied")
                } else if !revoked && text == clip.text {
                    record(client, "shared-fetch")
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
        let fixture = ClientFixture(directory: directory)
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
